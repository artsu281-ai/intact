import AppKit
import SwiftUI

struct IndicatorView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var settings = AppSettings.shared

    private var isDark: Bool {
        settings.isDarkMode
    }

    static let width: CGFloat = 460
    static let listeningSize = NSSize(width: 112, height: 32)
    static let noteSavedSize = NSSize(width: 154, height: 32)
    static let reminderSavedSize = NSSize(width: 196, height: 32)
    private static let copyPad: CGFloat = 16
    private static let bodyFont = NSFont.systemFont(ofSize: 13.5, weight: .regular)

    static func copySize(for text: String) -> NSSize {
        let textH = textHeight(text)
        let h = copyPad + 24 + 10 + textH + 14 + 30 + copyPad
        return NSSize(width: width, height: max(124, h))
    }

    static func textHeight(_ text: String) -> CGFloat {
        let lineHeight = ceil(bodyFont.boundingRectForFont.height) + 4
        let box = (text as NSString).boundingRect(
            with: NSSize(width: width - copyPad * 2, height: lineHeight * 12),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: bodyFont])
        let rawH = ceil(box.height)
        return min(max(24, rawH), 220)
    }

    var body: some View {
        Group {
            if let pending = controller.pendingText {
                noPlaceToInsert(text: pending)
                    .padding(Self.copyPad)
                    .frame(width: Self.copySize(for: pending).width,
                           height: Self.copySize(for: pending).height)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Palette.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Palette.hairline, lineWidth: 1)
                            )
                            .shadow(color: Palette.hudShadow(theme: settings.appTheme), radius: 16, y: 6)
                    )
            } else if controller.noteSavedText != nil {
                noteSavedToast
                    .frame(width: Self.noteSavedSize.width, height: Self.noteSavedSize.height)
                    .background(capsuleBg)
            } else if let remText = controller.reminderSavedText {
                reminderSavedToast(text: remText)
                    .frame(width: Self.reminderSavedSize.width, height: Self.reminderSavedSize.height)
                    .background(capsuleBg)
            } else {
                listening
                    .frame(width: Self.listeningSize.width, height: Self.listeningSize.height)
                    .background(capsuleBg)
            }
        }
        .preferredColorScheme(settings.appTheme.colorScheme)
    }

    private var capsuleBg: some View {
        Capsule()
            .fill(Palette.hudBg(theme: settings.appTheme))
            .overlay(
                Capsule()
                    .strokeBorder(Palette.hudBorder(theme: settings.appTheme), lineWidth: 0.75)
            )
            .shadow(color: Palette.hudShadow(theme: settings.appTheme), radius: 10, y: 3)
    }

    // MARK: - Компактный эстетичный спектр и индикатор записи

    private var listening: some View {
        HStack(spacing: 5) {
            switch controller.state {
            case .recording:
                PulsingVoiceIcon(active: true, size: 13)
                    .foregroundStyle(Palette.hudIcon(theme: settings.appTheme))

                CompactEqualizer(level: controller.level, theme: settings.appTheme)
                    .frame(width: 18, height: 12)

                Text(controller.elapsedText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.hudTextMuted(theme: settings.appTheme))

            case .transcribing:
                ThinkingDots(size: 14)
                    .foregroundStyle(Palette.hudIcon(theme: settings.appTheme))

                Text(L10n.hudTranscribing)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.hudText(theme: settings.appTheme))
                    .lineLimit(1)
                    .fixedSize()

            case .processingAI:
                ThinkingDots(size: 14)
                    .foregroundStyle(Palette.hudIcon(theme: settings.appTheme))

                // Имя модели и выход из ожидания: с крупной моделью пауза
                // длится секунды, и без этих двух подписей непонятно, кто
                // держит текст и можно ли не ждать.
                Text(modelName(for: .cleanup))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.hudText(theme: settings.appTheme))
                    .lineLimit(1)
                    .fixedSize()

                Text(T("⎋ как есть", "⎋ as is"))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.hudTextMuted(theme: settings.appTheme))
                    .lineLimit(1)
                    .fixedSize()

            case .answeringAI:
                ThinkingDots(size: 14)
                    .foregroundStyle(Palette.hudIcon(theme: settings.appTheme))

                Text(modelName(for: .quickAnswer))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.hudText(theme: settings.appTheme))
                    .lineLimit(1)
                    .fixedSize()

            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Подтверждение сохранения заметки

    private var noteSavedToast: some View {
        HStack(spacing: 6) {
            IntactIcon(kind: .success, size: 13)
                .foregroundStyle(Palette.hudTextMuted(theme: settings.appTheme))

            Text(L10n.hudNoteSaved)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.hudText(theme: settings.appTheme))
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Подтверждение сохранения напоминания

    private func reminderSavedToast(text: String) -> some View {
        HStack(spacing: 6) {
            IntactIcon(kind: .reminder, size: 13)
                .foregroundStyle(Palette.hudTextMuted(theme: settings.appTheme))

            Text(L10n.hudReminderSaved)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.hudText(theme: settings.appTheme))

            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.hudTextMuted(theme: settings.appTheme))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Вставлять некуда (Просторная карточка копирования)

    private func noPlaceToInsert(text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                IntactIcon(kind: .clipboardReady, size: 15)
                    .foregroundStyle(Palette.textPrimary)

                Text(L10n.hudTextReady)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)

                let words = text.split { $0.isWhitespace || $0.isNewline }.count
                if words > 0 {
                    Text("• \(words) \(wordsCountLabel(words))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textSecondary)
                }

                Spacer(minLength: 8)

                DismissCountdownButton(seconds: controller.pendingRemainingSeconds) {
                    controller.dismissPending()
                }
            }
            .frame(height: 24)

            Spacer().frame(height: 10)

            ScrollView(.vertical, showsIndicators: Self.textHeight(text) >= 200) {
                Text(text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.textPrimary)
                    .lineSpacing(3.5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Self.textHeight(text))

            Spacer().frame(height: 14)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(verbatim: "\u{2318}")
                        .font(.system(size: 11, weight: .medium))
                    Text(L10n.hudCopyShortcut)
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(Palette.textSecondary)

                Spacer()

                SoftButton(title: L10n.hudCopyBtn, icon: .copy) {
                    controller.copyPending()
                }
                .keyboardShortcut(.defaultAction)
                .keyboardShortcut("c", modifiers: .command)
            }
            .frame(height: 30)
        }
    }

    /// Короткое имя работающей модели: в пилюле фиксированной ширины
    /// «Claude Haiku 4.5» помещается, а «Qwen3.5 9B · Q8_0» — уже нет.
    private func modelName(for role: AIRole) -> String {
        let full = AIModelCatalog.title(for: AIModelCatalog.resolved(for: role))
        return full.split(separator: "·").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? full
    }

    private func wordsCountLabel(_ count: Int) -> String {
        if !L10n.isRu {
            return count == 1 ? "word" : "words"
        }
        let rem10 = count % 10
        let rem100 = count % 100
        if rem10 == 1 && rem100 != 11 { return T("слово", "word") }
        if (2...4).contains(rem10) && !(12...14).contains(rem100) { return T("слова", "words") }
        return T("слов", "words")
    }
}

// MARK: - Компактный анимированный эквалайзер

/// Короткий, ультра-эстетичный спектр из 4 живых анимированных столбиков,
/// динамически адаптирующийся под светлую и тёмную темы оформления.
struct CompactEqualizer: View {
    let level: Float
    var theme: AppTheme = .white

    var body: some View {
        HStack(spacing: 2) {
            EqualizerBar(level: level, minH: 2.5, maxH: 8, weight: 0.6, theme: theme)
            EqualizerBar(level: level, minH: 3.5, maxH: 12, weight: 1.0, theme: theme)
            EqualizerBar(level: level, minH: 3.5, maxH: 12, weight: 0.85, theme: theme)
            EqualizerBar(level: level, minH: 2.5, maxH: 8, weight: 0.55, theme: theme)
        }
    }
}

private struct EqualizerBar: View {
    let level: Float
    let minH: CGFloat
    let maxH: CGFloat
    let weight: CGFloat
    let theme: AppTheme

    private var calculatedHeight: CGFloat {
        let raw = CGFloat(max(0, min(1, level)))
        let h = minH + (maxH - minH) * (raw * weight * 1.8)
        return min(maxH, max(minH, h))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Palette.hudEqTop(theme: theme),
                        Palette.hudEqBottom(theme: theme)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 2.2, height: calculatedHeight)
            .animation(.spring(response: 0.12, dampingFraction: 0.65), value: calculatedHeight)
    }
}

// MARK: - Кнопки панели

struct SoftButton: View {
    let title: String
    let icon: IntactIconKind
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                IntactIcon(kind: icon, size: 13, weight: .medium)
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Palette.pillHover : Palette.pill)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct DismissCountdownButton: View {
    let seconds: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if seconds > 0 {
                    Text(T("\(seconds)с", "\(seconds)s"))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                }
                IntactIcon(kind: .close, size: 10, weight: .medium)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(hovering ? Palette.pillHover : Palette.pill)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct CircleIconButton: View {
    let icon: IntactIconKind
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            IntactIcon(kind: icon, size: 12, weight: .medium)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(hovering ? Palette.pillHover : Palette.pill))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Панель NSPanel

final class IndicatorPanel {
    private var panel: NSPanel?
    private var isInteractive = false

    func show(controller: DictationController, interactive: Bool = false) {
        if panel != nil, interactive == isInteractive { return }
        hide()

        let hosting = NSHostingView(rootView: IndicatorView(controller: controller))
        let isDark = AppSettings.shared.isDarkMode
        let targetAppearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        hosting.appearance = targetAppearance

        let size: NSSize
        if interactive {
            size = IndicatorView.copySize(for: controller.pendingText ?? "")
        } else if controller.noteSavedText != nil {
            size = IndicatorView.noteSavedSize
        } else if controller.reminderSavedText != nil {
            size = IndicatorView.reminderSavedSize
        } else {
            size = IndicatorView.listeningSize
        }
        hosting.frame = NSRect(origin: .zero, size: size)

        let p = KeyablePanel(contentRect: hosting.frame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.appearance = targetAppearance
        p.acceptsKey = interactive
        p.contentView = hosting
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = interactive ? .floating : .statusBar
        p.ignoresMouseEvents = !interactive
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        reposition(p)
        p.orderFrontRegardless()

        panel = p
        isInteractive = interactive
    }

    private func reposition(_ p: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = p.frame.size
        let visible = screen.visibleFrame
        p.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                 y: visible.minY + 90))
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        isInteractive = false
    }
}

final class KeyablePanel: NSPanel {
    var acceptsKey = false
    override var canBecomeKey: Bool { acceptsKey }
}
