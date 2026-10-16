import CoreGraphics
import Foundation

public struct Rect: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ cg: CGRect) {
        self.init(x: cg.origin.x, y: cg.origin.y, width: cg.width, height: cg.height)
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public enum TargetKind: String, Codable, Equatable {
    case rect
    case window
    case element
}

public enum MatchMode: String, Codable, Equatable {
    case contains
    case exact
    case regex
}

public struct Target: Codable, Equatable {
    public var kind: TargetKind
    public var rect: Rect?
    public var app: String?
    public var title: String?
    public var text: String?
    public var role: String?
    public var match: MatchMode?
    public var index: Int?
    public var label: String?
    public var scroll: Bool?

    public init(
        kind: TargetKind,
        rect: Rect? = nil,
        app: String? = nil,
        title: String? = nil,
        text: String? = nil,
        role: String? = nil,
        match: MatchMode? = nil,
        index: Int? = nil,
        label: String? = nil,
        scroll: Bool? = nil
    ) {
        self.kind = kind
        self.rect = rect
        self.app = app
        self.title = title
        self.text = text
        self.role = role
        self.match = match
        self.index = index
        self.label = label
        self.scroll = scroll
    }
}

public struct Style: Codable, Equatable {
    public var color: String?
    public var dim: Bool?

    public init(color: String? = nil, dim: Bool? = nil) {
        self.color = color
        self.dim = dim
    }
}

public struct HighlightRequest: Codable, Equatable {
    public var targets: [Target]
    public var label: String?
    public var duration: Double?
    public var activate: Bool?
    public var style: Style?

    public init(
        targets: [Target],
        label: String? = nil,
        duration: Double? = nil,
        activate: Bool? = nil,
        style: Style? = nil
    ) {
        self.targets = targets
        self.label = label
        self.duration = duration
        self.activate = activate
        self.style = style
    }
}

public struct ResolvedTarget: Codable, Equatable {
    public var index: Int
    public var label: String?
    public var rect: Rect
    public var app: String?
    public var windowTitle: String?
    public var matchedText: String?

    public init(
        index: Int,
        label: String? = nil,
        rect: Rect,
        app: String? = nil,
        windowTitle: String? = nil,
        matchedText: String? = nil
    ) {
        self.index = index
        self.label = label
        self.rect = rect
        self.app = app
        self.windowTitle = windowTitle
        self.matchedText = matchedText
    }
}

public struct TargetError: Codable, Equatable {
    public var index: Int
    public var message: String

    public init(index: Int, message: String) {
        self.index = index
        self.message = message
    }
}

public struct HighlightResponse: Codable, Equatable {
    public var ok: Bool
    public var resolved: [ResolvedTarget]
    public var errors: [TargetError]

    public init(ok: Bool, resolved: [ResolvedTarget], errors: [TargetError]) {
        self.ok = ok
        self.resolved = resolved
        self.errors = errors
    }
}

public struct HealthResponse: Codable, Equatable {
    public var ok: Bool
    public var version: String
    public var trusted: Bool
    public var port: Int
    public var pid: Int32

    public init(ok: Bool, version: String, trusted: Bool, port: Int, pid: Int32) {
        self.ok = ok
        self.version = version
        self.trusted = trusted
        self.port = port
        self.pid = pid
    }
}

public struct WindowInfo: Codable, Equatable {
    public var app: String
    public var bundleID: String?
    public var pid: Int32
    public var title: String
    public var rect: Rect
    public var onScreen: Bool

    public init(app: String, bundleID: String?, pid: Int32, title: String, rect: Rect, onScreen: Bool) {
        self.app = app
        self.bundleID = bundleID
        self.pid = pid
        self.title = title
        self.rect = rect
        self.onScreen = onScreen
    }
}

public struct WindowsResponse: Codable, Equatable {
    public var ok: Bool
    public var windows: [WindowInfo]

    public init(ok: Bool, windows: [WindowInfo]) {
        self.ok = ok
        self.windows = windows
    }
}

public struct ErrorResponse: Codable, Equatable {
    public var ok: Bool
    public var error: String

    public init(error: String) {
        self.ok = false
        self.error = error
    }
}
