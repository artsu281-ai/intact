import SwiftUI
import AppKit

/// Вкладка «Брифы и заметки» — быстрый анализ + Apple Notes + Apple Reminders + форматирование.
struct BriefsTab: View {
    @ObservedObject var settings: AppSettings
    var onOpenSection: ((SettingsSection) -> Void)? = nil
    @ObservedObject private var chat = AIChatService.shared

    var body: some View {
        SettingsPage(title: "Брифы и заметки") {

            // ── Быстрый анализ ──────────────────────────────────────────
            Card(header: "БЫСТРЫЙ АНАЛИЗ") {
                Row(title: "Сводка за сегодня",
                    subtitle: "ИИ анализирует все диктовки за сегодня и даёт краткое резюме",
                    first: true) {
                    quickChip(iconKind: .quickSummary, label: "Запустить") {
                        chat.analyzeTodayDictations()
                        onOpenSection?(.chat)
                    }
                }
                Row(title: "Извлечь задачи и TODO",
                    subtitle: "Находит действия, которые нужно сделать, из голосовых записей") {
                    quickChip(iconKind: .quickTasks, label: "Извлечь") {
                        chat.extractTasksFromHistoryAndNotes()
                        onOpenSection?(.chat)
                    }
                }
                Row(title: "Сводка Apple Notes",
                    subtitle: "Краткое резюме всех заметок из папки Intact в Apple Notes") {
                    quickChip(iconKind: .quickNotes, label: "Сводка") {
                        chat.summarizeNotes()
                        onOpenSection?(.chat)
                    }
                }
                if chat.isGenerating {
                    Row(title: "Формирование ответа…") {
                        Button {
                            onOpenSection?(.chat)
                        } label: {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.mini)
                                Text("Смотреть в чате →")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Palette.accent)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Palette.accent.opacity(0.10))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let err = chat.errorMessage {
                    Row(title: "Ошибка") {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: 320, alignment: .trailing)
                    }
                }
            }

            // ── Apple Notes ─────────────────────────────────────────────
            Card(header: "APPLE NOTES") {
                Row(title: "Создавать заметки по командам",
                    subtitle: "«Делаем заметку…», «Заметка…», «Создай заметку…» — сохраняет текст в Apple Notes без вставки",
                    first: true) {
                    Toggle("", isOn: $settings.enableVoiceNotes)
                        .toggleStyle(WisprToggleStyle())
                }
                if settings.enableVoiceNotes {
                    Row(title: "Папка в Заметках",
                        subtitle: "Папка в приложении Заметки (по умолчанию «Intact»)") {
                        TextField("Intact", text: $settings.voiceNotesFolder)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Palette.dropdownBg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Palette.hairline, lineWidth: 1)
                                    )
                            )
                            .frame(width: 130)
                    }
                }
            }

            // ── Apple Reminders ──────────────────────────────────────────
            Card(header: "APPLE REMINDERS") {
                Row(title: "Создавать напоминания по командам",
                    subtitle: "«Напомни завтра в 15:00…», «Поставь задачу…» — создаёт напоминание в Apple Reminders",
                    first: true) {
                    Toggle("", isOn: $settings.enableVoiceReminders)
                        .toggleStyle(WisprToggleStyle())
                }
                if settings.enableVoiceReminders {
                    Row(title: "Список напоминаний",
                        subtitle: "Оставьте пустым для списка по умолчанию") {
                        TextField("По умолчанию", text: $settings.voiceRemindersList)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Palette.dropdownBg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Palette.hairline, lineWidth: 1)
                                    )
                            )
                            .frame(width: 140)
                    }
                }
            }

            // ── Форматирование ───────────────────────────────────────────
            Card(header: "ФОРМАТИРОВАНИЕ ТЕКСТА") {
                Row(title: "Убирать точку в конце",
                    subtitle: "Удалять завершающую точку при коротких фразах",
                    first: true) {
                    Toggle("", isOn: $settings.trimTrailingPeriod)
                        .toggleStyle(WisprToggleStyle())
                }
                Row(title: "Добавлять пробел после текста",
                    subtitle: "Автоматически ставить пробел после вставленного фрагмента") {
                    Toggle("", isOn: $settings.appendSpace)
                        .toggleStyle(WisprToggleStyle())
                }
                Row(title: "Сохранять историю записей",
                    subtitle: "Позволяет скопировать продиктованный текст из истории позже") {
                    Toggle("", isOn: $settings.keepHistory)
                        .toggleStyle(WisprToggleStyle())
                }
                Row(title: "Таймаут карточки копирования",
                    subtitle: "Через сколько секунд скрывать окно, если поле ввода не выбрано") {
                    WisprDropdown(selection: $settings.copyDismissTimeoutSeconds,
                                  options: [3, 5, 10, 15, 30]) { sec in
                        Text("\(sec) сек\(sec == 5 ? " (по умолч.)" : "")")
                    }
                }
            }
        }
    }

    private func quickChip(iconKind: IntactIconKind, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                IntactIcon(kind: iconKind, size: 14)
                    .foregroundStyle(Palette.accent)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.dropdownBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(chat.isGenerating)
        .opacity(chat.isGenerating ? 0.5 : 1)
    }
}
