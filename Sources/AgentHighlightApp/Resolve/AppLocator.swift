import AppKit

enum AppLocator {
    static func locate(_ query: String?) -> NSRunningApplication? {
        let candidates = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != getpid() && $0.activationPolicy != .prohibited
        }
        guard let query = query?.trimmingCharacters(in: .whitespaces), !query.isEmpty else {
            let frontmost = NSWorkspace.shared.frontmostApplication
            return frontmost?.processIdentifier == getpid() ? nil : frontmost
        }
        let needle = query.lowercased()
        if let match = candidates.first(where: { $0.bundleIdentifier?.lowercased() == needle }) { return match }
        if let match = candidates.first(where: { $0.localizedName?.lowercased() == needle }) { return match }
        return candidates.first {
            ($0.localizedName?.lowercased().contains(needle) ?? false)
                || ($0.bundleIdentifier?.lowercased().contains(needle) ?? false)
        }
    }
}
