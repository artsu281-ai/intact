import SwiftUI
import AppKit

/// Единая вкладка «Настройки» — оформление (тема, иконка),
/// система и звук (автозапуск, приглушение звука, пауза музыки), провайдер ИИ.
struct SettingsTab: View {
    // Подписка на тему: см. `ThemeReader` в Theme.swift. Без неё вид
    // останется в старых цветах при смене темы. Не удалять как неиспользуемое.
    @ThemeReader var themeStamp

    @ObservedObject var settings: AppSettings
    var onOpenModels: (() -> Void)? = nil

    var body: some View {
        SettingsPage(title: T("Настройки", "Settings")) {

            // ── Оформление ──────────────────────────────────────────────
            Card(header: T("ОФОРМЛЕНИЕ", "APPEARANCE")) {
                Row(title: T("Плавающий индикатор записи", "Floating recording indicator"),
                    subtitle: T("Показывать индикатор поверх всех окон во время речи", "Show the indicator above all windows while speaking"),
                    first: true) {
                    Toggle("", isOn: $settings.showIndicator)
                        .toggleStyle(WisprToggleStyle())
                }
            }

            // Выбор темы
            themeSelectionCard

            // Выбор иконки приложения
            appIconSelectionCard

            // ── Система и звук ──────────────────────────────────────────
            Card(header: T("СИСТЕМА И ЗВУК", "SYSTEM AND SOUND")) {
                Row(title: T("Запускать при входе в систему", "Launch at login"),
                    subtitle: T("Автоматический запуск Intact вместе с macOS", "Start Intact together with macOS"),
                    first: true) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: T("Приглушать звук системы", "Mute system audio"),
                    subtitle: T("Временно выключает звук динамиков на время речи", "Temporarily mutes speakers while you speak")) {
                    Toggle("", isOn: $settings.muteAudioWhileDictating)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: T("Приостанавливать музыку и видео", "Pause music and video"),
                    subtitle: T("Ставит на паузу Apple Music, Spotify и другие плееры на время речи", "Pauses Apple Music, Spotify and other players while you speak")) {
                    Toggle("", isOn: $settings.pauseMediaWhileDictating)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: T("Звуковые сигналы", "Sound cues"),
                    subtitle: T("Короткие звуки при начале, окончании и ошибке записи", "Short sounds at the start, end and on error")) {
                    Toggle("", isOn: $settings.playSounds)
                        .toggleStyle(WisprToggleStyle())
                }
            }

            // ── ИИ и провайдеры ──────────────────────────────────────────
            Card(header: T("ИИ И ПРОВАЙДЕРЫ", "AI AND PROVIDERS")) {
                Row(title: T("Провайдер ИИ", "AI provider"),
                    subtitle: T("Используется для умного причёсывания текста и ответов на вопросы", "Used for smart text cleanup and AI answers"),
                    first: true) {
                    WisprDropdown(selection: $settings.aiProviderKind,
                                  options: AIProviderKind.allCases) { kind in
                        Text(kind.title)
                    }
                }

                if settings.aiProviderKind == .local {
                    Row(title: T("Локальные модели GGUF", "Local GGUF models"),
                        subtitle: T("Загрузка и управление офлайн-моделями llama-server", "Downloading and managing offline llama-server models")) {
                        PillButton(title: T("Хаб моделей", "Model hub"), icon: .models) {
                            onOpenModels?()
                        }
                    }
                }

                Row(title: T("Умное причёсывание диктовки", "Smart dictation cleanup"),
                    subtitle: T("Убирает слова-паразиты («э-э», «ну») и форматирует текст", "Removes filler words (“uh”, “well”) and formats the text")) {
                    Toggle("", isOn: $settings.enableAICleanup)
                        .toggleStyle(WisprToggleStyle())
                        .disabled(settings.aiProviderKind == .none)
                }
            }

            // ── Модель по разделам ───────────────────────────────────────
            Card(header: T("МОДЕЛЬ ПО РАЗДЕЛАМ", "MODEL PER SECTION")) {
                ForEach(Array(AIRole.allCases.enumerated()), id: \.element.id) { index, role in
                    AIRoleRow(role: role, first: index == 0,
                              onOpenSettings: {},
                              onOpenModels: { onOpenModels?() })
                }

                Row(title: T("Рассуждение локальной модели", "Local model reasoning"),
                    subtitle: T("В чате и брифах модель сначала обдумывает ответ. В причёсывании диктовки выключено всегда.", "In chat and briefs the model thinks before answering. Always off in dictation cleanup.")) {
                    Toggle("", isOn: $settings.localThinkingInChat)
                        .toggleStyle(WisprToggleStyle())
                }
            }

            integrationsCard
        }
    }

    // MARK: - Интеграции

    private var integrationsCard: some View {
        Card(header: T("ЗАМЕТКИ И НАПОМИНАНИЯ", "NOTES AND REMINDERS")) {
            Row(title: T("Создавать заметки по командам", "Create notes from voice commands"),
                subtitle: T("«Делаем заметку…», «Заметка…», «Создай заметку…» — сохраняет текст в Apple Notes без вставки", "“Make a note…”, “Note…”, “Create a note…” — saves the text to Apple Notes without inserting it"),
                first: true) {
                Toggle("", isOn: $settings.enableVoiceNotes)
                    .toggleStyle(WisprToggleStyle())
            }
            if settings.enableVoiceNotes {
                Row(title: T("Папка в Заметках", "Notes folder"),
                    subtitle: T("Папка в приложении Заметки (по умолчанию «Intact»)", "Folder in the Notes app (“Intact” by default)")) {
                    compactField(placeholder: "Intact", text: $settings.voiceNotesFolder, width: 130)
                }
            }

            Row(title: T("Создавать напоминания по командам", "Create reminders from voice commands"),
                subtitle: T("«Напомни завтра в 15:00…», «Поставь задачу…» — создаёт напоминание в Apple Reminders", "“Remind me tomorrow at 3pm…”, “Add a task…” — creates a reminder in Apple Reminders")) {
                Toggle("", isOn: $settings.enableVoiceReminders)
                    .toggleStyle(WisprToggleStyle())
            }
            if settings.enableVoiceReminders {
                Row(title: T("Список напоминаний", "Reminders list"),
                    subtitle: T("Оставьте пустым для списка по умолчанию", "Leave empty for the default list")) {
                    compactField(placeholder: T("По умолчанию", "Default"), text: $settings.voiceRemindersList, width: 140)
                }
            }
        }
    }

    private func compactField(placeholder: String, text: Binding<String>, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
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
            .frame(width: width)
    }

    // MARK: - Карточка выбора темы

    private var themeSelectionCard: some View {
        Card(header: L10n.appearanceHeaderTheme) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.appearanceThemeDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ThemeCard(
                        theme: .white,
                        title: L10n.themeWhite,
                        subtitle: L10n.themeWhiteSub,
                        accentColor: Color(red: 0.180, green: 0.480, blue: 0.920),
                        bgSample: Color(red: 0.970, green: 0.972, blue: 0.976),
                        cardSample: Color.white,
                        isSelected: settings.appTheme == .white
                    ) {
                        settings.setTheme(.white)
                        settings.applyTheme()
                    }

                    ThemeCard(
                        theme: .terracotta,
                        title: L10n.themeTerracotta,
                        subtitle: L10n.themeTerracottaSub,
                        accentColor: Color(red: 0.780, green: 0.435, blue: 0.318),
                        bgSample: Color(red: 0.980, green: 0.965, blue: 0.941),
                        cardSample: Color(red: 0.996, green: 0.992, blue: 0.984),
                        isSelected: settings.appTheme == .terracotta
                    ) {
                        settings.setTheme(.terracotta)
                        settings.applyTheme()
                    }

                    ThemeCard(
                        theme: .dark,
                        title: L10n.themeDark,
                        subtitle: L10n.themeDarkSub,
                        accentColor: Color(red: 0.880, green: 0.650, blue: 0.520),
                        bgSample: Color(red: 0.086, green: 0.082, blue: 0.078),
                        cardSample: Color(red: 0.145, green: 0.141, blue: 0.137),
                        isSelected: settings.appTheme == .dark
                    ) {
                        settings.setTheme(.dark)
                        settings.applyTheme()
                    }

                    ThemeCard(
                        theme: .system,
                        title: L10n.themeSystem,
                        subtitle: L10n.themeSystemSub,
                        accentColor: Color(red: 0.50, green: 0.50, blue: 0.50),
                        bgSample: Color(red: 0.935, green: 0.940, blue: 0.945),
                        cardSample: Color.white,
                        isSelected: settings.appTheme == .system
                    ) {
                        settings.setTheme(.system)
                        settings.applyTheme()
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Карточка выбора иконки приложения

    private var appIconSelectionCard: some View {
        Card(header: L10n.appearanceHeaderDock) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.appearanceDockSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 14) {
                    AppIconChoiceCard(
                        style: .light,
                        title: L10n.iconStyleLight,
                        subtitle: L10n.iconStyleLightSub,
                        imageName: "AppIcon-Light",
                        isSelected: settings.appIconStyle == .light
                    ) {
                        settings.appIconStyle = .light
                    }

                    AppIconChoiceCard(
                        style: .black,
                        title: L10n.iconStyleBlack,
                        subtitle: L10n.iconStyleBlackSub,
                        imageName: "AppIcon-Black",
                        isSelected: settings.appIconStyle == .black
                    ) {
                        settings.appIconStyle = .black
                    }

                    AppIconChoiceCard(
                        style: .auto,
                        title: L10n.iconStyleAuto,
                        subtitle: L10n.iconStyleAutoSub,
                        imageName: settings.isDarkMode ? "AppIcon-Black" : "AppIcon-Light",
                        isSelected: settings.appIconStyle == .auto
                    ) {
                        settings.appIconStyle = .auto
                    }
                }
            }
            .padding(20)
        }
    }
}
