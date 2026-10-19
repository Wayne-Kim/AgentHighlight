import ApplicationServices
import Foundation
import HighlightKit

struct OKResponse: Encodable {
    var ok = true
}

final class CommandRouter {
    private let overlay: OverlayController
    private let resolver: TargetResolver
    private let tour: StepTour
    private let port: Int

    init(overlay: OverlayController, resolver: TargetResolver, tour: StepTour, port: Int) {
        self.overlay = overlay
        self.resolver = resolver
        self.tour = tour
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
        case ("POST", "/steps"):
            return startSteps(request.body)
        case ("GET", "/steps"):
            return .json(onMain { tour.status })
        case ("POST", "/steps/next"):
            return .json(onMain { tour.move(by: 1); return tour.status })
        case ("POST", "/steps/prev"):
            return .json(onMain { tour.move(by: -1); return tour.status })
        case ("POST", "/clear"):
            onMain { tour.stop() }
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
            if target.kind == .figma, (target.url ?? "").isEmpty { return "targets[\(index)] requires url" }
        }
        return nil
    }

    private func find(_ body: Data) -> HTTPResponse {
        switch decodeRequest(body) {
        case .failure(let error):
            return .error("invalid HighlightRequest: \(error)", status: 400)
        case .success(var request):
            request.activate = false
            return .json(resolver.resolve(request, opensLinks: false))
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
            onMain {
                tour.abandon()
                overlay.show(items, style: style, duration: duration)
            }
        }
        return .json(response)
    }

    private func startSteps(_ body: Data) -> HTTPResponse {
        switch decodeRequest(body) {
        case .failure(let error):
            return .error("invalid HighlightRequest: \(error)", status: 400)
        case .success(let request):
            return .json(tour.start(request))
        }
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

    private func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }
}
