import AppKit
import HighlightKit

struct OverlayItem {
    var rect: CGRect
    var label: String?
    var number: Int?
    var step: StepCard?
}

struct StepCard {
    var number: Int
    var total: Int
    var title: String?
    var note: String?
    var nextTitle: String?
    var hasPrevious: Bool
}

struct OverlayStyle {
    var color: NSColor
    var dim: Bool

    static let dimDefaultsKey = "dimOutside"

    static var `default`: OverlayStyle {
        OverlayStyle(color: NSColor(hex: Defaults.color) ?? .systemRed, dim: UserDefaults.standard.bool(forKey: dimDefaultsKey))
    }

    static func from(_ style: Style?) -> OverlayStyle {
        var result = OverlayStyle.default
        if let hex = style?.color, let color = NSColor(hex: hex) { result.color = color }
        if let dim = style?.dim { result.dim = dim }
        return result
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
