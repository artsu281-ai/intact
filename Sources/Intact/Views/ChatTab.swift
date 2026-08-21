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
        VStack(spacing: 0) {
            // Заголовок страницы
            Text(L10n.tabChat)
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 46)
                .padding(.bottom, 20)

            // ── Sticky-хедер с провайдером и контекстом ─────────────────
            VStack(spacing: 0) {
                stickyProviderHeader
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
            .background(Palette.page)
            .zIndex(10)

            // ── Прокручиваемое тело ──────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Быстрые действия — горизонтальные чипы
                        VStack(alignment: .leading, spacing: 10) {
                            Text("БЫСТРЫЙ АНАЛИЗ")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.textTertiary)
                                .kerning(0.8)
                            quickChipsRow
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 20)

                        // Ошибка
                        if let err = chat.errorMessage {
                            HStack(spacing: 8) {
                                IntactIcon(kind: .warning, size: 13)
                                    .foregroundStyle(.orange)
                                Text(err)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.orange)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.orange.opacity(0.08))
                            )
                            .padding(.horizontal, 40)
                        }

                        // Заголовок диалога
                        if !chat.messages.isEmpty {
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
                            .padding(.horizontal, 40)
                        }

                        // Сообщения или пустое состояние
                        if chat.messages.isEmpty {
                            emptyStateView.padding(.horizontal, 40)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(chat.messages) { msg in
                                    bubbleRow(msg)
                                }
                            }
                            .padding(.horizontal, 40)
                        }

                        // Индикатор генерации
                        if chat.isGenerating {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small)
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
                            .padding(.horizontal, 40)
                            .id("generating")
                        }

                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.bottom, 8)
                }
                .onChange(of: chat.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: chat.isGenerating) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }

            // ── Закреплённый ввод внизу ────────────────────────────────
            VStack(spacing: 0) {
                Rectangle().fill(Palette.hairline).frame(height: 1)
                inputFooter
            }
            .background(Palette.page)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.page)
    }

    // MARK: - Sticky провайдер-хедер

    private var stickyProviderHeader: some View {
        HStack(spacing: 14) {
            // Статус провайдера
            HStack(spacing: 6) {
                Circle()
                    .fill(providerStatusColor)
                    .frame(width: 7, height: 7)
                Text(providerShort)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }

            Rectangle().fill(Palette.hairline).frame(width: 1, height: 14)

            // Контекст
            Menu {
                Toggle("Диктовки за сегодня", isOn: contextBinding(for: .dictationToday))
                Toggle("Все недавние диктовки", isOn: contextBinding(for: .dictationRecent))
                Toggle("Заметки Apple Notes", isOn: contextBinding(for: .appleNotes))
                Toggle("Напоминания Reminders", isOn: contextBinding(for: .appleReminders))
            } label: {
                HStack(spacing: 4) {
                    IntactIcon(kind: .context, size: 12)
                    Text("Контекст: \(chat.selectedContextSources.count)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Palette.pill)
                        .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

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
        .padding(.horizontal, 40)
        .padding(.vertical, 10)
    }

    private var providerStatusColor: Color {
        switch settings.aiProviderKind {
        case .none:  return .orange
        case .local: return LocalAIProvider.shared.isReady ? .green : .orange
        case .cloud: return .green
        }
    }

    private var providerShort: String {
        switch settings.aiProviderKind {
        case .none:  return "ИИ выключен"
        case .local:
            let name = URL(fileURLWithPath: settings.aiLocalModelPath).deletingPathExtension().lastPathComponent
            return name.isEmpty ? "Локальная модель" : name
        case .cloud:
            return "Claude · \(settings.aiCloudModel)"
        }
    }

    // MARK: - Чипы быстрого анализа

    private var quickChipsRow: some View {
        HStack(spacing: 10) {
            quickChip(icon: "⚡️", label: "Сводка за сегодня")  { chat.analyzeTodayDictations() }
            quickChip(icon: "📋", label: "Извлечь задачи")      { chat.extractTasksFromHistoryAndNotes() }
            quickChip(icon: "📝", label: "Сводка Notes")        { chat.summarizeNotes() }
            Spacer()
        }
    }

    private func quickChip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(icon).font(.system(size: 14))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
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
            IntactIcon(kind: .aiStar, size: 24)
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ассистент готов к работе")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text("Задайте вопрос ниже или запустите быстрый анализ выше")
                    .font(.system(size: 12))
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
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }

                    ForEach(msg.contextBadges, id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Palette.pill))
                            .foregroundStyle(Palette.textSecondary)
                    }

                    if isUser {
                        Text("Вы")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }

                    Text(timeString(from: msg.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                }

                // Тело пузыря
                Text(msg.content)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
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
                        HStack(spacing: 3) {
                            IntactIcon(kind: copiedMessageID == msg.id ? .copied : .copy, size: 12)
                            Text(copiedMessageID == msg.id ? "Скопировано" : "Копировать")
                                .font(.system(size: 10))
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
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Спросите что-нибудь или сформулируйте задачу…", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Palette.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 1)
                        )
                )
                .onSubmit { sendMessage() }

            let canSend = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.isGenerating
            Button { sendMessage() } label: {
                IntactIcon(kind: chat.isGenerating ? .stop : .send, size: 14)
                    .foregroundStyle(canSend ? .white : Palette.textTertiary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(canSend ? Palette.accent : Palette.pill)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(.spring(response: 0.22), value: canSend)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

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
                if enabled { chat.selectedContextSources.insert(source) }
                else { chat.selectedContextSources.remove(source) }
            }
        )
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
