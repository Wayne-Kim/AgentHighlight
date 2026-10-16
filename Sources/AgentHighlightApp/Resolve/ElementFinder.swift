import AppKit
import ApplicationServices

struct ElementMatch {
    let element: AXElement
    let rect: CGRect
    let text: String
    let role: String
    let score: Int
    let insideWebArea: Bool
    let window: AXElement
    let windowTitle: String
    let windowFrame: CGRect
}

struct ElementSearchResult {
    let matches: [ElementMatch]
    let visitedNodes: Int
}

enum ElementFinder {
    static let nodeLimit = 50_000
    static let timeLimit: TimeInterval = 4

    private static let batchAttributes = [
        kAXRoleAttribute, kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXChildrenAttribute,
    ] as CFArray

    private static let containerRoles: Set<String> = [kAXWindowRole, "AXWebArea", kAXSheetRole, kAXDrawerRole]

    private struct Frame {
        let element: AXElement
        let insideWebArea: Bool
    }

    static func find(
        app: NSRunningApplication,
        windowTitle: String?,
        matcher: TextMatcher,
        role: String?,
        deadline: Date? = nil,
        limit: Int = 20
    ) -> ElementSearchResult {
        let ownDeadline = Date().addingTimeInterval(timeLimit)
        let effectiveDeadline = deadline.map { min($0, ownDeadline) } ?? ownDeadline
        var visited = 0
        var matches: [ElementMatch] = []

        for window in WindowFinder.windows(of: app, titleRegex: windowTitle) {
            guard let axWindow = window.axWindow else { continue }
            var stack = [Frame(element: axWindow, insideWebArea: false)]
            while let frame = stack.popLast() {
                visited += 1
                if visited > nodeLimit || Date() > effectiveDeadline { break }
                let snapshot = read(frame.element)
                let childrenInsideWebArea = frame.insideWebArea || snapshot.role == "AXWebArea"
                stack.append(contentsOf: snapshot.children.reversed().map { Frame(element: $0, insideWebArea: childrenInsideWebArea) })

                guard !containerRoles.contains(snapshot.role),
                      role == nil || snapshot.role == role,
                      let text = snapshot.text,
                      let score = matcher.score(text),
                      let elementFrame = frame.element.frame, elementFrame.width > 0, elementFrame.height > 0
                else { continue }
                matches.append(ElementMatch(
                    element: frame.element,
                    rect: elementFrame,
                    text: text,
                    role: snapshot.role,
                    score: score,
                    insideWebArea: frame.insideWebArea,
                    window: axWindow,
                    windowTitle: window.title,
                    windowFrame: window.rect
                ))
            }
        }

        matches.sort { lhs, rhs in
            if lhs.insideWebArea != rhs.insideWebArea { return lhs.insideWebArea }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.text.count < rhs.text.count
        }
        return ElementSearchResult(matches: Array(matches.prefix(limit)), visitedNodes: visited)
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
