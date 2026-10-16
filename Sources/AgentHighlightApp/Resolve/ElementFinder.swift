import AppKit
import ApplicationServices

struct ElementMatch {
    let element: AXElement
    let rect: CGRect
    let text: String
    let role: String
    let score: Int
    let window: AXElement
    let windowTitle: String
    let windowFrame: CGRect
}

enum ElementFinder {
    static let nodeLimit = 50_000
    static let timeLimit: TimeInterval = 4

    private static let batchAttributes = [
        kAXRoleAttribute, kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXChildrenAttribute,
    ] as CFArray

    static func find(
        app: NSRunningApplication,
        windowTitle: String?,
        matcher: TextMatcher,
        role: String?,
        limit: Int = 20
    ) -> [ElementMatch] {
        let deadline = Date().addingTimeInterval(timeLimit)
        var visited = 0
        var matches: [ElementMatch] = []

        for window in WindowFinder.windows(of: app, titleRegex: windowTitle) {
            guard let axWindow = window.axWindow else { continue }
            var stack: [AXElement] = [axWindow]
            while let element = stack.popLast() {
                visited += 1
                if visited > nodeLimit || Date() > deadline { break }
                let snapshot = read(element)
                stack.append(contentsOf: snapshot.children.reversed())

                guard role == nil || snapshot.role == role,
                      let text = snapshot.text,
                      let score = matcher.score(text),
                      let frame = element.frame, frame.width > 0, frame.height > 0
                else { continue }
                matches.append(ElementMatch(
                    element: element,
                    rect: frame,
                    text: text,
                    role: snapshot.role,
                    score: score,
                    window: axWindow,
                    windowTitle: window.title,
                    windowFrame: window.rect
                ))
            }
        }

        matches.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.text.count < rhs.text.count
        }
        return Array(matches.prefix(limit))
    }

    private struct Snapshot {
        let role: String
        let text: String?
        let children: [AXElement]
    }

    private static func read(_ element: AXElement) -> Snapshot {
        var values: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(element.raw, batchAttributes, [], &values)
        guard status == .success, let array = values as? [AnyObject], array.count == 5 else {
            return Snapshot(role: element.role ?? "", text: nil, children: element.children)
        }
        let role = array[0] as? String ?? ""
        let text = [array[1], array[2], array[3]]
            .compactMap { $0 as? String }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let children = (array[4] as? [AXUIElement] ?? []).map(AXElement.init)
        return Snapshot(role: role, text: text, children: children)
    }
}
