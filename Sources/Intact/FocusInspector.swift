import AppKit
import ApplicationServices

/// Проверка активного контекста перед вставкой:
///
/// 1. Если фокус находится в текстовом поле / редакторе / терминале — текст сразу
///    вставляется в документ.
/// 2. Если поле ввода не выбрано (пустой рабочий стол Finder, фон окна, нередактируемый UI) —
///    приложение показывает всплывающую карточку с распознанным текстом и кнопкой «Скопировать».
enum FocusInspector {

    private static let editableRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField"
    ]

    /// Приложения-редакторы кода и терминалы, где курсор/ввод всегда активен в открытом окне
    private static let editorBundlePrefixes: [String] = [
        "com.microsoft.VSCode",
        "com.todesktop.",
        "com.sublimetext.",
        "com.jetbrains.",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "io.alacritty",
        "com.mitchellh.ghostty",
        "dev.zed.Zed"
    ]

    /// Системные бандлы рабочего стола и системных панелей
    private static let systemExcludedBundles: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight"
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
        let role = roleRef as? String ?? ""

        if editableRoles.contains(role) { return true }

        // Проверка каретки или выделенного фрагмента текста
        var caret: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &caret) == .success {
            return true
        }

        var selText: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selText) == .success {
            return true
        }

        // Проверка возможности изменения значения
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue { return true }

        return false
    }

    /// Определяет, есть ли в данный момент выбранное поле для автоматической вставки.
    static var canInsertText: Bool {
        guard Permissions.accessibility else { return false }

        // Если фокус явно в текстовом поле
        if hasEditableFocus { return true }

        // Проверяем текущее активное приложение
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let bundleId = frontApp.bundleIdentifier ?? ""

        if bundleId == Bundle.main.bundleIdentifier || systemExcludedBundles.contains(bundleId) {
            return false
        }

        // Особый случай для Finder (на рабочем столе или в списке без переименования вставки нет)
        if bundleId == "com.apple.finder" {
            return false
        }

        // Для редакторов кода и терминалов (VS Code, JetBrains, Terminal и др.)
        if editorBundlePrefixes.contains(where: { bundleId.hasPrefix($0) }) {
            return true
        }

        return false
    }
}
