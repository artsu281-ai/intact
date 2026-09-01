import AppKit
import SwiftUI

struct IndicatorView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var settings = AppSettings.shared

    private var isDark: Bool {
        settings.isDarkMode
    }

    static let width: CGFloat = 460
    static let listeningSize = NSSize(width: 114, height: 32)
    static let noteSavedSize = NSSize(width: 154, height: 32)
    static let reminderSavedSize = NSSize(width: 196, height: 32)
    static let geminiSentSize = NSSize(width: 220, height: 32)
    private static let copyPad: CGFloat = 16
    private static let bodyFont = NSFont.systemFont(ofSize: 13.5, weight: .regular)

    private static func measureTextWidth(_ text: String, font: NSFont) -> CGFloat {
        let box = (text as NSString).boundingRect(
            with: NSSize(width: 800, height: 32),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(box.width)
    }

    /// Сколько символов черновика помещается в пилюлю: четыре строки шириной ~390 pt
    /// шрифтом 12 pt — это примерно столько.
    private static let draftPreviewLimit = 210

    /// В пилюле показываем **хвост** черновика, а не его начало.
    ///
    /// Раньше сюда уходил весь `draftText` с `lineLimit(4)`, и SwiftUI обрезал его с конца:
    /// на экране навсегда застывали первые четыре строки, а новые слова, ради которых
    /// живой предпросмотр и нужен, были не видны.
    static func draftPreview(_ raw: String) -> String {
        let flat = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard flat.count > draftPreviewLimit else { return flat }

        let tail = flat.suffix(draftPreviewLimit)
        // Обрезаем по границе слова, чтобы фраза не начиналась с половины слова.
        if let space = tail.firstIndex(of: " ") {
            return "… " + tail[tail.index(after: space)...]
        }
        return "… " + tail
    }

    /// Межстрочный интервал черновика. Держим его здесь, чтобы замер высоты и отрисовка
    /// не разъезжались: без него последняя строка подрезалась снизу.
    static let draftLineSpacing: CGFloat = 2

    private static func measureDraftHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = draftLineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        let box = (text as NSString).boundingRect(
            with: NSSize(width: width, height: 200),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph]
        )
        return ceil(box.height)
    }

    static func listeningSize(for controller: DictationController) -> NSSize {
        if let note = controller.noteSavedText {
            let tw = measureTextWidth(note, font: .systemFont(ofSize: 11.5, weight: .medium))
            return NSSize(width: max(148, min(420, tw + 52)), height: 34)
        } else if let rem = controller.reminderSavedText {
            let tw = measureTextWidth(rem, font: .systemFont(ofSize: 11.5, weight: .medium))
            return NSSize(width: max(160, min(420, tw + 52)), height: 34)
        } else if let gem = controller.geminiSentText {
            let tw = measureTextWidth(gem, font: .systemFont(ofSize: 11.5, weight: .medium))
            return NSSize(width: max(170, min(420, tw + 52)), height: 34)
        }

        switch controller.state {
        case .recording:
            return NSSize(width: 224, height: 34)

        case .transcribing:
            return NSSize(width: 236, height: 34)

        case .processingAI:
            return NSSize(width: 256, height: 34)

        case .answeringAI:
            return NSSize(width: 242, height: 34)

        case .idle:
            return NSSize(width: 120, height: 34)
        }
    }

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
        let curSize = Self.listeningSize(for: controller)
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
                    .frame(width: curSize.width, height: curSize.height)
                    .background(dynamicIslandBg(size: curSize))
            } else if controller.reminderSavedText != nil {
                if let remText = controller.reminderSavedText {
                    reminderSavedToast(text: remText)
                        .frame(width: curSize.width, height: curSize.height)
                        .background(dynamicIslandBg(size: curSize))
                }
            } else if let gemText = controller.geminiSentText {
                geminiSentToast(prompt: gemText)
                    .frame(width: curSize.width, height: curSize.height)
                    .background(dynamicIslandBg(size: curSize))
            } else {
                listening(size: curSize)
                    .frame(width: curSize.width, height: curSize.height)
                    .background(dynamicIslandBg(size: curSize))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: controller.state)
        .preferredColorScheme(settings.appTheme.colorScheme)
    }

    private func dynamicIslandBg(size: NSSize) -> some View {
        let radius = min(size.height / 2, 18)
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Palette.hudBg(theme: settings.appTheme))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.hudBorder(theme: settings.appTheme), lineWidth: 0.75)
            )
            .shadow(color: Palette.hudShadow(theme: settings.appTheme), radius: 14, y: 4)
    }

    // MARK: - Бесшовный Dynamic Island индикатор записи

    /// Кто сейчас работает — одной строкой на все состояния пилюли.
    ///
    /// Раньше правильное имя стояло только на записи, а на расшифровке,
    /// причёсывании и ответе были зашиты «Whisper Voice / Whisper Cleanup /
    /// Whisper Answer». Про движок эти строки не спрашивали вообще, поэтому
    /// пилюля годами говорила «Whisper» там, где писал микрофон Gemini.
    private var engineBadge: String {
        // Страховка важнее настройки: если Gemini отвалился и дорасшифровывает
        // локальный Whisper, называть надо его.
        if controller.engineFellBack { return STTEngineType.whisperLocal.badgeName }
        return controller.activePipeline?.displayBadge ?? controller.engineLabel
    }

    @ViewBuilder
    private func listening(size: NSSize) -> some View {
        if controller.state == .recording {
            let badge = engineBadge
            LiveMicrophoneIndicator(
                active: true,
                level: controller.level,
                elapsedText: controller.elapsedText,
                badgeText: badge
            )
            .padding(.horizontal, 12)
            .frame(height: 34)
        } else {
            HStack(spacing: 7) {
                switch controller.state {
                case .recording:
                    EmptyView()

                case .transcribing:
                    ThinkingDots(size: 14)
                        .foregroundStyle(Palette.hudIcon(theme: settings.appTheme))

                    Text("\(engineBadge) · \(T("расшифровка…", "Transcribing…"))")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.hudText(theme: settings.appTheme))
                        .lineLimit(1)
                        .fixedSize()

                case .processingAI:
                    ThinkingDots(size: 14)
                        .foregroundStyle(Palette.hudIcon(theme: settings.appTheme))

                    Text("\(engineBadge) · \(T("причёсываю…", "Polishing…"))")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.hudText(theme: settings.appTheme))
                        .lineLimit(1)
                        .fixedSize()

                    Text("⎋")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Palette.hudTextMuted(theme: settings.appTheme))
                        .lineLimit(1)
                        .fixedSize()

                case .answeringAI:
                    ThinkingDots(size: 14)
                        .foregroundStyle(Palette.hudIcon(theme: settings.appTheme))

                    Text("\(engineBadge) · \(T("думаю…", "Thinking…"))")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.hudText(theme: settings.appTheme))
                        .lineLimit(1)
                        .fixedSize()

                case .idle:
                    EmptyView()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
        }
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

    // MARK: - Подтверждение отправки в Gemini

    private func geminiSentToast(prompt: String) -> some View {
        HStack(spacing: 6) {
            IntactIcon(kind: .aiStar, size: 13)
                .foregroundStyle(Palette.hudTextMuted(theme: settings.appTheme))

            Text(L10n.geminiSentHud)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.hudText(theme: settings.appTheme))

            Text(prompt)
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
    static func modelName(for role: AIRole) -> String {
        let choice = AIModelCatalog.resolved(for: role)
        if choice == .gemini { return "Gemini" }
        let full = AIModelCatalog.title(for: choice)
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

// MARK: - Индикатор микрофона и бейдж Gemini

/// Живой микрофон с пульсирующей точкой записи и эквалайзером
struct LiveMicrophoneIndicator: View {
    let active: Bool
    let level: Float
    let elapsedText: String
    var badgeText: String? = nil
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if active {
                    Circle()
                        .fill(Color.red.opacity(0.25))
                        .frame(width: 12, height: 12)
                        .scaleEffect(1.0 + CGFloat(max(0, min(1, level))) * 0.5)
                }

                Circle()
                    .fill(active ? Color.red : Palette.hudTextMuted(theme: settings.appTheme))
                    .frame(width: 6, height: 6)
            }

            Image(systemName: "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Palette.hudIcon(theme: settings.appTheme) : Palette.hudTextMuted(theme: settings.appTheme))

            CompactEqualizer(level: level, theme: settings.appTheme)
                .frame(width: 16, height: 10)

            Text(elapsedText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.hudTextMuted(theme: settings.appTheme))

            if let badgeText, !badgeText.isEmpty {
                Circle()
                    .fill(Palette.hudBorder(theme: settings.appTheme))
                    .frame(width: 3, height: 3)

                Text(badgeText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.hudText(theme: settings.appTheme))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
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
        let size: NSSize
        if interactive {
            size = IndicatorView.copySize(for: controller.pendingText ?? "")
        } else {
            size = IndicatorView.listeningSize(for: controller)
        }

        if let p = panel {
            if interactive == isInteractive {
                updateFrame(for: p, newSize: size)
                return
            }
        }
        hide()

        let hosting = NSHostingView(rootView: IndicatorView(controller: controller))
        let isDark = AppSettings.shared.isDarkMode
        let targetAppearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        hosting.appearance = targetAppearance
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
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
        reposition(p, size: size)
        p.orderFrontRegardless()

        panel = p
        isInteractive = interactive
    }

    func update(controller: DictationController) {
        guard let p = panel, !isInteractive else { return }
        let size = IndicatorView.listeningSize(for: controller)
        if abs(p.frame.width - size.width) > 1 || abs(p.frame.height - size.height) > 1 {
            updateFrame(for: p, newSize: size)
        }
    }

    private func updateFrame(for p: NSPanel, newSize: NSSize) {
        guard let visible = Self.visibleFrame(for: p) else { return }
        let targetFrame = NSRect(x: visible.midX - newSize.width / 2,
                                 y: visible.minY + 90,
                                 width: newSize.width,
                                 height: newSize.height)
        guard targetFrame != p.frame else { return }

        // Размер меняем мгновенно, без анимации окна.
        //
        // Черновик приходит до десяти раз в секунду, и каждая новая 0,36-секундная
        // анимация перебивала предыдущую в самом начале: окно успевало вырасти
        // на считанные проценты и тут же начинало новую анимацию с того же места.
        // На экране это выглядело как застрявшие первые слова — пилюля просто
        // не догоняла текст. Плавность даёт сам SwiftUI внутри пилюли.
        p.setFrame(targetFrame, display: true)
    }

    private func reposition(_ p: NSPanel, size: NSSize? = nil) {
        guard let visible = Self.visibleFrame(for: p) else { return }
        let targetSize = size ?? p.frame.size
        p.setFrameOrigin(NSPoint(x: visible.midX - targetSize.width / 2,
                                 y: visible.minY + 90))
    }

    /// У неактивирующей панели своего ключевого окна нет, поэтому `NSScreen.main`
    /// иногда пуст — тогда берём экран самой панели или первый доступный.
    private static func visibleFrame(for p: NSPanel) -> NSRect? {
        (p.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
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
