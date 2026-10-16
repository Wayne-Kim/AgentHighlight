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
        if Thread.isMainThread { return route(request) }
        return DispatchQueue.main.sync { route(request) }
    }

    private func route(_ request: HTTPRequest) -> HTTPResponse {
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
        case ("POST", "/clear"):
            overlay.clear()
            return .json(OKResponse())
        default:
            return .error("not found: \(request.method) \(request.path)", status: 404)
        }
    }

    private func highlight(_ body: Data) -> HTTPResponse {
        let request: HighlightRequest
        do {
            request = try JSONDecoder().decode(HighlightRequest.self, from: body)
        } catch {
            return .error("invalid HighlightRequest: \(error)", status: 400)
        }
        let response = resolver.resolve(request)
        if !response.resolved.isEmpty {
            overlay.show(
                overlayItems(for: request, response: response),
                style: OverlayStyle.from(request.style),
                duration: request.duration ?? Defaults.duration
            )
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
}
