import AppKit
import ApplicationServices
import HighlightKit

struct WindowRecord {
    let pid: Int32
    let app: String
    let bundleID: String?
    let title: String
    let rect: CGRect
    let onScreen: Bool
    let axWindow: AXElement?

    var info: WindowInfo {
        WindowInfo(app: app, bundleID: bundleID, pid: pid, title: title, rect: Rect(rect), onScreen: onScreen)
    }
}

enum WindowFinder {
    private static let messagingTimeout: Float = 1.5

    static func windows(of app: NSRunningApplication, titleRegex: String?) -> [WindowRecord] {
        let application = AXElement.application(pid: app.processIdentifier)
        application.setMessagingTimeout(messagingTimeout)
        let focused = application.focusedWindow
        var ordered = application.windows
        if let focused, let index = ordered.firstIndex(where: { CFEqual($0.raw, focused.raw) }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        let regex = titleRegex.flatMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
        return ordered.compactMap { window in
            guard !window.isMinimized, let frame = window.frame, frame.width > 0, frame.height > 0 else { return nil }
            let title = window.title ?? ""
            if let regex, !matches(regex, title) { return nil }
            return WindowRecord(
                pid: app.processIdentifier,
                app: app.localizedName ?? "",
                bundleID: app.bundleIdentifier,
                title: title,
                rect: frame,
                onScreen: true,
                axWindow: window
            )
        }
    }

    static func all() -> [WindowRecord] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        var axTitlesByPid: [Int32: [(CGRect, String)]] = [:]
        return list.compactMap { entry in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32, pid != getpid(),
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict), bounds.width > 1, bounds.height > 1
            else { return nil }
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            let running = NSRunningApplication(processIdentifier: pid)
            var title = entry[kCGWindowName as String] as? String ?? ""
            if title.isEmpty {
                if axTitlesByPid[pid] == nil { axTitlesByPid[pid] = axTitles(pid: pid) }
                title = axTitlesByPid[pid]?.first { abs($0.0.origin.x - bounds.origin.x) < 2 && abs($0.0.origin.y - bounds.origin.y) < 2 }?.1 ?? ""
            }
            return WindowRecord(
                pid: pid,
                app: running?.localizedName ?? owner,
                bundleID: running?.bundleIdentifier,
                title: title,
                rect: bounds,
                onScreen: true,
                axWindow: nil
            )
        }
    }

    private static func axTitles(pid: Int32) -> [(CGRect, String)] {
        let application = AXElement.application(pid: pid)
        application.setMessagingTimeout(messagingTimeout)
        return application.windows.compactMap { window in
            guard let frame = window.frame else { return nil }
            return (frame, window.title ?? "")
        }
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
