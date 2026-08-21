import AppKit
import SwiftUI

/// Мост совместимости: перенаправляет вызовы открытия чата в главное окно MainWindow.
final class ChatWindow {
    static let shared = ChatWindow()
    private init() {}

    func show() {
        MainWindow.shared.show(tab: .chat)
    }

    func toggle() {
        MainWindow.shared.toggle()
    }
}
