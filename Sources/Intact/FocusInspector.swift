import AppKit
import ApplicationServices

/// Интеллектуальная проверка доступности текстового поля перед вставкой:
///
/// 1. В браузерах (Chrome, Safari, Arc, Brave, Edge, Firefox и др.):
///    - Если курсор стоит в строке поиска, форме ввода или на странице в поле — текст вставляется напрямую.
///    - Если пользователь просто смотрит на страницу и поле не выбрано — показывается карточка «Скопировать».
/// 2. В Finder (на рабочем столе или в папках без режима переименования) — показывается карточка «Скопировать».
/// 3. В редакторах и приложениях (Antigravity IDE, VS Code, Telegram, Slack, Notes, Terminal и др.) — текст вставляется напрямую.
enum FocusInspector {

    private static let browserBundles: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.apple.Safari",
        "company.thebrowser.Arc",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi"
    ]

    private static let systemExcludedBundles: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine"
    ]

    /// Определяет, есть ли в данный момент возможность доставить текст в активное приложение.
    static var canInsertText: Bool {
        guard Permissions.accessibility else { return false }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let bundleId = frontApp.bundleIdentifier ?? ""

        // 1. Игнорируем собственное приложение и системные панели
        if bundleId.isEmpty || bundleId == Bundle.main.bundleIdentifier || systemExcludedBundles.contains(bundleId) {
            return false
        }

        let app = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        // 2. Особый случай для Finder: на пустом рабочем столе или в списке файлов без переименования вставки нет
        if bundleId == "com.apple.finder" {
            if err == .success, let elem = focusedRef as! AXUIElement? {
                var roleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
                let role = roleRef as? String ?? ""
                if role == (kAXTextFieldRole as String) || role == "AXSearchField" {
                    return true
                }
            }
            return false
        }

        // 3. Web-браузеры (Chrome, Safari, Arc, Brave, Edge, Firefox и др.)
        if browserBundles.contains(bundleId) {
            if err == .success, let elem = focusedRef as! AXUIElement? {
                var roleRef: CFTypeRef?
                var isValSettable: DarwinBoolean = false
                var isSelSettable: DarwinBoolean = false
                var isInsertionPoint: CFTypeRef?

                AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
                AXUIElementCopyAttributeValue(elem, kAXInsertionPointLineNumberAttribute as CFString, &isInsertionPoint)
                AXUIElementIsAttributeSettable(elem, kAXValueAttribute as CFString, &isValSettable)
                AXUIElementIsAttributeSettable(elem, kAXSelectedTextAttribute as CFString, &isSelSettable)

                let role = roleRef as? String ?? ""

                // Проверяем, является ли элемент редактируемым полем ввода
                if role == (kAXTextFieldRole as String) ||
                   role == (kAXTextAreaRole as String) ||
                   role == "AXSearchField" ||
                   role == (kAXComboBoxRole as String) ||
                   isValSettable.boolValue ||
                   isSelSettable.boolValue ||
                   isInsertionPoint != nil {
                    return true
                }
                // Фокус на ссылке, кнопке, картинке или теле страницы — не поле ввода
                return false
            } else {
                // В браузере нет сфокусированного элемента ввода
                return false
            }
        }

        // 4. Для остальных приложений (Antigravity IDE, VS Code, Telegram, Slack, Notes, Word, Terminal и др.)
        if err == .success, let elem = focusedRef as! AXUIElement? {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""

            // Если фокус на чистой кнопке или статическом изображении без текстового ввода
            if role == (kAXButtonRole as String) || role == (kAXImageRole as String) {
                return false
            }
        }

        return true
    }
}
