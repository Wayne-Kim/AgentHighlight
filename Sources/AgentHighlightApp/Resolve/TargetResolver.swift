import Foundation
import HighlightKit

final class TargetResolver {
    func resolve(_ request: HighlightRequest) -> HighlightResponse {
        let errors = request.targets.indices.map { TargetError(index: $0, message: "unsupported kind") }
        return HighlightResponse(ok: false, resolved: [], errors: errors)
    }
}
