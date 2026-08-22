import SwiftUI
import AppKit

/// Главная — это «сегодня».
///
/// Раньше здесь были три карточки-ярлыка на разделы, которые и так есть
/// в боковике, и три счётчика, один из которых считал сообщения активной
/// ветки чата. Вернуться сюда было незачем. Теперь это лента дня: что
/// наговорено, что из этого стало заметкой или напоминанием, и одна
/// кнопка — собрать из всего этого бриф.
struct HomeTab: View {
    @ObservedObject var settings: AppSettings
    var onOpenSection: (SettingsSection) -> Void

    @ObservedObject private var history = History.shared
    @ObservedObject private var models = ModelManager.shared
    @ObservedObject private var briefs = BriefService.shared
    @ObservedObject private var usage = UsageTracker.shared

    private var todayEntries: [HistoryEntry] {
        history.entries.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var todayBrief: Brief? {
        briefs.briefs.first { Calendar.current.isDateInToday($0.createdAt) && $0.kind == .day }
    }

    var body: some View {
        VStack(spacing: 0) {
            ContentColumn(maxWidth: Layout.wide) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Intact")
                        .font(.system(size: 32, weight: .regular, design: .serif))
                        .foregroundStyle(Palette.textPrimary)
                    Text(todayText)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.top, 46)
            .padding(.bottom, 22)

            ScrollView {
                ContentColumn(maxWidth: Layout.wide) {
                    VStack(alignment: .leading, spacing: 22) {
                        // Статус — только когда он ненормальный. Зелёная плашка
                        // «всё хорошо» на каждом открытии не несёт информации.
                        if let attention { attentionBanner(attention) }

                        dayHeaderRow

                        if todayEntries.isEmpty {
                            emptyDayBanner
                        } else {
                            dayTimeline
                        }

                        if let brief = todayBrief {
                            briefCard(brief)
                        }

                        shortcutsRow
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.page)
    }

    private var todayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: Date()).capitalizedFirst
    }

    // MARK: - Требует внимания

    private struct Attention {
        let text: String
        let action: String
        let section: SettingsSection
    }

    private var attention: Attention? {
        if !models.hasAnyModelInstalled {
            return Attention(text: "Модель распознавания не установлена — диктовка не заработает",
                             action: "Скачать модель", section: .models)
        }
        if let missing = Permissions.missingDescription {
            return Attention(text: missing, action: "Выдать доступ", section: .voice)
        }
        if settings.enableAICleanup, !AIRouter.shared.isReady(for: .cleanup) {
            return Attention(text: "Причёсывание включено, но модель для него не готова",
                             action: "Выбрать модель", section: .voice)
        }
        return nil
    }

    private func attentionBanner(_ item: Attention) -> some View {
        HStack(spacing: 12) {
            IntactIcon(kind: .warning, size: 17)
                .foregroundStyle(Palette.iconWarning)
            Text(item.text)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 12)
            PillButton(title: item.action, icon: .chevronRight) { onOpenSection(item.section) }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.iconWarning.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.iconWarning.opacity(0.28), lineWidth: 1)
                )
        )
    }

    // MARK: - Шапка дня

    private var dayHeaderRow: some View {
        HStack(alignment: .center, spacing: 18) {
            stat(value: "\(todayEntries.count)", label: "записей")
            divider()
            stat(value: spokenText, label: "речи")
            if usage.todayCost > 0 {
                divider()
                stat(value: UsageTracker.money(usage.todayCost), label: "облако")
            }

            Spacer()

            if briefs.generating == .day {
                HStack(spacing: 8) {
                    ThinkingDots(size: 15, tone: .process)
                    Text("Собираю бриф…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                Button {
                    briefs.generate(.day)
                    onOpenSection(.briefs)
                } label: {
                    HStack(spacing: 7) {
                        IntactIcon(kind: .quickSummary, size: 14)
                        Text(todayBrief == nil ? "Собрать бриф за день" : "Пересобрать бриф")
                            .font(.system(size: 13.5, weight: .medium))
                    }
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.accent.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Palette.accent.opacity(0.22), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(todayEntries.isEmpty || briefs.generating != nil)
                .opacity(todayEntries.isEmpty ? 0.45 : 1)
            }
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

    /// Сколько сегодня наговорено — величина, которую больше нигде не видно,
    /// а она честнее числа записей: одна запись бывает и на пять секунд,
    /// и на пять минут.
    private var spokenText: String {
        let total = todayEntries.reduce(0) { $0 + $1.seconds }
        if total < 60 { return "\(Int(total)) с" }
        return "\(Int(total / 60)) мин"
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private func divider() -> some View {
        Rectangle().fill(Palette.hairline).frame(width: 1, height: 32)
    }

    // MARK: - Лента дня

    private var dayTimeline: some View {
        let shown = Array(todayEntries.prefix(12))
        return VStack(alignment: .leading, spacing: 10) {
            Text("СЕГОДНЯ")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .kerning(0.8)

            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    DayEntryRow(entry: entry,
                                time: timeString(from: entry.date),
                                isLast: index == shown.count - 1)
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

            if todayEntries.count > shown.count {
                Button { onOpenSection(.history) } label: {
                    HStack(spacing: 5) {
                        Text("Ещё \(todayEntries.count - shown.count) за сегодня — вся история")
                            .font(.system(size: 13, weight: .medium))
                        IntactIcon(kind: .chevronRight, size: 11, weight: .medium)
                    }
                    .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyDayBanner: some View {
        HStack(spacing: 12) {
            SidebarIntactIcon(kind: .voice, selected: false, size: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text("Сегодня ещё тихо")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Text("Удержи \(settings.triggerKey.symbol) и скажи что-нибудь — записи появятся здесь")
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

    // MARK: - Бриф дня

    private func briefCard(_ brief: Brief) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IntactIcon(kind: .quickSummary, size: 14)
                    .foregroundStyle(Palette.accent)
                Text(brief.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button { onOpenSection(.briefs) } label: {
                    Text("Все брифы")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }
            MarkdownMessage(text: brief.text)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        )
    }

    // MARK: - Куда дальше

    /// Компактные ссылки вместо трёх больших карточек: разделы и так есть
    /// в боковике, дублировать их плитками во весь экран незачем.
    private var shortcutsRow: some View {
        HStack(spacing: 10) {
            shortcut(icon: .chat, title: "Чат с ИИ", subtitle: modelSubtitle) { onOpenSection(.chat) }
            shortcut(icon: .aiStar, title: "Спросите ИИ",
                     subtitle: settings.enableAIHotkey ? settings.aiTriggerKey.symbol : "выключено") { onOpenSection(.askAI) }
            shortcut(icon: .voice, title: "Диктовка",
                     subtitle: settings.triggerKey.symbol) { onOpenSection(.voice) }
        }
    }

    private var modelSubtitle: String {
        AIModelCatalog.title(for: AIModelCatalog.resolved(for: .chat))
    }

    private func shortcut(icon: IntactIconKind, title: String, subtitle: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                IconTile(kind: icon, tone: .idle, side: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

extension String {
    /// «Суббота, 22 августа» — DateFormatter отдаёт день недели со строчной.
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

/// Строка ленты дня. Отдельный тип ради собственного состояния: кнопка
/// копирования проявляется по наведению и подтверждает результат.
private struct DayEntryRow: View {
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

            IntactIcon(kind: entry.kind.icon, size: 13)
                .foregroundStyle(entry.kind == .dictation ? Palette.iconMuted : Palette.accent)
                .frame(width: 16)
                .help(entry.kind.title)

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
