import Foundation
import HighlightKit

enum ClientError: Error {
    case unreachable(String)
    case appUnavailable(String)

    var message: String {
        switch self {
        case .unreachable(let detail): return "cannot reach AgentHighlight: \(detail)"
        case .appUnavailable(let detail): return detail
        }
    }
}

struct Client {
    let port: Int
    private let timeout: TimeInterval = 20

    var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    func health() -> HealthResponse? {
        guard let (status, data) = try? get("/health"), status == 200 else { return nil }
        return try? JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func get(_ path: String, query: [String: String] = [:]) throws -> (Int, Data) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items.isEmpty ? nil : items
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = "GET"
        return try send(request)
    }

    func post<T: Encodable>(_ path: String, _ body: T) throws -> (Int, Data) {
        try postRaw(path, try JSONEncoder().encode(body))
    }

    func postRaw(_ path: String, _ data: Data) throws -> (Int, Data) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try send(request)
    }

    private func send(_ request: URLRequest) throws -> (Int, Data) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Int, Data), Error> = .failure(ClientError.unreachable("no response"))
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(ClientError.unreachable(error.localizedDescription))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            result = .success((status, data ?? Data()))
        }
        task.resume()
        semaphore.wait()
        return try result.get()
    }
}
