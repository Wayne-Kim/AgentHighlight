import AppKit
import HighlightKit

final class StepTour {
    private struct Step {
        let number: Int
        let target: Target
    }

    private struct Presentation {
        let generation: Int
        let step: Step
        let card: StepCard
        let style: OverlayStyle
        let activate: Bool
    }

    private let overlay: OverlayController
    private let resolver: TargetResolver
    private let queue = DispatchQueue(label: "AgentHighlight.StepTour")

    private var steps: [Step] = []
    private var total = 0
    private var position = 0
    private var generation = 0
    private var style = OverlayStyle.default
    private var activate = true
    private var currentApp: String?

    init(overlay: OverlayController, resolver: TargetResolver) {
        self.overlay = overlay
        self.resolver = resolver
    }

    var isActive: Bool {
        !steps.isEmpty
    }

    func start(_ request: HighlightRequest) -> HighlightResponse {
        let checked = resolver.resolve(probe(request))
        let found = Set(checked.resolved.map(\.index))
        let reachable = request.targets.enumerated()
            .filter { found.contains($0.offset) }
            .map { Step(number: $0.offset + 1, target: $0.element) }
        guard !reachable.isEmpty else { return checked }

        let presentation = onMain { () -> Presentation in
            steps = reachable
            total = request.targets.count
            position = 0
            style = OverlayStyle.from(request.style)
            activate = request.activate != false
            return nextPresentation()
        }
        var resolved = checked.resolved
        if let shown = present(presentation), let slot = resolved.firstIndex(where: { $0.index == shown.index }) {
            resolved[slot] = shown
        }
        return HighlightResponse(ok: checked.errors.isEmpty, resolved: resolved, errors: checked.errors)
    }

    func handleArrow(_ delta: Int) -> Bool {
        guard isActive, currentAppIsFrontmost() else { return false }
        move(by: delta)
        return true
    }

    func move(by delta: Int) {
        guard isActive else { return }
        let destination = position + delta
        if destination >= steps.count {
            stop()
            return
        }
        guard destination >= 0, destination != position else { return }
        position = destination
        let presentation = nextPresentation()
        queue.async { [weak self] in self?.present(presentation) }
    }

    func stop() {
        steps = []
        total = 0
        position = 0
        generation += 1
        currentApp = nil
        overlay.clear()
    }

    func abandon() {
        steps = []
        generation += 1
        currentApp = nil
    }

    var status: StepsStatus {
        guard isActive else { return StepsStatus(active: false) }
        let step = steps[position]
        return StepsStatus(active: true, current: step.number, total: total, label: step.target.label)
    }

    private func probe(_ request: HighlightRequest) -> HighlightRequest {
        var probe = request
        probe.activate = false
        probe.targets = request.targets.map { target in
            var silent = target
            silent.scroll = false
            return silent
        }
        return probe
    }

    private func nextPresentation() -> Presentation {
        generation += 1
        let step = steps[position]
        let next = steps.indices.contains(position + 1) ? steps[position + 1] : nil
        let card = StepCard(
            number: step.number,
            total: total,
            title: step.target.label,
            note: step.target.note,
            nextTitle: next.map { $0.target.label ?? $0.target.text ?? "" },
            hasPrevious: position > 0
        )
        return Presentation(generation: generation, step: step, card: card, style: style, activate: activate)
    }

    @discardableResult
    private func present(_ presentation: Presentation) -> ResolvedTarget? {
        let response = resolver.resolve(HighlightRequest(targets: [presentation.step.target], activate: presentation.activate))
        var resolved = response.resolved.first
        resolved?.index = presentation.step.number - 1
        let item = resolved.map { OverlayItem(rect: $0.rect.cgRect, step: presentation.card) }
            ?? missingItem(presentation.card, message: response.errors.first?.message)
        onMain {
            guard presentation.generation == generation else { return }
            currentApp = resolved?.app
            overlay.show([item], style: presentation.style, duration: 0)
        }
        return resolved
    }

    private func missingItem(_ card: StepCard, message: String?) -> OverlayItem {
        var card = card
        card.note = ["이 단계의 대상을 지금 화면에서 찾지 못했습니다.", message, card.note]
            .compactMap { $0 }
            .joined(separator: "\n")
        let primary = NSScreen.screens.first?.frame ?? .zero
        return OverlayItem(rect: CGRect(x: primary.midX, y: primary.height / 2, width: 0, height: 0), step: card)
    }

    private func currentAppIsFrontmost() -> Bool {
        guard let currentApp else { return true }
        return NSWorkspace.shared.frontmostApplication?.localizedName == currentApp
    }

    private func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }
}
