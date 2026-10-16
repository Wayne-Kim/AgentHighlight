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
            return .failure(ResolveError(message: "unsupported kind"))
        }
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

    private func activate(_ activations: [Activation]) {
        for activation in activations {
            _ = activation.window?.perform(kAXRaiseAction)
        }
        activations.last?.app.activate()
    }
}
