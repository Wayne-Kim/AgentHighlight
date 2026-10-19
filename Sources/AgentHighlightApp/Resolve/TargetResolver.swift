import AppKit
import ApplicationServices
import HighlightKit

final class TargetResolver {
    private static let requestTimeLimit: TimeInterval = 6
    private static let sparseTreeThreshold = 50
    private static let figmaBrowser = "Google Chrome"
    private static let figmaWindowTitle = #"Figma(\s*-|$)"#
    private static let figmaLoadTimeLimit: TimeInterval = 10

    private struct Activation {
        let app: NSRunningApplication
        let window: AXElement?
    }

    func resolve(_ request: HighlightRequest, opensLinks: Bool = true) -> HighlightResponse {
        var resolved: [ResolvedTarget] = []
        var errors: [TargetError] = []
        var activations: [Activation] = []
        let deadline = Date().addingTimeInterval(Self.requestTimeLimit)

        for (index, target) in request.targets.enumerated() {
            switch resolveTarget(target, index: index, deadline: deadline, opensLinks: opensLinks) {
            case .success(let outcome):
                resolved.append(outcome.target)
                if let activation = outcome.activation { activations.append(activation) }
            case .failure(let error):
                errors.append(TargetError(index: index, message: error.message))
            }
        }

        if request.activate != false { activate(activations) }
        return HighlightResponse(ok: errors.isEmpty, resolved: resolved, errors: errors)
    }

    private struct Outcome {
        let target: ResolvedTarget
        let activation: Activation?
    }

    private struct ResolveError: Error {
        let message: String
    }

    private func resolveTarget(_ target: Target, index: Int, deadline: Date, opensLinks: Bool) -> Result<Outcome, ResolveError> {
        switch target.kind {
        case .rect:
            guard let rect = target.rect else { return .failure(ResolveError(message: "rect target requires rect")) }
            return .success(Outcome(target: ResolvedTarget(index: index, label: target.label, rect: rect), activation: nil))
        case .window:
            return resolveWindow(target, index: index)
        case .element:
            return resolveElement(target, index: index, deadline: deadline)
        case .figma:
            return resolveFigma(target, index: index, opensLinks: opensLinks)
        }
    }

    private func resolveFigma(_ target: Target, index: Int, opensLinks: Bool) -> Result<Outcome, ResolveError> {
        guard let url = target.url.flatMap(URL.init(string:)), url.scheme != nil else {
            return .failure(ResolveError(message: "figma target requires url"))
        }
        let browser = target.app ?? Self.figmaBrowser
        var window = target
        window.kind = .window
        window.app = browser
        window.title = target.title ?? Self.figmaWindowTitle
        guard opensLinks else {
            let pending = ResolvedTarget(index: index, label: target.label, rect: Rect(.zero), app: browser, matchedText: url.absoluteString)
            return .success(Outcome(target: pending, activation: nil))
        }
        guard open(url, in: browser, besides: window) else {
            return .failure(ResolveError(message: "cannot open \(url.absoluteString) in \(browser)"))
        }
        let deadline = Date().addingTimeInterval(Self.figmaLoadTimeLimit)
        var result = resolveWindow(window, index: index)
        while case .failure = result, Date() < deadline {
            usleep(500_000)
            result = resolveWindow(window, index: index)
        }
        return result
    }

    private func open(_ url: URL, in app: String, besides window: Target) -> Bool {
        let arguments: [String]
        if case .success(let existing) = resolveWindow(window, index: 0), let activation = existing.activation {
            activate([activation])
            usleep(200_000)
            arguments = ["-a", app]
        } else {
            arguments = ["-na", app, "--args", "--new-window"]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments + [url.absoluteString]
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func resolveWindow(_ target: Target, index: Int) -> Result<Outcome, ResolveError> {
        guard let app = AppLocator.locate(target.app) else {
            return .failure(ResolveError(message: "app not found: \(target.app ?? "frontmost")"))
        }
        guard let window = WindowFinder.windows(of: app, titleRegex: target.title).first else {
            let filter = target.title.map { " matching title /\($0)/" } ?? ""
            return .failure(ResolveError(message: "no window\(filter) in \(app.localizedName ?? "app")"))
        }
        let resolved = ResolvedTarget(
            index: index,
            label: target.label,
            rect: Rect(window.rect),
            app: window.app,
            windowTitle: window.title
        )
        return .success(Outcome(target: resolved, activation: Activation(app: app, window: window.axWindow)))
    }

    private func resolveElement(_ target: Target, index: Int, deadline: Date) -> Result<Outcome, ResolveError> {
        guard let text = target.text, !text.isEmpty else {
            return .failure(ResolveError(message: "element target requires text"))
        }
        guard let app = AppLocator.locate(target.app) else {
            return .failure(ResolveError(message: "app not found: \(target.app ?? "frontmost")"))
        }
        AXElement.application(pid: app.processIdentifier).enableWebAccessibility()

        let matcher = TextMatcher(query: text, mode: target.match ?? .contains)
        var result = ElementFinder.find(app: app, windowTitle: target.title, matcher: matcher, role: target.role, deadline: deadline)
        if result.matches.isEmpty, result.visitedNodes < Self.sparseTreeThreshold, Date() < deadline {
            usleep(300_000)
            result = ElementFinder.find(app: app, windowTitle: target.title, matcher: matcher, role: target.role, deadline: deadline)
        }
        let matches = result.matches
        let position = target.index ?? 0
        guard position >= 0, position < matches.count else {
            let appName = app.localizedName ?? "app"
            return .failure(ResolveError(message: "no element matching \"\(text)\" in \(appName) (found \(matches.count))"))
        }

        let match = matches[position]
        var rect = match.rect
        if target.scroll != false, needsScroll(rect, within: match.windowFrame) {
            rect = scrollIntoView(match.element, from: rect)
        }
        if match.role == kAXStaticTextRole, matcher.mode != .exact,
           let range = matcher.range(in: match.text), let bounds = match.element.boundsForRange(range),
           match.windowFrame.intersects(bounds) {
            rect = bounds
        }

        let resolved = ResolvedTarget(
            index: index,
            label: target.label,
            rect: Rect(rect),
            app: app.localizedName,
            windowTitle: match.windowTitle,
            matchedText: String(match.text.prefix(120))
        )
        return .success(Outcome(target: resolved, activation: Activation(app: app, window: match.window)))
    }

    private func needsScroll(_ rect: CGRect, within windowFrame: CGRect) -> Bool {
        rect.width <= 1 || rect.height <= 1 || !windowFrame.contains(rect)
    }

    private func scrollIntoView(_ element: AXElement, from original: CGRect) -> CGRect {
        guard element.perform("AXScrollToVisible") else { return original }
        var previous: CGRect?
        for _ in 0..<8 {
            usleep(100_000)
            guard let frame = element.frame, frame.height > 1, frame.width > 1, frame != original else { continue }
            if frame == previous { return frame }
            previous = frame
        }
        return previous ?? element.frame ?? original
    }

    private func activate(_ activations: [Activation]) {
        guard !activations.isEmpty else { return }
        let work = {
            for activation in activations {
                _ = activation.window?.perform(kAXRaiseAction)
            }
            if let last = activations.last {
                let application = AXElement.application(pid: last.app.processIdentifier)
                AXUIElementSetAttributeValue(application.raw, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                last.app.activate()
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
    }
}
