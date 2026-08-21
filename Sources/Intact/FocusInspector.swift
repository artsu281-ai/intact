import AppKit
import ApplicationServices

/// Проверка активного контекста перед вставкой:
///
/// 1. В активных пользовательских приложениях (Antigravity, браузеры, редакторы, мессенджеры и др.)
///    текст автоматически доставляется в выбранное поле ввода через ⌘V или прямую печать.
/// 2. Если поле ввода не выбрано (нажатие на пустом рабочем столе Finder, в Dock или системных панелях) —
///    приложение показывает всплывающую карточку с текстом и кнопкой «Скопировать»,
///    которая автоматически скрывается по таймауту (по умолчанию 5 секунд).
enum FocusInspector {

    /// Системные бандлы рабочего стола и системных панелей macOS
    private static let systemExcludedBundles: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight"
    ]

    /// Определяет, есть ли в данный момент возможность доставить текст в активное приложение.
    static var canInsertText: Bool {
        guard Permissions.accessibility else { return false }

        // Проверяем текущее активное приложение
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let bundleId = frontApp.bundleIdentifier ?? ""

        // Игнорируем собственное приложение и системные панели
        if bundleId.isEmpty || bundleId == Bundle.main.bundleIdentifier || systemExcludedBundles.contains(bundleId) {
            return false
        }

        // Особый случай для Finder: на пустом рабочем столе или в списке файлов без переименования вставки нет
        if bundleId == "com.apple.finder" {
            let system = AXUIElementCreateSystemWide()
            var focused: CFTypeRef?
            if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
               let raw = focused {
                let element = raw as! AXUIElement
                var roleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
                let role = roleRef as? String ?? ""
                // Если в Finder фокус в поле переименования файла или строке поиска — разрешаем вставку
                if role == (kAXTextFieldRole as String) || role == "AXSearchField" {
                    return true
                }
            }
            return false
        }

        // Для любого пользовательского приложения (Antigravity, Chrome, VS Code, Telegram, Safari, Word и др.)
        // разрешаем прямую доставку текста
        return true
    }
}
