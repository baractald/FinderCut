import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct ShortcutKeyMap: Equatable {
    static let ansiDefault = ShortcutKeyMap(keyCodeX: 7, keyCodeC: 8, keyCodeV: 9)

    let keyCodeX: CGKeyCode
    let keyCodeC: CGKeyCode
    let keyCodeV: CGKeyCode
}

final class KeyboardLayoutResolver {
    private let lock = NSLock()
    private var cachedMap: ShortcutKeyMap = .ansiDefault
    private var inputSourceObserver: NSObjectProtocol?

    var currentMap: ShortcutKeyMap {
        lock.lock()
        defer { lock.unlock() }
        return cachedMap
    }

    init() {
        if Thread.isMainThread {
            refresh()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
            }
        }

        let notificationName = NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let observer = inputSourceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    func refresh() {
        let resolved = Self.resolveCurrentLayout()
        lock.lock()
        cachedMap = resolved
        lock.unlock()
    }

    static func resolveCurrentLayout() -> ShortcutKeyMap {
        let candidates = [
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        ].compactMap { $0 }

        var keyCodeX: CGKeyCode?
        var keyCodeC: CGKeyCode?
        var keyCodeV: CGKeyCode?

        for source in candidates {
            let found = scanKeyCodes(from: source)
            if keyCodeX == nil { keyCodeX = found["x"] }
            if keyCodeC == nil { keyCodeC = found["c"] }
            if keyCodeV == nil { keyCodeV = found["v"] }
            if keyCodeX != nil && keyCodeC != nil && keyCodeV != nil {
                break
            }
        }

        return ShortcutKeyMap(
            keyCodeX: keyCodeX ?? ShortcutKeyMap.ansiDefault.keyCodeX,
            keyCodeC: keyCodeC ?? ShortcutKeyMap.ansiDefault.keyCodeC,
            keyCodeV: keyCodeV ?? ShortcutKeyMap.ansiDefault.keyCodeV
        )
    }

    private static func scanKeyCodes(from inputSource: TISInputSource) -> [String: CGKeyCode] {
        guard let rawData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return [:]
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())
        let cmdModifierState = UInt32(cmdKey >> 8)

        var mapping: [String: CGKeyCode] = [:]
        for virtualKey in UInt16(0)..<UInt16(128) {
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var actualLength = 0

            let status = layoutData.withUnsafeBytes { rawBuffer -> OSStatus in
                guard let layoutPtr = rawBuffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                    return OSStatus(paramErr)
                }
                return UCKeyTranslate(
                    layoutPtr,
                    virtualKey,
                    UInt16(kUCKeyActionDisplay),
                    cmdModifierState,
                    keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysMask),
                    &deadKeyState,
                    chars.count,
                    &actualLength,
                    &chars
                )
            }

            guard status == noErr, actualLength > 0 else { continue }
            let charString = String(utf16CodeUnits: chars, count: actualLength).lowercased()
            if (charString == "x" || charString == "c" || charString == "v"), mapping[charString] == nil {
                mapping[charString] = CGKeyCode(virtualKey)
            }
        }
        return mapping
    }
}
