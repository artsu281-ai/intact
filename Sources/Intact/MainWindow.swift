import AppKit
import SwiftUI

final class MainWindowState: ObservableObject {
    static let shared = MainWindowState()
    @Published var section: SettingsSection = .general
}

/// Главное окно Intact — объединяет ИИ-чат (ассистент, анализ заметок и диктовок),
/// историю записей, каталог моделей и все настройки распознавания речи и системы.
final class MainWindow {
    static let shared = MainWindow()
    private var window: NSWindow?

    private init() {}

    func show(section: SettingsSection? = nil) {
        if let section {
            MainWindowState.shared.section = section
        }

        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.title = "Intact"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: SettingsView(section: Binding(
                get: { MainWindowState.shared.section },
                set: { MainWindowState.shared.section = $0 }
            )))
            w.minSize = NSSize(width: 880, height: 640)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func toggle() {
        if let w = window, w.isVisible, w.isKeyWindow {
            w.orderOut(nil)
        } else {
            show()
        }
    }
}
