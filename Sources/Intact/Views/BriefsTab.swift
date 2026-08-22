import SwiftUI
import AppKit

/// Раздел «Брифы»: собрать сводку, посмотреть собранные раньше, настроить
/// расписание.
///
/// Раньше здесь были три кнопки, каждая из которых открывала новую ветку чата
/// и там растворялась, плюс настройки Apple Notes и Reminders — то есть две
/// разные вещи в одном месте. Настройки интеграций уехали в «Настройки»,
/// а бриф стал объектом, который лежит на диске и переживает перезапуск.
struct BriefsTab: View {
    @ObservedObject var settings: AppSettings
    var onOpenSection: ((SettingsSection) -> Void)? = nil

    @ObservedObject private var service = BriefService.shared
    @State private var expanded: Set<UUID> = []
    @State private var exportError: String? = nil

    var body: some View {
        SettingsPage(title: "Брифы") {

            collectCard
            scheduleCard

            if let err = service.errorInfo {
                Card(header: nil) {
                    Row(title: "Не удалось собрать", subtitle: err.message, first: true) {
                        if let label = err.actionLabel, let section = err.section {
                            PillButton(title: label, icon: .settingsPage) { onOpenSection?(section) }
                        }
                    }
                }
            }

            if service.generating != nil {
                draftCard
            }

            if service.briefs.isEmpty {
                emptyState
            } else {
                briefsList
            }
        }
    }

    // MARK: - Собрать

    private var collectCard: some View {
        Card(header: "СОБРАТЬ") {
            ForEach(Array(BriefKind.allCases.enumerated()), id: \.element.id) { index, kind in
                Row(title: kind.title, subtitle: kind.subtitle, first: index == 0) {
                    if service.generating == kind {
                        HStack(spacing: 8) {
                            ThinkingDots(size: 14, tone: .process)
                            PillButton(title: "Стоп", icon: .stop) { service.cancel() }
                        }
                    } else {
                        PillButton(title: "Собрать", icon: kind.icon) {
                            service.generate(kind)
                        }
                        .opacity(service.generating == nil ? 1 : 0.4)
                        .disabled(service.generating != nil)
                    }
                }
            }
            Row(title: "Модель", subtitle: "Брифы собираются той же моделью, что и чат") {
                AIModelPicker(role: .chat,
                              onOpenSettings: { onOpenSection?(.settings) },
                              onOpenModels: { onOpenSection?(.models) })
            }
        }
    }

    // MARK: - Расписание

    private var scheduleCard: some View {
        Card(header: "РАСПИСАНИЕ") {
            Row(title: "Собирать автоматически",
                subtitle: settings.briefScheduleEnabled
                    ? "Каждый день в \(timeText), если приложение запущено"
                    : "Раз в день, без напоминаний вручную",
                first: true) {
                Toggle("", isOn: $settings.briefScheduleEnabled)
                    .toggleStyle(WisprToggleStyle())
            }
            if settings.briefScheduleEnabled {
                Row(title: "Что собирать") {
                    WisprDropdown(selection: $settings.briefScheduleKind,
                                  options: BriefKind.allCases) { kind in
                        Text(kind.title)
                    }
                }
                Row(title: "Во сколько",
                    subtitle: "Если в это время Mac спал, бриф соберётся при первом пробуждении") {
                    HStack(spacing: 6) {
                        WisprDropdown(selection: $settings.briefScheduleHour,
                                      options: Array(0...23)) { hour in
                            Text(String(format: "%02d", hour))
                        }
                        Text(":").foregroundStyle(Palette.textTertiary)
                        WisprDropdown(selection: $settings.briefScheduleMinute,
                                      options: [0, 15, 30, 45]) { minute in
                            Text(String(format: "%02d", minute))
                        }
                    }
                }
            }
        }
    }

    private var timeText: String {
        String(format: "%02d:%02d", settings.briefScheduleHour, settings.briefScheduleMinute)
    }

    // MARK: - Идёт сборка

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ThinkingDots(size: 16, tone: .process)
                Text("Собираю \(service.generating?.title.lowercased() ?? "бриф")…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
            }
            if !service.draft.isEmpty {
                MarkdownMessage(text: service.draft)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        )
    }

    // MARK: - Пусто

    private var emptyState: some View {
        VStack(spacing: 12) {
            IconTile(kind: .briefs, tone: .muted, side: 52)
            Text("Брифов пока нет")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
            Text("Соберите первый — он останется здесь и переживёт перезапуск")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    // MARK: - Список

    private var briefsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("СОБРАННЫЕ")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.leading, 4)
                Spacer()
                if let err = exportError {
                    Text(err)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.iconDanger)
                }
                Button {
                    service.clearAll()
                } label: {
                    HStack(spacing: 5) {
                        IntactIcon(kind: .clearAll, size: 12)
                        Text("Удалить все").font(.system(size: 12))
                    }
                    .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                ForEach(Array(service.briefs.enumerated()), id: \.element.id) { index, brief in
                    BriefRow(brief: brief,
                             first: index == 0,
                             isExpanded: expanded.contains(brief.id),
                             onToggle: {
                                 if expanded.contains(brief.id) { expanded.remove(brief.id) }
                                 else { expanded.insert(brief.id) }
                             },
                             onExport: { export(brief) },
                             onSaveToNotes: { saveToNotes(brief) },
                             onDelete: { service.delete(brief.id) })
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
            )
        }
    }

    private func export(_ brief: Brief) {
        let text = "# \(brief.title)\n\n_\(brief.modelLabel) · \(brief.badges.joined(separator: ", "))_\n\n\(brief.text)\n"
        switch Exporter.save(text: text, suggestedName: "Intact-бриф-\(Exporter.fileStamp(brief.createdAt))") {
        case .saved(let url):  Exporter.reveal(url); exportError = nil
        case .cancelled:       break
        case .failed(let msg): exportError = msg
        }
    }

    /// Бриф в Apple Notes — там же, где живут остальные заметки из голоса.
    private func saveToNotes(_ brief: Brief) {
        AppleNotesService.createNote(text: "\(brief.title)\n\n\(brief.text)",
                                     folderName: settings.voiceNotesFolder)
    }
}

/// Строка списка брифов: свёрнутая — заголовок и первые строки,
/// развёрнутая — весь текст с разметкой.
private struct BriefRow: View {
    let brief: Brief
    let first: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onExport: () -> Void
    let onSaveToNotes: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 22)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    IntactIcon(kind: brief.kind.icon, size: 16)
                        .foregroundStyle(Palette.accent)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(brief.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Palette.textPrimary)
                            if brief.automatic {
                                Text("по расписанию")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Palette.textTertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Palette.pill))
                            }
                        }
                        if !isExpanded {
                            Text(brief.preview)
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(2)
                        }
                        Text(([brief.modelLabel] + brief.badges).joined(separator: " · "))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.textTertiary)
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        if hovering || isExpanded {
                            PillButton(title: copied ? "Скопировано" : "Копировать",
                                       icon: copied ? .copied : .copy,
                                       tone: copied ? .success : nil) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(brief.text, forType: .string)
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                            }
                            PillButton(title: "В заметки", icon: .briefs) { onSaveToNotes() }
                            PillButton(title: "Файл", icon: .export) { onExport() }
                            PillButton(title: "Удалить", icon: .clearAll, tone: .danger) { onDelete() }
                        }
                        Button(action: onToggle) {
                            IntactIcon(kind: isExpanded ? .chevronUp : .chevronDown, size: 11)
                                .foregroundStyle(Palette.textTertiary)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isExpanded {
                    MarkdownMessage(text: brief.text)
                        .padding(.leading, 28)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 15)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { hovering = $0 }
    }
}
