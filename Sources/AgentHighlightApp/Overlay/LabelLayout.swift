import AppKit

enum LabelLayout {
    static let gap: CGFloat = 8
    static let margin: CGFloat = 8

    static func frame(for labelSize: CGSize, target: CGRect, in bounds: CGRect) -> CGRect {
        let x = min(max(target.minX, bounds.minX + margin), bounds.maxX - margin - labelSize.width)
        let above = target.maxY + gap
        let below = target.minY - gap - labelSize.height
        let inside = target.maxY - gap - labelSize.height

        let y: CGFloat
        if above + labelSize.height <= bounds.maxY - margin {
            y = above
        } else if below >= bounds.minY + margin {
            y = below
        } else {
            y = inside
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: labelSize)
    }
}
