import AppKit
import ApplicationServices
import HighlightKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController()
    private let resolver = TargetResolver()
    private lazy var tour = StepTour(overlay: overlay, resolver: resolver)
    private var statusItem: NSStatusItem?
    private var server: HTTPServer?
    private var keyInterceptor: KeyInterceptor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let port = Defaults.port(from: ProcessInfo.processInfo.environment)
        exitIfAnotherInstanceAnswers(port: port)
        installStatusItem(port: port)
        promptForAccessibilityIfNeeded()
        installKeyInterceptor()
        startServer(port: port)
    }

    private func exitIfAnotherInstanceAnswers(port: Int) {
        let request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!, timeoutInterval: 0.7)
        let semaphore = DispatchSemaphore(value: 0)
        var answered = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            answered = (response as? HTTPURLResponse)?.statusCode == 200
            semaphore.signal()
        }.resume()
        semaphore.wait()
        guard answered else { return }
        fputs("AgentHighlight: another instance already answers on port \(port)\n", stderr)
        exit(2)
    }

    private func installStatusItem(port: Int) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "scope", accessibilityDescription: "AgentHighlight")

        let menu = NSMenu()
        menu.addItem(withTitle: "하이라이트 지우기", action: #selector(clearHighlights), keyEquivalent: "")
        menu.addItem(withTitle: "접근성 권한 열기...", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "포트 \(port)", action: nil, keyEquivalent: "")
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

    private func installKeyInterceptor() {
        let interceptor = KeyInterceptor { [weak self] key in self?.handle(key) ?? false }
        overlay.visibilityHandler = { visible in interceptor.setActive(visible) }
        keyInterceptor = interceptor
    }

    private func handle(_ key: InterceptedKey) -> Bool {
        switch key {
        case .escape:
            tour.stop()
            return true
        case .left:
            return tour.handleArrow(-1)
        case .right:
            return tour.handleArrow(1)
        }
    }

    private func startServer(port: Int) {
        let router = CommandRouter(overlay: overlay, resolver: resolver, tour: tour, port: port)
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
        tour.stop()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
