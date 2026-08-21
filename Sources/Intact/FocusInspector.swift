import AppKit
import ApplicationServices

/// Проверка активного контекста перед вставкой:
///
/// 1. Во всех активных пользовательских приложениях (Antigravity IDE, VS Code, Chrome, Safari,
///    Telegram, Slack, Notes, Word, Terminal и др.) текст автоматически вставляется на место курсора
///    через ⌘V или прямую печать.
/// 2. Если приложение не активно, либо активен пустой рабочий стол Finder / системные панели —
///    показывается карточка «Скопировать», которая автоматически исчезает через выбранное время (по умолчанию 5с).
enum FocusInspector {

    private static let systemExcludedBundles: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.loginwindow"
    ]

    /// Определяет, есть ли в данный момент возможность доставить текст в активное приложение.
    static var canInsertText: Bool {
        guard Permissions.accessibility else { return false }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let bundleId = frontApp.bundleIdentifier ?? ""

        // Игнорируем собственное приложение и системные панели
        if bundleId.isEmpty || bundleId == Bundle.main.bundleIdentifier || systemExcludedBundles.contains(bundleId) {
            return false
        }

        // Особый случай для Finder: на пустом рабочем столе или в списке файлов без переименования вставки нет
        if bundleId == "com.apple.finder" {
            let app = AXUIElementCreateApplication(frontApp.processIdentifier)
            var focused: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
               let raw = focused {
                let element = raw as! AXUIElement
                var roleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
                let role = roleRef as? String ?? ""
                if role == (kAXTextFieldRole as String) || role == "AXSearchField" {
                    return true
                }
            }
            return false
        }

        // Для всех пользовательских приложений (Antigravity IDE, Chrome, VS Code, Telegram, Safari, Word и др.)
        // разрешаем прямую вставку
        return true
    }
}
