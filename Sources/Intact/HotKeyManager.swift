import AppKit
import Carbon.HIToolbox

/// Глобальный хоткей через Carbon: работает без доступа к «Универсальному доступу»
/// и отдаёт и нажатие, и отпускание — второе нужно для режима удержания.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let signature: OSType = 0x494E5443  // 'INTC'

    private init() {}

    func register(keyCode: Int, modifiers: Int) {
        unregister()
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                                         id, GetEventDispatcherTarget(), 0, &ref)
        if status != noErr { NSLog("Intact: не удалось зарегистрировать хоткей (\(status))") }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            guard let event else { return noErr }
            let kind = GetEventKind(event)
            DispatchQueue.main.async {
                if kind == UInt32(kEventHotKeyPressed) {
                    HotKeyManager.shared.onPress?()
                } else {
                    HotKeyManager.shared.onRelease?()
                }
            }
            return noErr
        }, 2, &types, nil, &handler)
    }

    // MARK: - Человекочитаемая запись комбинации

    static func describe(keyCode: Int, modifiers: Int) -> String {
        var s = ""
        if modifiers & Int(controlKey) != 0 { s += "⌃" }
        if modifiers & Int(optionKey)  != 0 { s += "⌥" }
        if modifiers & Int(shiftKey)   != 0 { s += "⇧" }
        if modifiers & Int(cmdKey)     != 0 { s += "⌘" }
        return s + keyName(keyCode)
    }

    static func keyName(_ code: Int) -> String {
        let named: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Escape: "Esc",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
            kVK_ANSI_Grave: "`", kVK_ANSI_Backslash: "\\", kVK_ANSI_Slash: "/",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: "."
        ]
        if let n = named[code] { return n }
        if let layout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let ok = data.withUnsafeBytes { raw -> Bool in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return false }
                return UCKeyTranslate(base, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                      UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                      &deadKeys, 4, &length, &chars) == noErr
            }
            if ok, length > 0 { return String(utf16CodeUnits: chars, count: length).uppercased() }
        }
        return "#\(code)"
    }

    /// Перевод модификаторов Cocoa в Carbon.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.control) { m |= Int(controlKey) }
        if flags.contains(.option)  { m |= Int(optionKey) }
        if flags.contains(.shift)   { m |= Int(shiftKey) }
        if flags.contains(.command) { m |= Int(cmdKey) }
        return m
    }
}
