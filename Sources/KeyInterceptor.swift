import AppKit
import ApplicationServices
import CoreGraphics

enum CutState: Equatable {
    case idle
    case pending(itemCount: Int)
}

final class KeyInterceptor {
    private static let finderBundleID = "com.apple.finder"
    private static let enabledKey = "finderCutEnabled"
    private static let keyCodeEsc: CGKeyCode = 53
    private static let syntheticEventTag: Int64 = 0x46435554 // "FCUT"
    private static let relevantModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    private let defaults: UserDefaults
    private let layoutResolver = KeyboardLayoutResolver()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var clipboardWatchTimer: Timer?
    private var cutCheckGeneration: Int = 0
    private var isTapActive = false

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled {
                clearCutState()
            }
        }
    }

    private(set) var cutState: CutState = .idle {
        didSet {
            switch cutState {
            case .pending:
                onCutStateChanged?(cutState)
            case .idle:
                if oldValue != .idle {
                    onCutStateChanged?(cutState)
                }
            }
        }
    }

    private var cutChangeCount: Int?

    var onCutStateChanged: ((CutState) -> Void)?
    var onTapStateChanged: ((Bool) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.enabledKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        }
    }

    @discardableResult
    func start() -> Bool {
        if let existingTap = eventTap {
            if AXIsProcessTrusted() {
                if !CGEvent.tapIsEnabled(tap: existingTap) {
                    CGEvent.tapEnable(tap: existingTap, enable: true)
                }
                if CGEvent.tapIsEnabled(tap: existingTap) {
                    isTapActive = true
                    return true
                }
            }
            stop()
        }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo = userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                return interceptor.handleEvent(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            isTapActive = false
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        self.isTapActive = true
        return true
    }

    func stop() {
        isTapActive = false
        clearCutState()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    @discardableResult
    func verifyHealth() -> Bool {
        guard AXIsProcessTrusted(), let tap = eventTap else {
            handleTapLost()
            return false
        }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        guard CGEvent.tapIsEnabled(tap: tap) else {
            handleTapLost()
            return false
        }
        return true
    }

    private func handleTapLost() {
        let wasActive = isTapActive || eventTap != nil
        stop()
        if wasActive {
            onTapStateChanged?(false)
        }
    }

    func clearCutState() {
        cutChangeCount = nil
        cutCheckGeneration += 1
        stopClipboardWatcher()
        cutState = .idle
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            let stillEnabled = eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
            if !stillEnabled || !AXIsProcessTrusted() {
                DispatchQueue.main.async { [weak self] in
                    self?.handleTapLost()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        // Pass through our own synthetic events untouched.
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag {
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown, isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        // Ignore key auto-repeat.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return Unmanaged.passUnretained(event)
        }

        guard FocusInspector.focusedApplicationBundleID() == Self.finderBundleID else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let mods = event.flags.intersection(Self.relevantModifiers)

        // Esc cancels pending cut state without blocking Finder's own Esc handling.
        if keyCode == Self.keyCodeEsc && mods.isEmpty {
            if case .pending = cutState {
                DispatchQueue.main.async { [weak self] in
                    self?.clearCutState()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard mods == .maskCommand else {
            return Unmanaged.passUnretained(event)
        }

        let keyMap = layoutResolver.currentMap

        if keyCode == keyMap.keyCodeC {
            if case .pending = cutState {
                DispatchQueue.main.async { [weak self] in
                    self?.clearCutState()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if keyCode == keyMap.keyCodeX {
            guard !FocusInspector.isFocusedElementTextInput() else {
                return Unmanaged.passUnretained(event)
            }

            // Swallow Cmd+X and post a clean synthetic Cmd+C so both Finder windows and Desktop copy reliably.
            let beforeCount = NSPasteboard.general.changeCount
            postSyntheticKey(keyCode: keyMap.keyCodeC, flags: .maskCommand)
            scheduleClipboardVerification(previousChangeCount: beforeCount)
            return nil
        }

        if keyCode == keyMap.keyCodeV {
            guard !FocusInspector.isFocusedElementTextInput() else {
                return Unmanaged.passUnretained(event)
            }

            if case .pending = cutState,
               let expectedCount = cutChangeCount,
               NSPasteboard.general.changeCount == expectedCount {
                // Swallow Cmd+V and post a clean synthetic Option+Cmd+V ("Move Item Here").
                postSyntheticKey(keyCode: keyMap.keyCodeV, flags: [.maskCommand, .maskAlternate])
                DispatchQueue.main.async { [weak self] in
                    self?.clearCutState()
                }
                return nil
            } else if case .pending = cutState {
                DispatchQueue.main.async { [weak self] in
                    self?.clearCutState()
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func postSyntheticKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            down.flags = flags
            down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
            down.post(tap: .cgAnnotatedSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private func scheduleClipboardVerification(previousChangeCount: Int) {
        cutCheckGeneration += 1
        let gen = cutCheckGeneration
        let delays: [TimeInterval] = [0.05, 0.12, 0.25, 0.45, 0.7]

        func attempt(index: Int) {
            guard index < delays.count else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + delays[index]) { [weak self] in
                guard let self = self, self.cutCheckGeneration == gen else { return }
                let pb = NSPasteboard.general
                if pb.changeCount != previousChangeCount {
                    let urls = pb.readObjects(
                        forClasses: [NSURL.self],
                        options: [.urlReadingFileURLsOnly: true]
                    ) as? [URL] ?? []

                    if !urls.isEmpty {
                        self.cutChangeCount = pb.changeCount
                        self.cutState = .pending(itemCount: urls.count)
                        self.startClipboardWatcher()
                    } else {
                        self.clearCutState()
                    }
                    return
                }
                attempt(index: index + 1)
            }
        }

        attempt(index: 0)
    }

    private func startClipboardWatcher() {
        stopClipboardWatcher()
        clipboardWatchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let expected = self.cutChangeCount else {
                self?.stopClipboardWatcher()
                return
            }
            if NSPasteboard.general.changeCount != expected {
                self.clearCutState()
            }
        }
    }

    private func stopClipboardWatcher() {
        clipboardWatchTimer?.invalidate()
        clipboardWatchTimer = nil
    }
}
