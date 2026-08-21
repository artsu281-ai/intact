import AppKit
import SwiftUI

/// Окно и интерфейс общения с персональным ИИ-ассистентом Intact,
/// анализа заметок, истории диктовок и напоминаний.
struct ChatView: View {
    @ObservedObject var chat = AIChatService.shared
    @ObservedObject var settings = AppSettings.shared
    var onOpenSettings: ((SettingsSection?) -> Void)? = nil

    @State private var inputText: String = ""
    @State private var copiedMessageID: UUID? = nil
    @State private var showContextSettings = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Palette.hairline).frame(height: 1)

            if chat.messages.isEmpty {
                welcomeView
            } else {
                messageListView
            }

            if let err = chat.errorMessage {
                errorBanner(err)
            }

            Rectangle().fill(Palette.hairline).frame(height: 1)
            bottomBar
        }
        .frame(minWidth: 540, minHeight: 640)
        .background(Palette.page)
        .preferredColorScheme(settings.appTheme.colorScheme)
        .id(settings.appTheme)
    }

    // MARK: - Верхняя панель

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Чат с ИИ")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)

                Button {
                    if let onOpenSettings {
                        onOpenSettings(.ai)
                    } else {
                        SettingsWindow.shared.show()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(providerStatusColor)
                            .frame(width: 6, height: 6)
                        Text(providerStatusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if !chat.messages.isEmpty {
                PillButton(title: "Новый чат", symbol: "plus") {
                    chat.clearHistory()
                }
            }

            Button {
                if let onOpenSettings {
                    onOpenSettings(nil)
                } else {
                    SettingsWindow.shared.show()
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(6)
                    .background(
                        Circle().fill(Palette.dropdownBg)
                    )
            }
            .buttonStyle(.plain)
            .help("Настройки моделей и провайдеров")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Palette.card)
    }

    private var providerStatusColor: Color {
        switch settings.aiProviderKind {
        case .none: return .orange
        case .local: return LocalAIProvider.shared.isReady ? .green : .orange
        case .cloud: return CloudAIProvider.shared.isReady ? .green : .orange
        }
    }

    private var providerStatusText: String {
        switch settings.aiProviderKind {
        case .none:
            return "ИИ выключен (выберите в настройках)"
        case .local:
            let modelName = URL(fileURLWithPath: settings.aiLocalModelPath).deletingPathExtension().lastPathComponent
            return modelName.isEmpty ? "Локальная модель не выбрана" : "Локально · \(modelName)"
        case .cloud:
            return "Облако · \(settings.aiCloudModel)"
        }
    }

    // MARK: - Стартовый экран подсказок

    private var welcomeView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)

                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Palette.accent.opacity(0.15))
                            .frame(width: 54, height: 54)
                        Image(systemName: "sparkles")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }

                    Text("Персональный ассистент")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(Palette.textPrimary)

                    Text("Задайте любой вопрос или используйте быстрый анализ ваших голосовых записей и заметок:")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                VStack(spacing: 10) {
                    promptCard(
                        symbol: "waveform.badge.magnifyingglass",
                        title: "Анализ диктовок за сегодня",
                        subtitle: "Краткая сводка, ключевые мысли и решения из сегодняшних записей"
                    ) {
                        chat.analyzeTodayDictations()
                    }

                    promptCard(
                        symbol: "checklist",
                        title: "Извлечь задачи и TODO",
                        subtitle: "Поиск задач, поручений и дедлайнов в диктовках и заметках"
                    ) {
                        chat.extractTasksFromHistoryAndNotes()
                    }

                    promptCard(
                        symbol: "note.text",
                        title: "Сводка заметок Apple Notes",
                        subtitle: "Выжимка главных тем и идей из ваших заметок в Apple Notes"
                    ) {
                        chat.summarizeNotes()
                    }

                    promptCard(
                        symbol: "lightbulb.fill",
                        title: "Свободный вопрос или формулировка мысли",
                        subtitle: "Напишите любой вопрос, тему для брейншторма или текст для улучшения"
                    ) {
                        inputText = "Помоги структурировать мысль: "
                    }
                }
                .frame(maxWidth: 480)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
        }
    }

    private func promptCard(symbol: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.accent.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Список сообщений

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(chat.messages) { msg in
                        messageBubble(msg)
                            .id(msg.id)
                    }

                    if chat.isGenerating {
                        thinkingIndicator
                            .id("generating_indicator")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .onChange(of: chat.messages.count) { _, _ in
                if let last = chat.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: chat.isGenerating) { _, generating in
                if generating {
                    withAnimation { proxy.scrollTo("generating_indicator", anchor: .bottom) }
                }
            }
        }
    }

    private func messageBubble(_ msg: ChatMessage) -> some View {
        let isUser = msg.role == .user

        return HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 40) }

            if !isUser {
                ZStack {
                    Circle()
                        .fill(Palette.accent.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .padding(.top, 4)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                // Бейджи контекста (если использовался)
                if !msg.contextBadges.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(msg.contextBadges, id: \.self) { badge in
                            HStack(spacing: 3) {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 9))
                                Text(badge)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Palette.dropdownBg)
                                    .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1))
                            )
                            .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }

                // Тело сообщения
                Text(msg.content)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isUser ? Palette.accent.opacity(0.12) : Palette.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isUser ? Palette.accent.opacity(0.3) : Palette.hairline, lineWidth: 1)
                            )
                    )

                // Время и кнопка копирования для ассистента
                HStack(spacing: 8) {
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
                                Image(systemName: copiedMessageID == msg.id ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10))
                                Text(copiedMessageID == msg.id ? "Скопировано" : "Копировать")
                                    .font(.system(size: 10.5))
                            }
                            .foregroundStyle(Palette.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(timeString(from: msg.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                }
                .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }

            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Анализирую и формирую ответ…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
            )

            Spacer()
        }
    }

    private func errorBanner(_ err: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            Text(err)
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Нижняя панель ввода и быстрых действий

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // Быстрые чипы и селектор контекста
            HStack(spacing: 8) {
                quickChip(title: "⚡️ За сегодня") { chat.analyzeTodayDictations() }
                quickChip(title: "📋 Задачи") { chat.extractTasksFromHistoryAndNotes() }
                quickChip(title: "📝 Заметки") { chat.summarizeNotes() }

                Spacer()

                Menu {
                    Toggle("Диктовки за сегодня", isOn: binding(for: .dictationToday))
                    Toggle("История всех диктовок", isOn: binding(for: .dictationRecent))
                    Toggle("Заметки Apple Notes", isOn: binding(for: .appleNotes))
                    Toggle("Напоминания Reminders", isOn: binding(for: .appleReminders))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 11))
                        Text("Контекст: \(chat.selectedContextSources.count)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Palette.dropdownBg)
                            .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1))
                    )
                    .foregroundStyle(Palette.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Поле ввода
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Спросите что-нибудь или введите задачу…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Palette.dropdownBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Palette.hairline, lineWidth: 1)
                            )
                    )
                    .onSubmit {
                        sendMessage()
                    }

                Button {
                    sendMessage()
                } label: {
                    ZStack {
                        Circle()
                            .fill(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isGenerating ? Palette.pill : Palette.accent)
                            .frame(width: 36, height: 36)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isGenerating ? Palette.textTertiary : .white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isGenerating)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Palette.card)
    }

    private func quickChip(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Palette.dropdownBg)
                        .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1))
                )
                .foregroundStyle(Palette.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private func binding(for source: AIContextSource) -> Binding<Bool> {
        Binding(
            get: { chat.selectedContextSources.contains(source) },
            set: { enabled in
                if enabled {
                    chat.selectedContextSources.insert(source)
                } else {
                    chat.selectedContextSources.remove(source)
                }
            }
        )
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        chat.send(prompt: text)
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
