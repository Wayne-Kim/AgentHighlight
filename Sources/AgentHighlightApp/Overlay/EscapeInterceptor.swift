import AppKit
import CoreGraphics

final class EscapeInterceptor {
    private static let escapeKeyCode: Int64 = 53

    private let onEscape: () -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fallbackMonitor: Any?

    init(onEscape: @escaping () -> Void) {
        self.onEscape = onEscape
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
            return Unmanaged<EscapeInterceptor>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
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
        guard type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKeyCode else {
            return Unmanaged.passUnretained(event)
        }
        DispatchQueue.main.async(execute: onEscape)
        return nil
    }

    private func installFallbackMonitor() {
        guard fallbackMonitor == nil else { return }
        fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(Self.escapeKeyCode) else { return }
            self?.onEscape()
        }
    }
}
