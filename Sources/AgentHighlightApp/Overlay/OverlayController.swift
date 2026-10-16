import AppKit
import HighlightKit

final class OverlayController {
    var visibilityHandler: ((Bool) -> Void)?
    private var windows: [OverlayWindow] = []
    private var windowCache: [OverlayWindow] = []
    private var dismissTimer: Timer?

    var isVisible: Bool {
        !windows.isEmpty
    }

    func show(_ items: [OverlayItem], style: OverlayStyle, duration: TimeInterval) {
        clear()
        defer { visibilityHandler?(isVisible) }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for screen in NSScreen.screens {
            let window = takeCachedWindow(for: screen) ?? OverlayWindow(screen: screen)
            let placed = items.compactMap { place($0, on: screen, primaryHeight: primaryHeight) }
            window.overlayView.render(items: placed, style: style)
            window.orderFrontRegardless()
            windows.append(window)
        }
        windowCache.forEach { $0.close() }
        windowCache = []
        if duration > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.clear()
            }
        }
    }

    func clear() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard isVisible else { return }
        windows.forEach { $0.orderOut(nil) }
        windowCache = windows
        windows = []
        visibilityHandler?(false)
    }

    private func takeCachedWindow(for screen: NSScreen) -> OverlayWindow? {
        guard let index = windowCache.firstIndex(where: { $0.frame == screen.frame }) else { return nil }
        return windowCache.remove(at: index)
    }

    private func place(_ item: OverlayItem, on screen: NSScreen, primaryHeight: CGFloat) -> OverlayItem? {
        let appKitRect = Coordinates.appKitRect(topLeft: item.rect, primaryHeight: primaryHeight)
        guard appKitRect.intersects(screen.frame) else { return nil }
        var placed = item
        placed.rect = appKitRect.offsetBy(dx: -screen.frame.origin.x, dy: -screen.frame.origin.y)
        return placed
    }
}
