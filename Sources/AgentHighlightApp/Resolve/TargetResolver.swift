import AppKit
import ApplicationServices
import HighlightKit

final class TargetResolver {
    private struct Activation {
        let app: NSRunningApplication
        let window: AXElement?
    }

    func resolve(_ request: HighlightRequest) -> HighlightResponse {
        var resolved: [ResolvedTarget] = []
        var errors: [TargetError] = []
        var activations: [Activation] = []

        for (index, target) in request.targets.enumerated() {
            switch resolveTarget(target, index: index) {
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

    private func resolveTarget(_ target: Target, index: Int) -> Result<Outcome, ResolveError> {
        switch target.kind {
        case .rect:
            guard let rect = target.rect else { return .failure(ResolveError(message: "rect target requires rect")) }
            return .success(Outcome(target: ResolvedTarget(index: index, label: target.label, rect: rect), activation: nil))
        case .window:
            return resolveWindow(target, index: index)
        case .element:
            return resolveElement(target, index: index)
        }
    }

    private func resolveElement(_ target: Target, index: Int) -> Result<Outcome, ResolveError> {
        guard let text = target.text, !text.isEmpty else {
            return .failure(ResolveError(message: "element target requires text"))
        }
        guard let app = AppLocator.locate(target.app) else {
            return .failure(ResolveError(message: "app not found: \(target.app ?? "frontmost")"))
        }
        AXElement.application(pid: app.processIdentifier).enableWebAccessibility()

        let matcher = TextMatcher(query: text, mode: target.match ?? .contains)
        var matches = ElementFinder.find(app: app, windowTitle: target.title, matcher: matcher, role: target.role)
        if matches.isEmpty {
            usleep(300_000)
            matches = ElementFinder.find(app: app, windowTitle: target.title, matcher: matcher, role: target.role)
        }
        let position = target.index ?? 0
        guard position < matches.count else {
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

    private func needsScroll(_ rect: CGRect, within windowFrame: CGRect) -> Bool {
        rect.width <= 1 || rect.height <= 1 || !windowFrame.contains(rect)
    }

    private func scrollIntoView(_ element: AXElement, from original: CGRect) -> CGRect {
        guard element.perform("AXScrollToVisible") else { return original }
        for _ in 0..<6 {
            usleep(100_000)
            if let frame = element.frame, frame.height > 1, frame.width > 1, frame != original { return frame }
        }
        return element.frame ?? original
    }

    private func activate(_ activations: [Activation]) {
        for activation in activations {
            _ = activation.window?.perform(kAXRaiseAction)
        }
        activations.last?.app.activate()
    }
}
