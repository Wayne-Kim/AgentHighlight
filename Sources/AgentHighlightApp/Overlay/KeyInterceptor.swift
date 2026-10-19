import AppKit
import CoreGraphics

enum InterceptedKey {
    case escape
    case left
    case right

    init?(keyCode: Int64) {
        switch keyCode {
        case 53: self = .escape
        case 123: self = .left
        case 124: self = .right
        default: return nil
        }
    }
}

final class KeyInterceptor {
    private static let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    private let onKey: (InterceptedKey) -> Bool
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fallbackMonitor: Any?

    init(onKey: @escaping (InterceptedKey) -> Bool) {
        self.onKey = onKey
    }

    func setActive(_ active: Bool) {
        if active { enable() } else { disable() }
    }

    private func enable() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            return Unmanaged<KeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
        }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else {
            installFallbackMonitor()
            return
        }
        tap = created
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
    }

    private func disable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let fallbackMonitor {
            NSEvent.removeMonitor(fallbackMonitor)
            self.fallbackMonitor = nil
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown,
              event.flags.intersection(Self.modifierMask).isEmpty,
              let key = InterceptedKey(keyCode: event.getIntegerValueField(.keyboardEventKeycode)),
              onKey(key) else {
            return Unmanaged.passUnretained(event)
        }
        return nil
    }

    private func installFallbackMonitor() {
        guard fallbackMonitor == nil else { return }
        fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  let key = InterceptedKey(keyCode: Int64(event.keyCode)) else { return }
            _ = self?.onKey(key)
        }
    }
}
