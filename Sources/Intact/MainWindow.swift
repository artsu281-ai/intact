import AppKit
import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case chat
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:     return "Чат с ИИ"
        case .settings: return "Настройки"
        }
    }

    var icon: String {
        switch self {
        case .chat:     return "sparkles"
        case .settings: return "slider.horizontal.3"
        }
    }
}

final class MainWindowState: ObservableObject {
    static let shared = MainWindowState()
    @Published var selectedTab: MainTab = .chat
    @Published var settingsSection: SettingsSection = .general
}

/// Главное окно Intact — объединяет ИИ-чат (ассистент, анализ заметок и диктовок)
/// и раздел настроек распознавания речи, моделей и системы.
final class MainWindow {
    static let shared = MainWindow()
    private var window: NSWindow?

    private init() {}

    func show(tab: MainTab = .chat, section: SettingsSection? = nil) {
        MainWindowState.shared.selectedTab = tab
        if let section {
            MainWindowState.shared.settingsSection = section
        }

        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.title = "Intact"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: MainView())
            w.minSize = NSSize(width: 860, height: 620)
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
