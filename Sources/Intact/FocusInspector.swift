import AppKit
import ApplicationServices

/// Точная проверка активного контекста перед вставкой:
///
/// 1. Если пользователь нажал на поле ввода (в браузере Chrome/Safari, редакторе Antigravity/VS Code,
///    мессенджере, почте, заметках или терминале) — текст сразу вставляется на место курсора.
/// 2. Если поле ввода не выбрано (клик на фоне сайта в Chrome, пустой рабочий стол Finder,
///    просмотр страницы без активного инпута) — приложение показывает всплывающую карточку
///    с кнопкой «Скопировать», которая автоматически исчезает через 5 секунд.
enum FocusInspector {

    private static let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField"
    ]

    private static let systemExcludedBundles: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight"
    ]

    /// Определяет, есть ли в данный момент выбранное поле для автоматической вставки.
    static var canInsertText: Bool {
        guard Permissions.accessibility else { return false }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let bundleId = frontApp.bundleIdentifier ?? ""

        if bundleId.isEmpty || bundleId == Bundle.main.bundleIdentifier || systemExcludedBundles.contains(bundleId) {
            return false
        }

        // В терминалах ввод всегда активен в текущей сессии
        let isTerminal = bundleId == "com.apple.Terminal" || bundleId == "com.googlecode.iterm2" ||
                         bundleId.contains("alacritty") || bundleId.contains("ghostty")
        if isTerminal { return true }

        // Проверяем наличие активного элемента ввода в текущем приложении
        return hasEditableFocus(appPID: frontApp.processIdentifier)
    }

    private static func hasEditableFocus(appPID: pid_t) -> Bool {
        var focusedElement: AXUIElement?

        // 1. Запрашиваем фокус непосредственно у активного приложения
        let app = AXUIElementCreateApplication(appPID)
        var appFocused: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &appFocused) == .success,
           let raw = appFocused {
            focusedElement = (raw as! AXUIElement)
        } else {
            // Резервный запрос через системный фокус
            let system = AXUIElementCreateSystemWide()
            var sysFocused: CFTypeRef?
            if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &sysFocused) == .success,
               let raw = sysFocused {
                focusedElement = (raw as! AXUIElement)
            }
        }

        guard let element = focusedElement else {
            return false
        }

        // Проверяем роль элемента
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        // Стандартные текстовые поля (включая веб-поля ввода и редакторы)
        if editableRoles.contains(role) {
            return true
        }

        // Наличие каретки или выделения текста
        var caretRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &caretRef) == .success,
           caretRef != nil {
            if role != "AXButton" && role != "AXImage" && role != "AXLink" {
                return true
            }
        }

        // Позиция каретки в строке (Monaco/VS Code/Electron)
        var lineRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXInsertionPointLineNumber" as CFString, &lineRef) == .success {
            return true
        }

        // Изменяемое значение
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }

        return false
    }
}
