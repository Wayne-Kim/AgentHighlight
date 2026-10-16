import Foundation

struct Arguments {
    private(set) var positionals: [String] = []
    private(set) var flags: Set<String> = []
    private(set) var options: [String: String] = [:]

    init(_ argv: [String]) {
        var index = 0
        while index < argv.count {
            let token = argv[index]
            defer { index += 1 }
            if token == "--" {
                positionals.append(contentsOf: argv[(index + 1)...])
                return
            }
            guard token.hasPrefix("--") else {
                positionals.append(token)
                continue
            }
            let body = String(token.dropFirst(2))
            if let equals = body.firstIndex(of: "=") {
                options[String(body[..<equals])] = String(body[body.index(after: equals)...])
            } else if body.hasPrefix("no-") {
                flags.insert(body)
            } else if index + 1 < argv.count, !argv[index + 1].hasPrefix("--") {
                options[body] = argv[index + 1]
                index += 1
            } else {
                flags.insert(body)
            }
        }
    }

    func option(_ name: String) -> String? {
        options[name]
    }

    func double(_ name: String) -> Double? {
        options[name].flatMap(Double.init)
    }

    func int(_ name: String) -> Int? {
        options[name].flatMap(Int.init)
    }

    func has(_ flag: String) -> Bool {
        flags.contains(flag)
    }
}
