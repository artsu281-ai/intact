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
            HStack(alignment: .firstTextBaseline) {
                Text("Intact")
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 40)
            .padding(.top, 46)
            .padding(.bottom, 24)

            // ── Прокручиваемое тело ──────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // ── Три карточки-кита ────────────────────────────────
                    HStack(alignment: .top, spacing: 14) {
                        featureCard(
                            icon: .voice,
                            title: "Голос",
                            description: "Удержи \(settings.triggerKey.symbol) и говори — текст появится там, где курсор",
                            accentColor: Palette.accent,
                            status: voiceStatus,
                            statusColor: voiceStatusColor,
                            action: { onOpenSection(.voice) },
                            actionLabel: "Настроить"
                        )
                        featureCard(
                            icon: .aiStar,
                            title: "ИИ-Ассистент",
                            description: "Задай вопрос, проанализируй диктовки, получи сводку за день",
                            accentColor: .purple,
                            status: aiStatus,
                            statusColor: aiStatusColor,
                            action: { onOpenSection(.chat) },
                            actionLabel: "Открыть чат"
                        )
                        featureCard(
                            icon: .briefs,
                            title: "Брифы и заметки",
                            description: "Сводки, задачи, Apple Notes и Reminders прямо из голоса",
                            accentColor: .teal,
                            status: briefsStatus,
                            statusColor: .teal,
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
                .padding(.horizontal, 40)
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
        accentColor: Color,
        status: String,
        statusColor: Color,
        action: @escaping () -> Void,
        actionLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Иконка
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accentColor.opacity(0.10))
                    .frame(width: 48, height: 48)
                SidebarIntactIcon(kind: icon, selected: true, size: 22)
                    .foregroundStyle(accentColor)
            }

            // Текст
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Статус + кнопка
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                }
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(accentColor.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(accentColor.opacity(0.22), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
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
            statItem(value: "\(todayEntries.count)", label: "диктовок сегодня")
            divider()
            statItem(value: "\(chat.messages.count)", label: "сообщений ИИ")
            divider()
            statItem(value: models.hasAnyModelInstalled ? "Готов" : "Нет модели",
                     label: "статус движка")
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

    private func statItem(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 18)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .kerning(0.8)

            VStack(spacing: 0) {
                ForEach(history.entries.prefix(6)) { entry in
                    recentRow(entry)
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
                Text("Вся история →")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func recentRow(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 12) {
            Text(timeString(from: entry.date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 42, alignment: .trailing)
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1, height: 22)
            Text(entry.text)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
                .frame(maxWidth: .infinity, alignment: .bottom)
                .opacity(history.entries.prefix(6).last?.id == entry.id ? 0 : 1)
        )
    }

    private var emptyHistoryBanner: some View {
        HStack(spacing: 12) {
            SidebarIntactIcon(kind: .voice, selected: false, size: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text("Начни диктовку")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text("Удержи \(settings.triggerKey.symbol) и скажи что-нибудь — здесь появятся твои записи")
                    .font(.system(size: 12))
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
        if !models.hasAnyModelInstalled { return .orange }
        return controller.state == .idle ? .green : Palette.accent
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
        case .none: return .orange
        case .local: return LocalAIProvider.shared.isReady ? .green : .orange
        case .cloud: return .green
        }
    }

    private var briefsStatus: String {
        var parts: [String] = []
        if settings.enableVoiceNotes { parts.append("Заметки ✓") }
        if settings.enableVoiceReminders { parts.append("Напоминания ✓") }
        return parts.isEmpty ? "Интеграции выключены" : parts.joined(separator: " · ")
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
