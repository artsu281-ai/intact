import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Кнопка, которая ловит следующее сочетание клавиш и записывает его в настройки.
struct HotKeyRecorder: View {
    @ObservedObject var settings: AppSettings
    @State private var listening = false
    @State private var monitor: Any?
    @State private var hovering = false

    var body: some View {
        Button(action: toggleListening) {
            HStack(spacing: 6) {
                if listening {
                    Circle()
                        .fill(Palette.iconWarning)
                        .frame(width: 7, height: 7)
                    Text(T("Нажмите клавиши…", "Press keys…"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                } else {
                    IntactIcon(kind: .keyboard, size: 14)
                        .foregroundStyle(Palette.textSecondary)
                    Text(HotKeyManager.describe(keyCode: settings.hotKeyCode,
                                                modifiers: settings.hotKeyModifiers))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7.5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(listening ? Palette.cardHighlight : (hovering ? Palette.pillHover : Palette.pill))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(listening ? Palette.iconWarning.opacity(0.6) : Palette.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onDisappear(perform: stopListening)
    }

    private func toggleListening() {
        listening ? stopListening() : startListening()
    }

    private func startListening() {
        listening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let mods = HotKeyManager.carbonModifiers(from: event.modifierFlags)
            if event.keyCode == UInt16(kVK_Escape) && mods == 0 {
                stopListening()
                return nil
            }
            guard mods != 0 else { return nil }   // без модификатора хоткей перехватит обычный ввод
            settings.hotKeyCode = Int(event.keyCode)
            settings.hotKeyModifiers = mods
            stopListening()
            return nil
        }
    }

    private func stopListening() {
        listening = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

