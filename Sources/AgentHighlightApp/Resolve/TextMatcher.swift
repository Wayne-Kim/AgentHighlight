import Foundation
import HighlightKit

struct TextMatcher {
    let query: String
    let mode: MatchMode
    private let normalizedQuery: String
    private let regex: NSRegularExpression?

    init(query: String, mode: MatchMode) {
        self.query = query
        self.mode = mode
        normalizedQuery = Self.normalize(query)
        regex = mode == .regex ? try? NSRegularExpression(pattern: query, options: [.caseInsensitive]) : nil
    }

    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func score(_ candidate: String) -> Int? {
        switch mode {
        case .regex:
            guard let regex, regex.firstMatch(in: candidate, range: fullRange(candidate)) != nil else { return nil }
            return 1
        case .exact:
            return Self.normalize(candidate) == normalizedQuery ? 3 : nil
        case .contains:
            let normalized = Self.normalize(candidate)
            guard !normalized.isEmpty, !normalizedQuery.isEmpty else { return nil }
            if normalized == normalizedQuery { return 3 }
            if normalized.hasPrefix(normalizedQuery) { return 2 }
            if normalized.contains(normalizedQuery) { return 1 }
            return nil
        }
    }

    func range(in candidate: String) -> NSRange? {
        if mode == .regex {
            return regex?.firstMatch(in: candidate, range: fullRange(candidate))?.range
        }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        guard let found = candidate.range(of: query, options: options) else { return nil }
        return NSRange(found, in: candidate)
    }

    private func fullRange(_ text: String) -> NSRange {
        NSRange(text.startIndex..., in: text)
    }
}
