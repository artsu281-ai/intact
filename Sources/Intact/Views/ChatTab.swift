import AppKit
import SwiftUI

/// Вкладка диалога с персональным ИИ-ассистентом и контекстного анализа
/// голосовых записей, заметок и напоминаний.
struct ChatTab: View {
    @ObservedObject var settings: AppSettings
    var onOpenSection: ((SettingsSection) -> Void)? = nil

    @ObservedObject private var chat = AIChatService.shared
    @State private var inputText: String = ""
    @State private var copiedMessageID: UUID? = nil

    var body: some View {
        SettingsPage(title: L10n.tabChat) {
            providerCard
            quickActionsCard
            dialogCard
        }
    }

    // MARK: - Карточка провайдера и контекста

    private var providerCard: some View {
        Card(header: "ИИ-провайдер и контекст") {
            Row(title: "Провайдер интеллекта",
                subtitle: providerSubtitle,
                first: true) {
                PillButton(title: "Настройки ИИ", symbol: "gearshape") {
                    onOpenSection?(.ai)
                }
            }

            Row(title: "Источники контекста",
                subtitle: "Данные, учитываемые ассистентом при ответах и анализе") {
                Menu {
                    Toggle("Диктовки за сегодня", isOn: contextBinding(for: .dictationToday))
                    Toggle("Все недавние диктовки", isOn: contextBinding(for: .dictationRecent))
                    Toggle("Заметки Apple Notes", isOn: contextBinding(for: .appleNotes))
                    Toggle("Напоминания Reminders", isOn: contextBinding(for: .appleReminders))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 11))
                        Text("Активно: \(chat.selectedContextSources.count)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Palette.dropdownBg)
                            .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1))
                    )
                    .foregroundStyle(Palette.textPrimary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var providerSubtitle: String {
        switch settings.aiProviderKind {
        case .none:
            return "ИИ выключен — включите локальную модель или Claude в настройках ИИ"
        case .local:
            let modelName = URL(fileURLWithPath: settings.aiLocalModelPath).deletingPathExtension().lastPathComponent
            let status = LocalAIProvider.shared.isReady ? "Готов" : "Запуск…"
            return "Локальная модель (GGUF): \(modelName.isEmpty ? "не выбрана" : modelName) · \(status)"
        case .cloud:
            return "Облачный провайдер: Anthropic Claude (\(settings.aiCloudModel))"
        }
    }

    // MARK: - Карточка быстрого анализа

    private var quickActionsCard: some View {
        Card(header: "Быстрый анализ записей и заметок") {
            Row(title: "⚡️ Сводка за сегодня",
                subtitle: "Краткая структурированная выжимка мыслей, тем и решений из сегодняшних голосовых записей",
                first: true) {
                PillButton(title: "Запустить", symbol: "waveform.badge.magnifyingglass") {
                    chat.analyzeTodayDictations()
                }
                .disabled(chat.isGenerating)
            }

            Row(title: "📋 Извлечь задачи и TODO",
                subtitle: "Поиск поручений, дел и дедлайнов в истории диктовок и заметках") {
                PillButton(title: "Извлечь", symbol: "checklist") {
                    chat.extractTasksFromHistoryAndNotes()
                }
                .disabled(chat.isGenerating)
            }

            Row(title: "📝 Сводка заметок Apple Notes",
                subtitle: "Выжимка ключевых идей и тем из папки «\(settings.voiceNotesFolder)» в Заметках") {
                PillButton(title: "Сводка", symbol: "note.text") {
                    chat.summarizeNotes()
                }
                .disabled(chat.isGenerating)
            }
        }
    }

    // MARK: - Карточка диалога

    private var dialogCard: some View {
        Card(header: "Диалог с ассистентом") {
            VStack(alignment: .leading, spacing: 0) {
                // Верхний бар карточки диалога
                HStack {
                    Text(chat.messages.isEmpty ? "История пуста" : "Сообщений: \(chat.messages.count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)

                    Spacer()

                    if !chat.messages.isEmpty {
                        PillButton(title: "Очистить диалог", symbol: "trash") {
                            chat.clearHistory()
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)

                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 22)

                // Сообщения или подсказка
                if chat.messages.isEmpty {
                    emptyStateRow
                } else {
                    messagesStreamView
                }

                if let err = chat.errorMessage {
                    Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 22)
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 12))
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.08))
                }

                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 22)

                // Нижнее поле ввода внутри карточки
                inputRow
            }
        }
    }

    private var emptyStateRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundStyle(Palette.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Ассистент готов к работе")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text("Задайте вопрос в поле ниже или нажмите «Запустить» в карточке быстрого анализа выше.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var messagesStreamView: some View {
        VStack(spacing: 12) {
            ForEach(chat.messages) { msg in
                messageRow(msg)
            }

            if chat.isGenerating {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Анализирую и формирую ответ…")
                        .font(.system(size: 12.5))
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
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private func messageRow(_ msg: ChatMessage) -> some View {
        let isUser = msg.role == .user

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isUser ? "person.crop.circle" : "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isUser ? Palette.textTertiary : Palette.accent)

                Text(isUser ? "Вы" : "Intact ИИ")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isUser ? Palette.textSecondary : Palette.accent)

                if !msg.contextBadges.isEmpty {
                    ForEach(msg.contextBadges, id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Palette.dropdownBg))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }

                Spacer()

                Text(timeString(from: msg.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)

                if !isUser {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(msg.content, forType: .string)
                        copiedMessageID = msg.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedMessageID == msg.id { copiedMessageID = nil }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: copiedMessageID == msg.id ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            Text(copiedMessageID == msg.id ? "Скопировано" : "Копировать")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(msg.content)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isUser ? Palette.accent.opacity(0.08) : Palette.dropdownBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isUser ? Palette.accent.opacity(0.2) : Palette.hairline, lineWidth: 1)
                        )
                )
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Спросите что-нибудь или сформулируйте задачу…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.dropdownBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 1)
                        )
                )
                .onSubmit {
                    sendMessage()
                }

            PillButton(title: "Отправить", symbol: "arrow.up") {
                sendMessage()
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isGenerating)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        chat.send(prompt: text)
    }

    private func contextBinding(for source: AIContextSource) -> Binding<Bool> {
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

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
