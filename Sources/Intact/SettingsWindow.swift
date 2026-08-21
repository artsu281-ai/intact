import AppKit
import SwiftUI

/// Мост совместимости: перенаправляет вызовы открытия настроек в главное окно MainWindow.
final class SettingsWindow {
    static let shared = SettingsWindow()
    private init() {}

    func show(section: SettingsSection? = nil) {
        MainWindow.shared.show(tab: .settings, section: section)
    }
}
