import AppKit

enum LabelLayout {
    static let gap: CGFloat = 8
    static let margin: CGFloat = 8

    static func frame(for labelSize: CGSize, target: CGRect, avoiding obstacles: [CGRect], in bounds: CGRect) -> CGRect {
        let candidates = candidateFrames(for: labelSize, target: target).map { clamp($0, in: bounds) }
        if let free = candidates.first(where: { candidate in !obstacles.contains { $0.intersects(candidate) } }) {
            return free
        }
        return candidates.min { overlapArea($0, obstacles) < overlapArea($1, obstacles) } ?? candidates[0]
    }

    private static func candidateFrames(for size: CGSize, target: CGRect) -> [CGRect] {
        let above = CGPoint(x: target.minX, y: target.maxY + gap)
        let below = CGPoint(x: target.minX, y: target.minY - gap - size.height)
        let right = CGPoint(x: target.maxX + gap, y: target.midY - size.height / 2)
        let left = CGPoint(x: target.minX - gap - size.width, y: target.midY - size.height / 2)
        let inside = CGPoint(x: target.minX + gap, y: target.maxY - gap - size.height)
        return [above, below, right, left, inside].map { CGRect(origin: $0, size: size) }
    }

    private static func clamp(_ frame: CGRect, in bounds: CGRect) -> CGRect {
        var clamped = frame
        clamped.origin.x = min(max(frame.minX, bounds.minX + margin), bounds.maxX - margin - frame.width)
        clamped.origin.y = min(max(frame.minY, bounds.minY + margin), bounds.maxY - margin - frame.height)
        return clamped
    }

    private static func overlapArea(_ frame: CGRect, _ obstacles: [CGRect]) -> CGFloat {
        obstacles.reduce(0) { total, obstacle in
            let overlap = frame.intersection(obstacle)
            return total + (overlap.isNull ? 0 : overlap.width * overlap.height)
        }
    }
}
