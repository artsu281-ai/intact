import AppKit
import SwiftUI

/// Окно настроек живёт в AppKit, а не в сцене SwiftUI: так его можно открыть
/// откуда угодно — из меню в строке статуса, из меню Dock, по клику на иконку —
/// не пробрасывая openWindow через окружение.
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.title = "Intact"
            // Заголовок рисуем сами: боковик должен доходить до верха окна,
            // а название раздела стоять над его содержимым, а не над списком.
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: SettingsView())
            w.minSize = NSSize(width: 840, height: 640)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
