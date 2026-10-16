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
        case ("POST", "/clear"):
            overlay.clear()
            return .json(OKResponse())
        default:
            return .error("not found: \(request.method) \(request.path)", status: 404)
        }
    }
}
