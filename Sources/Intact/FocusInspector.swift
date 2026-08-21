import AppKit
import ApplicationServices

/// Проверка активного контекста перед вставкой.
///
/// Цель: не отправлять случайные ⌘V и нажатия клавиш в пустой рабочий стол
/// Finder или системные панели, но при этом надёжно работать во всех приложениях
/// (включая Electron, веб-страницы, IDE JetBrains, терминалы и др.).
enum FocusInspector {

    private static let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField",
        "AXWebArea"
    ]

    /// Системные бандлы рабочего стола/панелей, где нажатия вслепую нежелательны
    private static let systemExcludedBundles: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui"
    ]

    /// Проверяет, сообщает ли Accessibility API о наличии редактируемого элемента.
    static var hasEditableFocus: Bool {
        guard Permissions.accessibility else { return false }

        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let raw = focused else { return false }
        let element = raw as! AXUIElement

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if let role = roleRef as? String, editableRoles.contains(role) { return true }

        // Признак каретки или выделения (работает в ряде редакторов)
        var caret: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &caret) == .success {
            return true
        }

        var selText: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selText) == .success {
            return true
        }

        // Проверка на возможность изменения значения
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue { return true }

        return false
    }

    /// Определяет, можно ли доставлять текст (через ⌘V или печать) в текущее активное приложение.
    ///
    /// В отличие от чистой проверки AX-ролей, этот метод не блокирует вставку в приложениях,
    /// не реализующих нативные AX-атрибуты (VS Code, JetBrains, Chrome contenteditable, Terminal и др.).
    static var canInsertText: Bool {
        guard Permissions.accessibility else { return false }

        // Если Accessibility подтверждает текстовое поле — точно можно вставлять.
        if hasEditableFocus { return true }

        // Проверяем текущее активное приложение
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let bundleId = frontApp.bundleIdentifier ?? ""

        // Игнорируем наше собственное приложение и системные панели
        if bundleId == Bundle.main.bundleIdentifier || systemExcludedBundles.contains(bundleId) {
            return false
        }

        // Особый случай для Finder: на пустом рабочем столе вставлять некуда
        if bundleId == "com.apple.finder" {
            let system = AXUIElementCreateSystemWide()
            var focused: CFTypeRef?
            if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
               let raw = focused {
                let element = raw as! AXUIElement
                var roleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
                let role = roleRef as? String ?? ""
                // Если в Finder фокус в текстовом поле (например, переименование файла) — разрешаем.
                if editableRoles.contains(role) { return true }
                // Если на рабочем столе или в списке без поля ввода — не вставляем.
                if role == "AXScrollArea" || role == "AXDesktopGroup" || role == "AXApplication" || role.isEmpty {
                    return false
                }
            }
        }

        // Для любого обычного активного приложения (браузер, редактор кода, мессенджер и т.д.)
        // разрешаем доставку текста.
        return true
    }
}
