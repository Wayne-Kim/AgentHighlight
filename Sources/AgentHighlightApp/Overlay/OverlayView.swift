import AppKit
import HighlightKit

final class OverlayView: NSView {
    private static let rippleSpread: CGFloat = 12
    private static let rippleDuration: CFTimeInterval = 0.7
    private static let rippleCount: Float = 2

    private let dimLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        dimLayer.fillRule = .evenOdd
        layer?.addSublayer(dimLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func render(items: [OverlayItem], style: OverlayStyle) {
        clearContents()
        let holes = items.map { $0.rect.insetBy(dx: -Defaults.padding, dy: -Defaults.padding) }
        renderDim(holes: zip(items, holes).filter { !$0.0.rect.isEmpty }.map(\.1), enabled: style.dim)
        var placedLabels: [CGRect] = []
        for (index, (item, hole)) in zip(items, holes).enumerated() {
            if !item.rect.isEmpty {
                addStrokes(for: hole, color: style.color)
                addRipple(for: hole, color: style.color)
            }
            let otherHoles = holes.enumerated().filter { $0.offset != index }.map(\.element)
            if let labelFrame = addLabel(for: item, hole: hole, color: style.color, avoiding: otherHoles + placedLabels) {
                placedLabels.append(labelFrame)
            }
        }
    }

    private func clearContents() {
        layer?.sublayers?.filter { $0 !== dimLayer }.forEach { $0.removeFromSuperlayer() }
        subviews.forEach { $0.removeFromSuperview() }
        dimLayer.path = nil
    }

    private func renderDim(holes: [CGRect], enabled: Bool) {
        dimLayer.frame = bounds
        dimLayer.fillColor = NSColor.black.withAlphaComponent(enabled ? Defaults.dimAlpha : 0).cgColor
        let path = CGMutablePath()
        path.addRect(bounds)
        for hole in holes {
            path.addRoundedRect(in: hole, cornerWidth: Defaults.cornerRadius, cornerHeight: Defaults.cornerRadius)
        }
        dimLayer.path = path
    }

    private func addStrokes(for hole: CGRect, color: NSColor) {
        let halo = CAShapeLayer()
        halo.path = roundedPath(hole.insetBy(dx: -2, dy: -2), radius: Defaults.cornerRadius + 2)
        halo.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        halo.fillColor = NSColor.clear.cgColor
        halo.lineWidth = 1
        layer?.addSublayer(halo)

        let stroke = CAShapeLayer()
        stroke.path = roundedPath(hole, radius: Defaults.cornerRadius)
        stroke.strokeColor = color.cgColor
        stroke.fillColor = NSColor.clear.cgColor
        stroke.lineWidth = 3
        layer?.addSublayer(stroke)
    }

    private func addRipple(for hole: CGRect, color: NSColor) {
        let ripple = CAShapeLayer()
        ripple.path = roundedPath(hole, radius: Defaults.cornerRadius)
        ripple.strokeColor = color.cgColor
        ripple.fillColor = NSColor.clear.cgColor
        ripple.lineWidth = 2
        ripple.opacity = 0
        layer?.addSublayer(ripple)

        let spread = Self.rippleSpread
        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = ripple.path
        pathAnimation.toValue = roundedPath(hole.insetBy(dx: -spread, dy: -spread), radius: Defaults.cornerRadius + spread)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0

        let group = CAAnimationGroup()
        group.animations = [pathAnimation, fade]
        group.duration = Self.rippleDuration
        group.repeatCount = Self.rippleCount
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ripple.add(group, forKey: "ripple")
    }

    private func addLabel(for item: OverlayItem, hole: CGRect, color: NSColor, avoiding obstacles: [CGRect]) -> CGRect? {
        let label: NSView
        if let step = item.step {
            label = StepCardView(card: step, badgeColor: color)
        } else if item.label != nil || item.number != nil {
            label = LabelView(text: item.label, number: item.number, badgeColor: color)
        } else {
            return nil
        }
        label.frame = LabelLayout.frame(for: label.frame.size, target: hole, avoiding: obstacles, in: bounds)
        addSubview(label)
        return label.frame
    }

    private func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}

final class LabelView: NSView {
    private static let maxWidth: CGFloat = 420
    private static let horizontalPadding: CGFloat = 12
    private static let verticalPadding: CGFloat = 8
    private static let badgeSize: CGFloat = 22
    private static let badgeGap: CGFloat = 8

    init(text: String?, number: Int?, badgeColor: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: "#1C1C1E")!.withAlphaComponent(0.9).cgColor
        layer?.cornerRadius = 10

        var cursorX = Self.horizontalPadding
        var contentHeight: CGFloat = 0

        var badge: NSView?
        if let number {
            let view = makeBadge(number: number, color: badgeColor)
            badge = view
            cursorX += Self.badgeSize + Self.badgeGap
            contentHeight = Self.badgeSize
        }

        var field: NSTextField?
        if let text, !text.isEmpty {
            let textField = makeTextField(text: text, maxWidth: Self.maxWidth - cursorX - Self.horizontalPadding)
            field = textField
            contentHeight = max(contentHeight, textField.frame.height)
        }

        let width = cursorX + (field?.frame.width ?? -Self.badgeGap) + Self.horizontalPadding
        let height = contentHeight + Self.verticalPadding * 2
        frame = CGRect(x: 0, y: 0, width: width, height: height)

        if let badge {
            badge.frame.origin = CGPoint(x: Self.horizontalPadding, y: (height - Self.badgeSize) / 2)
            addSubview(badge)
        }
        if let field {
            field.frame.origin = CGPoint(x: cursorX, y: (height - field.frame.height) / 2)
            addSubview(field)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func makeBadge(number: Int, color: NSColor) -> NSView {
        let badge = NSView(frame: CGRect(x: 0, y: 0, width: Self.badgeSize, height: Self.badgeSize))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = color.cgColor
        badge.layer?.cornerRadius = Self.badgeSize / 2

        let digits = NSTextField(labelWithString: String(number))
        digits.font = .systemFont(ofSize: 12, weight: .bold)
        digits.textColor = .white
        digits.alignment = .center
        digits.sizeToFit()
        digits.frame = CGRect(
            x: 0,
            y: (Self.badgeSize - digits.frame.height) / 2,
            width: Self.badgeSize,
            height: digits.frame.height
        )
        badge.addSubview(digits)
        return badge
    }

    private func makeTextField(text: String, maxWidth: CGFloat) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 14, weight: .semibold)
        field.textColor = .white
        field.maximumNumberOfLines = 3
        field.lineBreakMode = .byTruncatingTail
        field.preferredMaxLayoutWidth = maxWidth
        field.frame.size = field.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        field.frame.size.width = min(field.frame.size.width, maxWidth)
        return field
    }
}
