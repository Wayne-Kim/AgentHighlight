import AppKit
import HighlightKit

final class OverlayController {
    private var windows: [OverlayWindow] = []
    private var dismissTimer: Timer?

    func show(_ items: [OverlayItem], style: OverlayStyle, duration: TimeInterval) {
        clear()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let placed = items.compactMap { place($0, on: screen, primaryHeight: primaryHeight) }
            window.overlayView.render(items: placed, style: style)
            window.orderFrontRegardless()
            windows.append(window)
        }
        if duration > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.clear()
            }
        }
    }

    func clear() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    private func place(_ item: OverlayItem, on screen: NSScreen, primaryHeight: CGFloat) -> OverlayItem? {
        let appKitRect = Coordinates.appKitRect(topLeft: item.rect, primaryHeight: primaryHeight)
        guard appKitRect.intersects(screen.frame) else { return nil }
        var placed = item
        placed.rect = appKitRect.offsetBy(dx: -screen.frame.origin.x, dy: -screen.frame.origin.y)
        return placed
    }
}
