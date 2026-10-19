import AppKit

final class StepCardView: NSView {
    private static let width: CGFloat = 380
    private static let padding: CGFloat = 14
    private static let rowGap: CGFloat = 8
    private static let badgeHeight: CGFloat = 22
    private static let badgeGap: CGFloat = 8

    override var isFlipped: Bool { true }

    init(card: StepCard, badgeColor: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: "#1C1C1E")!.withAlphaComponent(0.94).cgColor
        layer?.cornerRadius = 12

        let contentWidth = Self.width - Self.padding * 2
        var cursorY = Self.padding

        let badge = makeBadge(text: "\(card.number) / \(card.total)", color: badgeColor)
        badge.frame.origin = CGPoint(x: Self.padding, y: cursorY)
        addSubview(badge)

        let titleX = Self.padding + badge.frame.width + Self.badgeGap
        if let title = card.title, !title.isEmpty {
            let field = makeField(title, size: 15, weight: .semibold, alpha: 1, width: Self.width - Self.padding - titleX, lines: 3)
            field.frame.origin = CGPoint(x: titleX, y: cursorY + max(0, (Self.badgeHeight - field.frame.height) / 2))
            addSubview(field)
            cursorY += max(Self.badgeHeight, field.frame.height)
        } else {
            cursorY += Self.badgeHeight
        }

        if let note = card.note, !note.isEmpty {
            cursorY += Self.rowGap + 2
            let field = makeField(note, size: 13, weight: .regular, alpha: 0.85, width: contentWidth, lines: 10)
            field.frame.origin = CGPoint(x: Self.padding, y: cursorY)
            addSubview(field)
            cursorY += field.frame.height
        }

        cursorY += Self.rowGap + 4
        let divider = NSView(frame: CGRect(x: Self.padding, y: cursorY, width: contentWidth, height: 1))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        addSubview(divider)
        cursorY += 1 + Self.rowGap

        if let nextTitle = card.nextTitle {
            let field = makeField("다음  \(card.number + 1). \(nextTitle)", size: 12, weight: .medium, alpha: 0.6, width: contentWidth, lines: 1)
            field.frame.origin = CGPoint(x: Self.padding, y: cursorY)
            addSubview(field)
            cursorY += field.frame.height + 4
        }

        let hint = makeField(keyHint(for: card), size: 11, weight: .regular, alpha: 0.5, width: contentWidth, lines: 1)
        hint.frame.origin = CGPoint(x: Self.padding, y: cursorY)
        addSubview(hint)
        cursorY += hint.frame.height + Self.padding

        frame = CGRect(x: 0, y: 0, width: Self.width, height: cursorY)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func keyHint(for card: StepCard) -> String {
        var parts: [String] = []
        if card.hasPrevious { parts.append("← 이전") }
        parts.append(card.number < card.total ? "→ 다음" : "→ 마치기")
        parts.append("esc 닫기")
        return parts.joined(separator: "   ")
    }

    private func makeBadge(text: String, color: NSColor) -> NSView {
        let digits = NSTextField(labelWithString: text)
        digits.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        digits.textColor = .white
        digits.alignment = .center
        digits.sizeToFit()

        let width = max(Self.badgeHeight, digits.frame.width + 14)
        let badge = NSView(frame: CGRect(x: 0, y: 0, width: width, height: Self.badgeHeight))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = color.cgColor
        badge.layer?.cornerRadius = Self.badgeHeight / 2
        digits.frame = CGRect(x: 0, y: (Self.badgeHeight - digits.frame.height) / 2, width: width, height: digits.frame.height)
        badge.addSubview(digits)
        return badge
    }

    private func makeField(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, width: CGFloat, lines: Int) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = NSColor.white.withAlphaComponent(alpha)
        field.maximumNumberOfLines = lines
        field.lineBreakMode = .byWordWrapping
        field.cell?.truncatesLastVisibleLine = true
        field.preferredMaxLayoutWidth = width
        let fitted = field.cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)) ?? .zero
        let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: field.font!))
        field.frame.size = CGSize(width: width, height: min(ceil(fitted.height), lineHeight * CGFloat(lines)))
        return field
    }
}
