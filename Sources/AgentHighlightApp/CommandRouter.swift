import ApplicationServices
import Foundation
import HighlightKit

struct OKResponse: Encodable {
    var ok = true
}

final class CommandRouter {
    private let overlay: OverlayController
    private let resolver: TargetResolver
    private let port: Int

    init(overlay: OverlayController, resolver: TargetResolver, port: Int) {
        self.overlay = overlay
        self.resolver = resolver
        self.port = port
    }

    func handle(_ request: HTTPRequest) -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            return .json(HealthResponse(
                ok: true,
                version: Defaults.version,
                trusted: AXIsProcessTrusted(),
                port: port,
                pid: getpid()
            ))
        case ("POST", "/highlight"):
            return highlight(request.body)
        case ("POST", "/find"):
            return find(request.body)
        case ("GET", "/windows"):
            return windows(app: request.query["app"], title: request.query["title"])
        case ("POST", "/clear"):
            onMain { overlay.clear() }
            return .json(OKResponse())
        default:
            return .error("not found: \(request.method) \(request.path)", status: 404)
        }
    }

    private func decodeRequest(_ body: Data) -> Result<HighlightRequest, Error> {
        Result {
            let request = try JSONDecoder().decode(HighlightRequest.self, from: body)
            if let problem = validationProblem(request) { throw ValidationError(message: problem) }
            return request
        }
    }

    private struct ValidationError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    private func validationProblem(_ request: HighlightRequest) -> String? {
        if request.targets.isEmpty { return "targets must not be empty" }
        if let duration = request.duration, duration < 0 { return "duration must be >= 0" }
        for (index, target) in request.targets.enumerated() {
            if let position = target.index, position < 0 { return "targets[\(index)].index must be >= 0" }
            if target.kind == .rect, target.rect == nil { return "targets[\(index)] requires rect" }
            if target.kind == .element, (target.text ?? "").isEmpty { return "targets[\(index)] requires text" }
        }
        return nil
    }

    private func find(_ body: Data) -> HTTPResponse {
        switch decodeRequest(body) {
        case .failure(let error):
            return .error("invalid HighlightRequest: \(error)", status: 400)
        case .success(var request):
            request.activate = false
            return .json(resolver.resolve(request))
        }
    }

    private func windows(app: String?, title: String?) -> HTTPResponse {
        let records: [WindowRecord]
        if let app, !app.isEmpty {
            guard let running = AppLocator.locate(app) else { return .error("app not found: \(app)", status: 404) }
            records = WindowFinder.windows(of: running, titleRegex: title)
        } else {
            records = WindowFinder.all()
        }
        return .json(WindowsResponse(ok: true, windows: records.map(\.info)))
    }

    private func highlight(_ body: Data) -> HTTPResponse {
        let request: HighlightRequest
        switch decodeRequest(body) {
        case .failure(let error):
            return .error("invalid HighlightRequest: \(error)", status: 400)
        case .success(let decoded):
            request = decoded
        }
        let response = resolver.resolve(request)
        if !response.resolved.isEmpty {
            let items = overlayItems(for: request, response: response)
            let style = OverlayStyle.from(request.style)
            let duration = request.duration ?? Defaults.duration
            onMain { overlay.show(items, style: style, duration: duration) }
        }
        return .json(response)
    }

    private func overlayItems(for request: HighlightRequest, response: HighlightResponse) -> [OverlayItem] {
        let numbered = request.targets.count > 1
        var fallbackLabel = request.label
        return response.resolved.map { target in
            var label = target.label
            if label == nil, let fallback = fallbackLabel {
                label = fallback
                fallbackLabel = nil
            }
            return OverlayItem(rect: target.rect.cgRect, label: label, number: numbered ? target.index + 1 : nil)
        }
    }

    private func onMain(_ work: () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
}
