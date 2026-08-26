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
        "com.apple.ScreenSaver.Engine",
        // Приложения-посредники, через которые мы сами и спрашиваем модель.
        // Если ответ придёт в момент, когда фронтом оказалось окно Gemini,
        // «вставить» означало бы вписать ответ в его же поле ввода — а
        // пользователь при этом не увидит вообще ничего.
        "com.google.GeminiMacOS"
    ]

    /// Короткое описание того, что видит проверка прямо сейчас — для лога.
    /// Без него разбор «почему текст ушёл в никуда» требует отдельного скрипта.
    static var focusDescription: String {
        guard let front = NSWorkspace.shared.frontmostApplication else { return "нет активного приложения" }
        let bundleId = front.bundleIdentifier ?? "—"
        let app = AXUIElementCreateApplication(front.processIdentifier)
        var focusedRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard err == .success, let elem = focusedRef as! AXUIElement? else {
            return "\(bundleId), фокуса нет (код \(err.rawValue))"
        }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
        return "\(bundleId), фокус: \(roleRef as? String ?? "?")"
    }

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

        // 4. Для остальных приложений (VS Code, Xcode, Telegram, Slack, Notes, Word, Terminal и др.)
        //
        // Нет сфокусированного элемента — значит вставлять физически некуда: пользователь
        // кликнул по пустому месту окна или по рабочему столу. Раньше здесь стоял
        // безусловный `return true`, и текст молча уходил в пустоту, а карточка
        // «Скопировать» не показывалась — сказанное просто пропадало.
        guard err == .success, let elem = focusedRef as! AXUIElement? else {
            return false
        }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        // Фокус на кнопке, картинке или неизменяемой подписи — не поле ввода.
        if role == (kAXButtonRole as String)
            || role == (kAXImageRole as String)
            || role == (kAXStaticTextRole as String) {
            return false
        }

        // Всё остальное считаем пригодным: многие редакторы и терминалы отдают
        // нестандартные роли, и требовать от них строго текстовую роль — значит
        // сломать вставку там, где она сейчас работает.
        return true
    }
}
