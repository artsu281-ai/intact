import AppKit
import Carbon.HIToolbox

/// Доставка распознанного текста в активное приложение.
enum TextInserter {

    static var hasAccessibility: Bool { Permissions.accessibility }

    static func requestAccessibility() { Permissions.requestAccessibility() }

    static func deliver(_ text: String, mode: OutputMode) {
        guard !text.isEmpty else { return }
        switch mode {
        case .clipboard:
            copy(text)
        case .paste:
            paste(text)
        case .type:
            typeOut(text)
        case .live:
            // Текст уже напечатан вживую во время речи — здесь делать нечего.
            break
        }
    }

    private static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Кладём текст в буфер, жмём ⌘V и через секунду возвращаем прежнее содержимое.
    private static func paste(_ text: String) {
        guard Permissions.accessibility else {
            Log.write("текст в буфере, но ⌘V отправить нельзя: нет «Универсального доступа»")
            return
        }
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)

        copy(text)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
            let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
            let up   = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)

            if let previous {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    // Не затираем буфер, если пользователь успел скопировать что-то своё.
                    if pb.string(forType: .string) == text {
                        pb.clearContents()
                        pb.setString(previous, forType: .string)
                    }
                }
            }
        }
    }

    /// Посимвольный ввод — для полей, где ⌘V не работает.
    private static func typeOut(_ text: String) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        for ch in text {
            var units = Array(String(ch).utf16)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            down?.flags = []
            down?.post(tap: .cgAnnotatedSessionEventTap)

            var unitsUp = Array(String(ch).utf16)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: unitsUp.count, unicodeString: &unitsUp)
            up?.flags = []
            up?.post(tap: .cgAnnotatedSessionEventTap)
            usleep(1400)
        }
    }
}
