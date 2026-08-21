import SwiftUI
import AppKit

/// Домашний экран Intact — три столпа + активность за сегодня + последние записи.
struct HomeTab: View {
    @ObservedObject var settings: AppSettings
    var onOpenSection: (SettingsSection) -> Void

    @ObservedObject private var controller = DictationController.shared
    @ObservedObject private var history = History.shared
    @ObservedObject private var chat = AIChatService.shared
    @ObservedObject private var models = ModelManager.shared

    private var todayEntries: [HistoryEntry] {
        let cal = Calendar.current
        return history.entries.filter { cal.isDateInToday($0.date) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Заголовок ───────────────────────────────────────────────
            ContentColumn(maxWidth: Layout.wide) {
                Text("Intact")
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.top, 46)
            .padding(.bottom, 24)

            // ── Прокручиваемое тело ──────────────────────────────────────
            ScrollView {
                ContentColumn(maxWidth: Layout.wide) {
                  VStack(alignment: .leading, spacing: 28) {

                    // ── Три карточки-кита ────────────────────────────────
                    HStack(alignment: .top, spacing: 14) {
                        featureCard(
                            icon: .voice,
                            title: "Голос",
                            description: "Удержи \(settings.triggerKey.symbol) и говори — текст появится там, где курсор",
                            status: voiceStatus,
                            statusColor: voiceStatusColor,
                            action: { onOpenSection(.voice) },
                            actionLabel: "Настроить"
                        )
                        featureCard(
                            icon: .aiStar,
                            title: "ИИ-Ассистент",
                            description: "Задай вопрос, проанализируй диктовки, получи сводку за день",
                            status: aiStatus,
                            statusColor: aiStatusColor,
                            action: { onOpenSection(.chat) },
                            actionLabel: "Открыть чат"
                        )
                        featureCard(
                            icon: .briefs,
                            title: "Брифы и заметки",
                            description: "Сводки, задачи, Apple Notes и Reminders прямо из голоса",
                            status: briefsStatus,
                            statusColor: briefsStatusColor,
                            action: { onOpenSection(.briefs) },
                            actionLabel: "Открыть"
                        )
                    }

                    // ── Статус сегодня ───────────────────────────────────
                    todayStatsBar

                    // ── Последние записи ─────────────────────────────────
                    if !history.entries.isEmpty {
                        recentEntriesSection
                    } else {
                        emptyHistoryBanner
                    }
                  }
                }
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.page)
    }

    // MARK: - Feature Card

    private func featureCard(
        icon: IntactIconKind,
        title: String,
        description: String,
        status: String,
        statusColor: Color,
        action: @escaping () -> Void,
        actionLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            IconTile(kind: icon, tone: .active, side: 48)

            // Текст
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Статус + кнопка
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(status)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                }
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7.5)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Palette.accent.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(Palette.accent.opacity(0.22), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 204, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        )
    }

    // MARK: - Stats Bar

    private var todayStatsBar: some View {
        HStack(spacing: 0) {
            statItem(label: "диктовок сегодня") { statNumber("\(todayEntries.count)") }
            divider()
            statItem(label: "сообщений ИИ") { statNumber("\(chat.messages.count)") }
            divider()
            statItem(label: "статус движка") {
                HStack(spacing: 7) {
                    Circle()
                        .fill(models.hasAnyModelInstalled ? Palette.iconSuccess : Palette.iconWarning)
                        .frame(width: 8, height: 8)
                    Text(models.hasAnyModelInstalled ? "Готов" : "Нет модели")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        )
    }

    /// Фиксированная высота строки значения выравнивает подписи между собой,
    /// хотя число набрано крупно, а статус — обычным текстом.
    private func statItem<Value: View>(label: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            value()
                .frame(height: 26, alignment: .leading)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 18)
    }

    private func statNumber(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.textPrimary)
    }

    private func divider() -> some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(width: 1, height: 36)
    }

    // MARK: - Recent Entries

    private var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ПОСЛЕДНИЕ ЗАПИСИ")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .kerning(0.8)

            VStack(spacing: 0) {
                ForEach(history.entries.prefix(6)) { entry in
                    RecentEntryRow(entry: entry,
                                   time: timeString(from: entry.date),
                                   isLast: history.entries.prefix(6).last?.id == entry.id)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
            )

            Button {
                onOpenSection(.history)
            } label: {
                HStack(spacing: 5) {
                    Text("Вся история")
                        .font(.system(size: 13, weight: .medium))
                    IntactIcon(kind: .chevronRight, size: 11, weight: .medium)
                }
                .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyHistoryBanner: some View {
        HStack(spacing: 12) {
            SidebarIntactIcon(kind: .voice, selected: false, size: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text("Начни диктовку")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text("Удержи \(settings.triggerKey.symbol) и скажи что-нибудь — здесь появятся твои записи")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        )
    }

    // MARK: - Status helpers

    private var voiceStatus: String {
        if !models.hasAnyModelInstalled { return "Нет модели Whisper" }
        switch controller.state {
        case .idle:         return "Готов к диктовке"
        case .recording:    return "Запись…"
        case .transcribing: return "Распознаётся…"
        case .processingAI: return "ИИ обрабатывает…"
        }
    }

    private var voiceStatusColor: Color {
        if !models.hasAnyModelInstalled { return Palette.iconWarning }
        return controller.state == .idle ? Palette.iconSuccess : Palette.accent
    }

    private var aiStatus: String {
        switch settings.aiProviderKind {
        case .none: return "ИИ не настроен"
        case .local: return LocalAIProvider.shared.isReady ? "Локальная модель" : "Загружается…"
        case .cloud: return "Облако · \(settings.aiCloudModel)"
        }
    }

    private var aiStatusColor: Color {
        switch settings.aiProviderKind {
        case .none: return Palette.iconWarning
        case .local: return LocalAIProvider.shared.isReady ? Palette.iconSuccess : Palette.iconWarning
        case .cloud: return Palette.iconSuccess
        }
    }

    private var briefsStatus: String {
        switch (settings.enableVoiceNotes, settings.enableVoiceReminders) {
        case (true, true):   return "Заметки и напоминания включены"
        case (true, false):  return "Заметки включены"
        case (false, true):  return "Напоминания включены"
        case (false, false): return "Интеграции выключены"
        }
    }

    private var briefsStatusColor: Color {
        settings.enableVoiceNotes || settings.enableVoiceReminders
            ? Palette.iconSuccess
            : Palette.iconMuted
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

/// Строка «последней записи» на Главной.
///
/// Вынесена в отдельный тип ради собственного состояния: кнопка копирования
/// проявляется по наведению и подтверждает результат — ровно так же, как
/// такая же кнопка в разделе «История».
private struct RecentEntryRow: View {
    let entry: HistoryEntry
    let time: String
    let isLast: Bool

    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Text(time)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 42, alignment: .trailing)
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1, height: 22)
            Text(entry.text)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)

            Button(action: copy) {
                HStack(spacing: 5) {
                    IntactIcon(kind: copied ? .copied : .copy, size: 12)
                    if copied {
                        Text("Скопировано")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                }
                .foregroundStyle(copied ? Palette.accent : Palette.iconIdle)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(copied ? Palette.accent.opacity(0.10) : Palette.pill)
                )
            }
            .buttonStyle(.plain)
            .help("Скопировать текст записи")
            .opacity(hovering || copied ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10.5)
        .contentShape(Rectangle())
        .background(hovering ? Palette.hover : Color.clear)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
