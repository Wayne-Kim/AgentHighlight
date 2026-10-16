import AppKit
import ApplicationServices
import HighlightKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController()
    private let resolver = TargetResolver()
    private var statusItem: NSStatusItem?
    private var server: HTTPServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        promptForAccessibilityIfNeeded()
        startServer()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "scope", accessibilityDescription: "AgentHighlight")

        let menu = NSMenu()
        menu.addItem(withTitle: "하이라이트 지우기", action: #selector(clearHighlights), keyEquivalent: "")
        menu.addItem(withTitle: "접근성 권한 열기...", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "포트 \(Defaults.port(from: ProcessInfo.processInfo.environment))", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
        statusItem = item
    }

    private func promptForAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func startServer() {
        let port = Defaults.port(from: ProcessInfo.processInfo.environment)
        let router = CommandRouter(overlay: overlay, resolver: resolver, port: port)
        do {
            let server = try HTTPServer(port: UInt16(port), handler: router.handle)
            server.start { error in
                fputs("AgentHighlight: port \(port) unavailable: \(error)\n", stderr)
                exit(2)
            }
            self.server = server
        } catch {
            fputs("AgentHighlight: cannot listen on port \(port): \(error)\n", stderr)
            exit(2)
        }
    }

    @objc private func clearHighlights() {
        overlay.clear()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
