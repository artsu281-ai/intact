import AppKit
import SwiftUI

/// Окно чата с ИИ и контекстного анализа заметок / истории.
/// Создаётся и управляется через AppKit, доступно из меню, дока и шортката.
final class ChatWindow {
    static let shared = ChatWindow()
    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.title = "Чат с ИИ — Intact"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: ChatView())
            w.minSize = NSSize(width: 500, height: 580)
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
