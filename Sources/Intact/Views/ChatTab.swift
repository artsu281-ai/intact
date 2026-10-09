import AppKit
import SwiftUI

/// Вкладка диалога с персональным ИИ-ассистентом и контекстного анализа
/// голосовых записей, заметок и напоминаний.
/// Круглая кнопка композера: лёгкая подсветка при наведении и нажатии,
/// одинаковая у вложения, Gemini, микрофона и отправки.
private struct ComposerButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(Circle().fill(Color.white.opacity(hovering && isEnabled ? 0.07 : 0)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct ChatTab: View {
    /// Высота всех элементов шапки — модель, облако, контекст, настройки.
    static let headerChipHeight: CGFloat = 26
    /// Сторона круглых кнопок композера и минимальная высота поля ввода.
    static let composerSide: CGFloat = 40

    // Подписка на тему: см. `ThemeReader` в Theme.swift. Без неё вид
    // останется в старых цветах при смене темы. Не удалять как неиспользуемое.
    @ThemeReader var themeStamp

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
                        if let err = chat.errorInfo { errorBanner(err) }
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

    /// Чат — единственный раздел, где наружу уходит не только надиктованная
    /// фраза, но и заметки, напоминания и файлы. Об этом стоит говорить прямо.
    private var isCloudChat: Bool {
        AIRouter.shared.routing(for: .chat)?.isCloud == true
    }

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

                        if let err = chat.errorInfo {
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
            Text(T("БЫСТРЫЙ АНАЛИЗ", "QUICK ANALYSIS"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .kerning(0.8)
            quickChipsRow
        }
    }

    /// Ошибка с кнопкой, ведущей туда, где её можно починить. Сообщение
    /// без действия — это тупик: человек читает «Ошибка 401» и остаётся
    /// с ней один на один.
    private func errorBanner(_ info: AIErrorInfo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IntactIcon(kind: .error, size: 15)
                .foregroundStyle(Palette.iconDanger)
                .padding(.top, 1)
            Text(info.message)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.iconDanger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let label = info.actionLabel, let section = info.section {
                Button { onOpenSection?(section) } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.iconDanger)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background(Capsule().fill(Palette.iconDanger.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
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
            Text(T("ДИАЛОГ", "CONVERSATION"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .kerning(0.8)
            Spacer()
            Button {
                exportReport()
            } label: {
                HStack(spacing: 5) {
                    IntactIcon(kind: .export, size: 12)
                    Text(T("Выгрузить", "Export"))
                        .font(.system(size: 12))
                }
                .foregroundStyle(Palette.textTertiary)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(T("Сохранить весь диалог в файл Markdown", "Save the whole conversation to a Markdown file"))

            Button {
                chat.clearHistory()
            } label: {
                HStack(spacing: 5) {
                    IntactIcon(kind: .clearChat, size: 12)
                    Text(T("Очистить (\(chat.messages.count))", "Clear (\(chat.messages.count))"))
                        .font(.system(size: 12))
                }
                .foregroundStyle(Palette.textTertiary)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
        }
    }

    /// Отчёт по разговору. Раньше кнопка жила в «Брифах» — за экран от
    /// переписки, которую она выгружает.
    private func exportReport() {
        let text = Exporter.reportMarkdown(chat.messages)
        switch Exporter.save(text: text, suggestedName: T("Intact-отчёт-\(Exporter.fileStamp())", "Intact-report-\(Exporter.fileStamp())")) {
        case .saved(let url):  Exporter.reveal(url)
        case .cancelled:       break
        case .failed(let msg): chat.errorInfo = AIErrorInfo(message: msg)
        }
    }

    /// Пока модель рассуждает, показывать нечего: ход мысли идёт отдельным
    /// полем и в ответ не попадает. На локальной 27B это минуты тишины,
    /// в которые индикатор выглядит зависшим — поэтому он называет, что
    /// именно происходит, и считает секунды.
    private var generatingIndicator: some View {
        HStack(spacing: 10) {
            ThinkingDots(size: 18, tone: .process)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(generatingLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if chat.generationElapsed > 20 {
                Button { chat.stopGenerating() } label: {
                    Text(T("Остановить", "Stop"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.dropdownBg)
        )
    }

    private var generatingLabel: String {
        if let tool = chat.toolStatus { return tool }

        let reasons = AIRouter.shared.routing(for: .chat)?.thinks == true
        let base = reasons
            ? T("Модель обдумывает ответ — текст появится, когда она закончит",
                "The model is thinking — text appears once it is done")
            : T("Анализирую и формирую ответ…", "Reading and writing the answer…")

        let elapsed = Int(chat.generationElapsed)
        guard elapsed >= 3 else { return base }
        return "\(base) · \(elapsed / 60):\(String(format: "%02d", elapsed % 60))"
    }

    // MARK: - Sticky провайдер-хедер

    /// Шапка чата с деградацией по ширине.
    ///
    /// Замерено метриками AppKit: в полном виде шапке нужно 677 pt, а область
    /// чата при открытом списке чатов даёт около 520. Одного `lineLimit` мало —
    /// он убирает разрыв слов, но переполнение остаётся, и шапка просто
    /// обрезается краем. Поэтому здесь три варианта, и `ViewThatFits` берёт
    /// первый, который влезает целиком:
    ///
    /// - полный — 677 pt;
    /// - без подписи «уходит в облако», замок остаётся — 587 pt;
    /// - плюс «Настройки ИИ» одной шестерёнкой — 501 pt.
    ///
    /// Внутри каждого варианта сжиматься позволено только названию модели
    /// (`AIModelPicker` усекает его многоточием) — всё прочее стоит на
    /// `fixedSize`, иначе SwiftUI начинает ломать подписи по слогам.
    private var stickyProviderHeader: some View {
        ViewThatFits(in: .horizontal) {
            headerRow(cloudLabel: true, settingsLabel: true)
            headerRow(cloudLabel: false, settingsLabel: true)
            headerRow(cloudLabel: false, settingsLabel: false)
        }
        .padding(.vertical, 10)
    }

    private func headerRow(cloudLabel: Bool, settingsLabel: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { railVisible.toggle() }
            } label: {
                IntactIcon(kind: railVisible ? .chevronLeft : .chevronRight, size: 12)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: Self.headerChipHeight, height: Self.headerChipHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(railVisible ? T("Скрыть список чатов", "Hide chat list") : T("Показать список чатов", "Show chat list"))

            AIModelPicker(
                role: .chat,
                outlined: true,
                onOpenSettings: { onOpenSection?(.settings) },
                onOpenModels:   { onOpenSection?(.models) }
            )
            .frame(height: Self.headerChipHeight)

            if isCloudChat {
                HStack(spacing: 4) {
                    IntactIcon(kind: .lock, size: 10)
                    if cloudLabel {
                        Text(T("уходит в облако", "goes to the cloud"))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .foregroundStyle(Palette.iconWarning)
                .padding(.horizontal, 9)
                .frame(height: Self.headerChipHeight)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.iconWarning.opacity(0.12)))
                .help(T("Сообщения, диктовки, заметки и содержимое прикреплённых файлов отправляются на серверы Google", "Messages, dictations, notes and the contents of attached files are sent to Google's servers"))
            }

            Rectangle().fill(Palette.hairline).frame(width: 1, height: 16)

            // Кнопка контекста с кастомным поповером
            Button {
                showContextPopover.toggle()
            } label: {
                HStack(spacing: 5) {
                    IntactIcon(kind: .context, size: 12)
                    Text(contextLabel)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: Self.headerChipHeight)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.pill)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
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
                    if settingsLabel {
                        Text(T("Настройки ИИ", "AI settings"))
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .foregroundStyle(Palette.textTertiary)
                .frame(height: Self.headerChipHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // В сжатых вариантах от подписей остаются одни значки — смысл
            // должен оставаться доступным хотя бы по наведению.
            .help(T("Настройки ИИ", "AI settings"))
        }
    }

    // MARK: - Поповер выбора источников контекста

    /// Объём контекста виден прямо на кнопке: он уходит в каждый запрос
    /// и оплачивается, а раньше о его размере нельзя было узнать вообще.
    private var contextLabel: String {
        let count = chat.selectedContextSources.count
        let tokens = chat.estimatedContextTokens
        guard tokens > 0 else { return T("Контекст: \(count)", "Context: \(count)") }
        let short = tokens >= 1000
            ? String(format: "%.1fk", Double(tokens) / 1000)
            : "\(tokens)"
        return T("Контекст: \(count) · ≈\(short) ток.", "Context: \(count) · ≈\(short) tok.")
    }

    private var contextSelectionPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(T("ИСТОЧНИКИ ДАННЫХ ДЛЯ ИИ", "DATA SOURCES FOR THE AI"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .kerning(0.6)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)

            contextToggleRow(
                source: .dictationToday,
                icon: .voice,
                title: T("Диктовки за сегодня", "Today's dictations"),
                subtitle: T("Анализировать голосовые записи сегодняшнего дня", "Analyse today's voice recordings")
            )
            contextToggleRow(
                source: .dictationRecent,
                icon: .history,
                title: T("Все диктовки", "All dictations"),
                subtitle: T("История прошлых дней", "History from previous days")
            )
            contextToggleRow(
                source: .appleNotes,
                icon: .briefs,
                title: T("Заметки Apple Notes", "Apple Notes"),
                subtitle: T("Заметки из папки Intact", "Notes from the Intact folder")
            )
            contextToggleRow(
                source: .appleReminders,
                icon: .quickTasks,
                title: T("Напоминания", "Reminders"),
                subtitle: T("Задачи из Apple Reminders", "Tasks from Apple Reminders")
            )

            Divider().overlay(Palette.hairline).padding(.vertical, 4)

            contextFreshnessRow
        }
        .padding(14)
        .frame(width: 300)
    }

    /// Контекст собирается один раз на разговор — значит, нужно видеть,
    /// когда именно, и уметь пересобрать: данные с утра к вечеру устаревают.
    private var contextFreshnessRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.contextGatheredAt == nil
                     ? T("Контекст ещё не собран", "Context not gathered yet")
                     : T("Собран в \(timeString(from: chat.contextGatheredAt!))", "Gathered at \(timeString(from: chat.contextGatheredAt!))"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                Text(T("Один набор на весь разговор — не пересобирается на каждую реплику", "One set for the whole conversation — not rebuilt on every message"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if chat.isGatheringContext {
                ProgressView().controlSize(.small)
            } else {
                Button { chat.refreshContext() } label: {
                    HStack(spacing: 4) {
                        IntactIcon(kind: .refresh, size: 11)
                        Text(T("Обновить", "Refresh")).font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.accent.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
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
            quickChip(iconKind: .quickSummary, label: T("Сводка за сегодня", "Today's summary"))  { chat.analyzeTodayDictations() }
            quickChip(iconKind: .quickTasks,   label: T("Извлечь задачи", "Extract tasks"))      { chat.extractTasksFromHistoryAndNotes() }
            quickChip(iconKind: .quickNotes,   label: T("Сводка заметок", "Notes summary"))        { chat.summarizeNotes() }
            Spacer()
        }
    }

    private func quickChip(iconKind: IntactIconKind, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                IntactIcon(kind: iconKind, size: 14)
                    .foregroundStyle(Palette.accent)
                // Подпись чипа не переносится: «Извлечь задачи» уезжало в две
                // строки, пока соседи оставались в одну, и ряд разъезжался по
                // высоте. Чип узкий и короткий — ему честнее быть шире, чем
                // выше.
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
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
                Text(T("Ассистент готов к работе", "The assistant is ready"))
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text(T("Задайте вопрос ниже или запустите быстрый анализ выше", "Ask a question below or run a quick analysis above"))
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
                        Text(T("Intact ИИ", "Intact AI"))
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
                        Text(T("Вы", "You"))
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
                            Text(copiedMessageID == msg.id ? T("Скопировано", "Copied") : T("Копировать ответ целиком", "Copy the whole answer"))
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

                        Text(T("Идёт запись… (\(controller.elapsedText))", "Recording… (\(controller.elapsedText))"))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)

                        Spacer()

                        CompactEqualizer(level: controller.level, theme: settings.appTheme)
                            .frame(width: 44, height: 18)

                        Button {
                            controller.cancel()
                            isChatRecording = false
                        } label: {
                            Text(T("Отмена", "Cancel"))
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
                        Text(T("Распознавание речи Whisper…", "Whisper is transcribing…"))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10.5)
                } else {
                    TextField(T("Спросите что-нибудь или надиктуйте голосом…", "Ask something, or dictate it"), text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .onSubmit { sendMessage() }
                }
            }
            .frame(minHeight: Self.composerSide, alignment: .center)
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
                    .frame(width: Self.composerSide, height: Self.composerSide)
                    .background(Circle().fill(Palette.pill))
            }
            .buttonStyle(ComposerButtonStyle())
            .help(T("Прикрепить файл или папку", "Attach a file or folder"))

            if settings.geminiIntegrationEnabled && GeminiBridgeService.shared.isInstalled {
                Button {
                    let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? (controller.lastResult.isEmpty ? T("Привет, Gemini!", "Hi, Gemini!") : controller.lastResult)
                        : inputText
                    GeminiBridgeService.shared.sendToGemini(
                        prompt: prompt,
                        autoSubmit: settings.geminiAutoSubmit,
                        newChat: settings.geminiCreateNewChat
                    )
                } label: {
                    IntactIcon(kind: .aiStar, size: 14)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: Self.composerSide, height: Self.composerSide)
                        .background(Circle().fill(Palette.pill))
                }
                .buttonStyle(ComposerButtonStyle())
                .help(T("Отправить в приложение Gemini на Mac", "Send to Gemini app on Mac"))
            }

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
                .frame(width: Self.composerSide, height: Self.composerSide)
                .background(
                    Circle().fill(isChatRecording && controller.state == .recording ? Palette.iconDanger : Palette.accent.opacity(0.12))
                )
            }
            .buttonStyle(ComposerButtonStyle())
            .help(isChatRecording ? T("Остановить и отправить запрос", "Stop and send the request") : T("Голосовой запрос в чат (нажмите для записи)", "Voice request into chat (click to record)"))

            // Кнопка отправки текста — во время генерации превращается в «Стоп»
            // и остаётся кликабельной, а не просто меняет иконку задизейбленной.
            let canSend = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.isGenerating
            Button {
                if chat.isGenerating { chat.stopGenerating() } else { sendMessage() }
            } label: {
                IntactIcon(kind: chat.isGenerating ? .stop : .send, size: 14)
                    .foregroundStyle(canSend || chat.isGenerating ? .white : Palette.textTertiary)
                    .frame(width: Self.composerSide, height: Self.composerSide)
                    .background(
                        Circle().fill(canSend || chat.isGenerating ? Palette.accent : Palette.pill)
                    )
            }
            .buttonStyle(ComposerButtonStyle())
            .disabled(!canSend && !chat.isGenerating)
            .help(chat.isGenerating ? T("Остановить генерацию", "Stop generating") : T("Отправить", "Send"))
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
        panel.prompt = T("Прикрепить", "Attach")
        panel.message = T("Выберите файлы или папку, которые ИИ сможет прочитать в этом диалоге", "Choose files or a folder the AI may read in this conversation")
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
