import Foundation
import HighlightKit

final class TargetResolver {
    func resolve(_ request: HighlightRequest) -> HighlightResponse {
        var resolved: [ResolvedTarget] = []
        var errors: [TargetError] = []
        for (index, target) in request.targets.enumerated() {
            switch target.kind {
            case .rect:
                guard let rect = target.rect else {
                    errors.append(TargetError(index: index, message: "rect target requires rect"))
                    continue
                }
                resolved.append(ResolvedTarget(index: index, label: target.label, rect: rect))
            default:
                errors.append(TargetError(index: index, message: "unsupported kind"))
            }
        }
        return HighlightResponse(ok: errors.isEmpty, resolved: resolved, errors: errors)
    }
}
