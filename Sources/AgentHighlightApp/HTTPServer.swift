import Foundation
import Network

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data
}

struct HTTPResponse {
    var status: Int
    var body: Data
    var contentType: String = "application/json"

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data("{\"ok\":false,\"error\":\"encoding failed\"}".utf8)
        return HTTPResponse(status: status, body: data)
    }

    static func error(_ message: String, status: Int) -> HTTPResponse {
        json(["ok": AnyEncodable(false), "error": AnyEncodable(message)], status: status)
    }

    var reasonPhrase: String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }

    var serialized: Data {
        var head = "HTTP/1.1 \(status) \(reasonPhrase)\r\n"
        head += "Content-Type: \(contentType); charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        encodeValue = { encoder in try value.encode(to: encoder) }
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

final class HTTPServer {
    typealias Handler = (HTTPRequest) -> HTTPResponse

    private static let maxBodyBytes = 1_000_000
    private static let maxHeaderBytes = 16_384
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    private let listener: NWListener
    private let handler: Handler
    private let port: UInt16
    private let queue = DispatchQueue(label: "agenthighlight.http")

    init(port: UInt16, handler: @escaping Handler) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: parameters)
        self.handler = handler
        self.port = port
    }

    func start(onFailure: @escaping (Error) -> Void) {
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { onFailure(error) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            if error != nil {
                connection.cancel()
                return
            }
            switch self.parse(buffer) {
            case .incomplete where !isComplete:
                self.receive(on: connection, buffer: buffer)
            case .incomplete:
                self.send(.error("incomplete request", status: 400), on: connection)
            case .tooLarge:
                self.send(.error("request exceeds size limits", status: 413), on: connection)
            case .malformed:
                self.send(.error("malformed request", status: 400), on: connection)
            case .forbidden(let reason):
                self.send(.error(reason, status: 403), on: connection)
            case .request(let request):
                self.send(self.handler(request), on: connection)
            }
        }
    }

    private enum ParseResult {
        case incomplete
        case tooLarge
        case malformed
        case forbidden(String)
        case request(HTTPRequest)
    }

    private func parse(_ buffer: Data) -> ParseResult {
        guard let headerEnd = buffer.range(of: Self.headerTerminator) else {
            return buffer.count > Self.maxHeaderBytes ? .tooLarge : .incomplete
        }
        guard let headerText = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .malformed
        }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2 else { return .malformed }
        let method = String(requestLine[0]).uppercased()
        let target = String(requestLine[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            headers[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        if let reason = originPolicyViolation(headers) { return .forbidden(reason) }

        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        guard contentLength >= 0 else { return .malformed }
        if contentLength > Self.maxBodyBytes { return .tooLarge }

        let body = buffer[headerEnd.upperBound...]
        if body.count < contentLength { return .incomplete }

        let components = URLComponents(string: "http://localhost" + target)
        let path = components?.path ?? target
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }

        return .request(HTTPRequest(
            method: method,
            path: path,
            query: query,
            headers: headers,
            body: Data(body.prefix(contentLength))
        ))
    }

    private func originPolicyViolation(_ headers: [String: String]) -> String? {
        if headers["origin"] != nil {
            return "browser-origin requests are not accepted"
        }
        let allowedHosts: Set<String> = ["127.0.0.1", "localhost", "127.0.0.1:\(port)", "localhost:\(port)"]
        if let host = headers["host"]?.lowercased(), !allowedHosts.contains(host) {
            return "host must be 127.0.0.1:\(port)"
        }
        return nil
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
