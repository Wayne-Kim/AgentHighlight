import Foundation

enum Output {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static func print<T: Encodable>(_ value: T) {
        guard let data = try? encoder.encode(value) else { return }
        printRaw(data)
    }

    static func printRaw(_ data: Data) {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let text = String(data: pretty, encoding: .utf8) {
            Swift.print(text)
        } else {
            Swift.print(String(decoding: data, as: UTF8.self))
        }
    }

    static func fail(_ message: String, code: Int32) -> Int32 {
        print(["ok": AnyEncodable(false), "error": AnyEncodable(message)])
        return code
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
