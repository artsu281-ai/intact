import AppKit
import SwiftUI

/// Вкладка диалога с персональным ИИ-ассистентом и контекстного анализа
/// голосовых записей, заметок и напоминаний.
struct ChatTab: View {
    @ObservedObject var settings: AppSettings
    var onOpenSection: ((SettingsSection) -> Void)? = nil

    @ObservedObject private var chat = AIChatService.shared
    @ObservedObject private var controller = DictationController.shared
    @State private var inputText: String = ""
    @State private var copiedMessageID: UUID? = nil
    @State private var showContextPopover: Bool = false
    @State private var isChatRecording: Bool = false
    /// Видимость списка чатов переживает перезапуск.
    @AppStorage("chatThreadRailVisible") private var railVisible: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            if railVisible {
                ChatThreadRail()
                Rectangle().fill(Palette.hairline).frame(width: 1)
            }
            chatColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.page)
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            ContentColumn {
                Text(pageTitle)
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 46)
            .padding(.bottom, 20)

            // ── Sticky-хедер с провайдером и контекстом ─────────────────
            VStack(spacing: 0) {
                ContentColumn { stickyProviderHeader }
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
            .background(Palette.page)
            .zIndex(10)

            if hasConversation {
                conversationBody
            } else {
                // Пустой чат не прокручивается: приглашение стоит по центру
                // свободного места, а не прижимается к шапке.
                ContentColumn {
                    VStack(alignment: .leading, spacing: 22) {
                        quickAnalysisSection
                        if let err = chat.errorMessage { errorBanner(err) }
                    }
                }
                .padding(.top, 20)

                Spacer(minLength: 24)
                ContentColumn { emptyStateView }
                Spacer(minLength: 24)
            }

            // ── Закреплённый ввод внизу ────────────────────────────────
            VStack(spacing: 0) {
                Rectangle().fill(Palette.hairline).frame(height: 1)
                ContentColumn { inputFooter }
            }
            .background(Palette.page)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.page)
    }

    private var hasConversation: Bool { !chat.messages.isEmpty || chat.isGenerating }

    /// Заголовок страницы: имя активной ветки важнее слова «Чат» — оно и так
    /// написано в боковом меню.
    private var pageTitle: String {
        guard let thread = chat.activeThread, !thread.isEmpty else { return L10n.tabChat }
        return thread.title
    }

    // MARK: - Тело диалога

    private var conversationBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ContentColumn {
                    VStack(alignment: .leading, spacing: 22) {
                        quickAnalysisSection
                            .padding(.top, 20)

                        if let err = chat.errorMessage {
                            errorBanner(err)
                        }

                        if !chat.messages.isEmpty {
                            conversationHeader

                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(chat.messages) { msg in
                                    bubbleRow(msg)
                                }
                            }
                        }

                        if chat.isGenerating {
                            generatingIndicator.id("generating")
                        }

                        Color.clear.frame(height: 8).id("bottom")
                    }
                }
                .padding(.bottom, 8)
            }
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
            // Пока ответ печатается, число сообщений не меняется — следим
            // за длиной последнего, иначе текст уползал бы под нижний край.
            .onChange(of: chat.messages.last?.content.count ?? 0) { _, _ in
                proxy.scrollTo("bottom")
            }
            .onChange(of: chat.isGenerating) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    private var quickAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("БЫСТРЫЙ АНАЛИЗ")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .kerning(0.8)
            quickChipsRow
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            IntactIcon(kind: .error, size: 15)
                .foregroundStyle(Palette.iconDanger)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.iconDanger)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.iconDanger.opacity(0.08))
        )
    }

    private var conversationHeader: some View {
        HStack {
            Text("ДИАЛОГ")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .kerning(0.8)
            Spacer()
            Button {
                chat.clearHistory()
            } label: {
                HStack(spacing: 5) {
                    IntactIcon(kind: .clearChat, size: 12)
                    Text("Очистить (\(chat.messages.count))")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var generatingIndicator: some View {
        HStack(spacing: 10) {
            ThinkingDots(size: 18, tone: .process)
            Text("Анализирую и формирую ответ…")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.dropdownBg)
        )
    }

    // MARK: - Sticky провайдер-хедер

    private var stickyProviderHeader: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { railVisible.toggle() }
            } label: {
                IntactIcon(kind: railVisible ? .chevronLeft : .chevronRight, size: 12)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(railVisible ? "Скрыть список чатов" : "Показать список чатов")

            AIModelPicker(
                onOpenSettings: { onOpenSection?(.settings) },
                onOpenModels:   { onOpenSection?(.models) }
            )

            Rectangle().fill(Palette.hairline).frame(width: 1, height: 14)

            // Кнопка контекста с кастомным поповером
            Button {
                showContextPopover.toggle()
            } label: {
                HStack(spacing: 5) {
                    IntactIcon(kind: .context, size: 12)
                    Text("Контекст: \(chat.selectedContextSources.count)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    Capsule()
                        .fill(Palette.pill)
                        .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showContextPopover, arrowEdge: .bottom) {
                contextSelectionPopover
            }

            Spacer()

            Button {
                onOpenSection?(.settings)
            } label: {
                HStack(spacing: 4) {
                    IntactIcon(kind: .settings, size: 12)
                    Text("Настройки ИИ")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Поповер выбора источников контекста

    private var contextSelectionPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ИСТОЧНИКИ ДАННЫХ ДЛЯ ИИ")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .kerning(0.6)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)

            contextToggleRow(
                source: .dictationToday,
                icon: .voice,
                title: "Диктовки за сегодня",
                subtitle: "Анализировать голосовые записи сегодняшнего дня"
            )
            contextToggleRow(
                source: .dictationRecent,
                icon: .history,
                title: "Все диктовки",
                subtitle: "История прошлых дней"
            )
            contextToggleRow(
                source: .appleNotes,
                icon: .briefs,
                title: "Заметки Apple Notes",
                subtitle: "Заметки из папки Intact"
            )
            contextToggleRow(
                source: .appleReminders,
                icon: .quickTasks,
                title: "Напоминания",
                subtitle: "Задачи из Apple Reminders"
            )
        }
        .padding(14)
        .frame(width: 280)
    }

    private func contextToggleRow(source: AIContextSource, icon: IntactIconKind, title: String, subtitle: String) -> some View {
        let isSelected = chat.selectedContextSources.contains(source)
        return Button {
            if isSelected { chat.selectedContextSources.remove(source) }
            else { chat.selectedContextSources.insert(source) }
        } label: {
            HStack(spacing: 10) {
                IntactIcon(kind: icon, size: 15)
                    .foregroundStyle(isSelected ? Palette.accent : Palette.textTertiary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    IntactIcon(kind: .copied, size: 13)
                        .foregroundStyle(Palette.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Palette.accent.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Чипы быстрого анализа

    private var quickChipsRow: some View {
        HStack(spacing: 10) {
            quickChip(iconKind: .quickSummary, label: "Сводка за сегодня")  { chat.analyzeTodayDictations() }
            quickChip(iconKind: .quickTasks,   label: "Извлечь задачи")      { chat.extractTasksFromHistoryAndNotes() }
            quickChip(iconKind: .quickNotes,   label: "Сводка заметок")        { chat.summarizeNotes() }
            Spacer()
        }
    }

    private func quickChip(iconKind: IntactIconKind, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                IntactIcon(kind: iconKind, size: 14)
                    .foregroundStyle(Palette.accent)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7.5)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 4, y: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(chat.isGenerating)
        .opacity(chat.isGenerating ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.15), value: chat.isGenerating)
    }

    // MARK: - Пустое состояние

    private var emptyStateView: some View {
        HStack(spacing: 14) {
            IconTile(kind: .aiStar, tone: .active, side: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ассистент готов к работе")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text("Задайте вопрос ниже или запустите быстрый анализ выше")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        )
    }

    // MARK: - Пузырь сообщения

    private func bubbleRow(_ msg: ChatMessage) -> some View {
        let isUser = msg.role == .user
        return HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 80) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                // Метка и бейджи
                HStack(spacing: 5) {
                    if !isUser {
                        IntactIcon(kind: .aiStar, size: 11)
                            .foregroundStyle(Palette.accent)
                        Text("Intact ИИ")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }

                    ForEach(msg.contextBadges, id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Palette.pill))
                            .foregroundStyle(Palette.textSecondary)
                    }

                    if isUser {
                        IntactIcon(kind: .user, size: 11)
                            .foregroundStyle(Palette.textTertiary)
                        Text("Вы")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }

                    Text(timeString(from: msg.timestamp))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textTertiary)
                }

                // Тело пузыря.
                // Реплику пользователя показываем как есть: это надиктованный
                // текст, и разбор разметки только испортил бы звёздочки и дефисы.
                Group {
                    if isUser {
                        Text(msg.content)
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.textPrimary)
                            .textSelection(.enabled)
                            .lineSpacing(3.5)
                    } else {
                        MarkdownMessage(text: msg.content)
                    }
                }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10.5)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isUser ? Palette.accent.opacity(0.11) : Palette.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        isUser ? Palette.accent.opacity(0.22) : Palette.hairline,
                                        lineWidth: 1
                                    )
                            )
                    )

                // Копировать — только для AI
                if !isUser {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(msg.content, forType: .string)
                        copiedMessageID = msg.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedMessageID == msg.id { copiedMessageID = nil }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            IntactIcon(kind: copiedMessageID == msg.id ? .copied : .copy, size: 12)
                            Text(copiedMessageID == msg.id ? "Скопировано" : "Копировать ответ целиком")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !isUser { Spacer(minLength: 80) }
        }
        .transition(.asymmetric(
            insertion: .move(edge: isUser ? .trailing : .leading).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Закреплённый ввод

    private var inputFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !chat.attachedFiles.isEmpty {
                attachedFilesRow
            }
            inputRow
        }
    }

    private var attachedFilesRow: some View {
        HStack(spacing: 6) {
            ForEach(chat.attachedFiles) { file in
                HStack(spacing: 5) {
                    IntactIcon(kind: .folder, size: 11)
                        .foregroundStyle(Palette.textTertiary)
                    Text(file.displayName)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    Button {
                        chat.removeAttachedFile(file.id)
                    } label: {
                        IntactIcon(kind: .error, size: 9)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Palette.pill))
            }
            Spacer()
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Поле ввода или интерактивная полоса голосовой записи
            Group {
                if isChatRecording && controller.state == .recording {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Palette.iconDanger)
                            .frame(width: 9, height: 9)
                            .opacity(controller.blink ? 0.3 : 1.0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(), value: controller.blink)

                        Text("Идёт запись… (\(controller.elapsedText))")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)

                        Spacer()

                        CompactEqualizer(level: controller.level, theme: settings.appTheme)
                            .frame(width: 44, height: 18)

                        Button {
                            controller.cancel()
                            isChatRecording = false
                        } label: {
                            Text("Отмена")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Palette.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Palette.pill))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10.5)
                } else if isChatRecording && (controller.state == .transcribing || controller.state == .processingAI) {
                    HStack(spacing: 10) {
                        ThinkingDots(size: 18, tone: .voice)
                        Text("Распознавание речи Whisper…")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10.5)
                } else {
                    TextField("Спросите что-нибудь или надиктуйте голосом…", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .onSubmit { sendMessage() }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isChatRecording ? Palette.iconDanger.opacity(0.4) : Palette.hairline, lineWidth: 1)
                    )
            )

            // Прикрепить файл или папку — доступ по явному выбору в системном
            // диалоге, а не по фоновому разрешению на весь диск.
            Button {
                attachFilesViaPanel()
            } label: {
                IntactIcon(kind: .folder, size: 15)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Palette.pill))
            }
            .buttonStyle(.plain)
            .help("Прикрепить файл или папку")

            // Кнопка голосового сообщения (ГС / микрофон)
            Button {
                toggleVoiceRecording()
            } label: {
                ZStack {
                    if isChatRecording && controller.state == .recording {
                        IntactIcon(kind: .stop, size: 14)
                            .foregroundStyle(Color.white)
                    } else if isChatRecording && (controller.state == .transcribing || controller.state == .processingAI) {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        IntactIcon(kind: .voice, size: 15)
                            .foregroundStyle(Palette.accent)
                    }
                }
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(isChatRecording && controller.state == .recording ? Palette.iconDanger : Palette.accent.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .help(isChatRecording ? "Остановить и отправить запрос" : "Голосовой запрос в чат (нажмите для записи)")

            // Кнопка отправки текста — во время генерации превращается в «Стоп»
            // и остаётся кликабельной, а не просто меняет иконку задизейбленной.
            let canSend = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.isGenerating
            Button {
                if chat.isGenerating { chat.stopGenerating() } else { sendMessage() }
            } label: {
                IntactIcon(kind: chat.isGenerating ? .stop : .send, size: 14)
                    .foregroundStyle(canSend || chat.isGenerating ? .white : Palette.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(canSend || chat.isGenerating ? Palette.accent : Palette.pill)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend && !chat.isGenerating)
            .help(chat.isGenerating ? "Остановить генерацию" : "Отправить")
            .animation(.spring(response: 0.22), value: canSend)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func toggleVoiceRecording() {
        if isChatRecording && controller.state == .recording {
            controller.stop()
        } else if controller.state == .idle {
            isChatRecording = true
            controller.startCustomDictation { recognized in
                isChatRecording = false
                let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    chat.send(prompt: trimmed)
                }
            }
        }
    }

    private func attachFilesViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Прикрепить"
        panel.message = "Выберите файлы или папку, которые ИИ сможет прочитать в этом диалоге"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        chat.attachFiles(urls: panel.urls)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        chat.send(prompt: text)
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
