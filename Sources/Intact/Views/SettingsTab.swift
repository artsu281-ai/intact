import SwiftUI
import AppKit

/// Единая вкладка «Настройки» — оформление (тема, иконка, язык интерфейса),
/// система и звук (автозапуск, Dock, приглушение звука, пауза музыки), провайдер ИИ.
struct SettingsTab: View {
    @ObservedObject var settings: AppSettings
    var onOpenModels: (() -> Void)? = nil

    @ObservedObject private var usage = UsageTracker.shared
    @State private var apiKeyText: String = ""
    @State private var apiKeySaved = false
    @State private var isSelfTesting = false
    @State private var selfTestStage = ""
    @State private var selfTestResults: [CloudCheck] = []

    var body: some View {
        SettingsPage(title: T("Настройки", "Settings")) {

            // ── Оформление ──────────────────────────────────────────────
            Card(header: T("ОФОРМЛЕНИЕ", "APPEARANCE")) {
                // Переключателя языка здесь больше нет. Из ~700 строк
                // интерфейса через L10n проходили 85 — английский вариант
                // давал русское окно с десятком английских вкраплений,
                // то есть был хуже, чем честный русский. Сам L10n остался
                // в коде: если английский когда-нибудь доведут до конца,
                // переключатель вернётся сюда же.
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
                        .onChange(of: settings.launchAtLogin) { _, new in LoginItem.set(enabled: new) }
                }

                Row(title: T("Значок в Dock", "Dock icon"),
                    subtitle: T("Отображать приложение в панели Dock", "Show the app in the Dock")) {
                    Toggle("", isOn: $settings.showDockIcon)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: T("Заглушать системный звук во время речи", "Mute system sound while speaking"),
                    subtitle: T("Отключает вывод динамиков и наушников на время записи", "Silences speakers and headphones for the duration of the recording")) {
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
                    subtitle: T("Используется для умного причёсывания текста и чата", "Used for smart text cleanup and chat"),
                    first: true) {
                    WisprDropdown(selection: $settings.aiProviderKind,
                                  options: AIProviderKind.allCases) { kind in
                        Text(kind.title)
                    }
                }

                if settings.aiProviderKind == .cloud {
                    Row(title: T("API-ключ Anthropic", "Anthropic API key"),
                        subtitle: T("Ключ сохраняется в защищённом хранилище Keychain", "The key is stored in the Keychain")) {
                        HStack(spacing: 8) {
                            SecureField("sk-ant-api03-...", text: $apiKeyText)
                                .textFieldStyle(.plain)
                                .frame(width: 180)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Palette.dropdownBg)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(Palette.hairline, lineWidth: 1)
                                        )
                                )
                            PillButton(title: apiKeySaved ? T("Сохранено", "Saved") : T("Сохранить", "Save"),
                                       icon: apiKeySaved ? .success : .copied,
                                       tone: apiKeySaved ? .success : nil) {
                                KeychainHelper.set(apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   service: CloudAIProvider.keychainService)
                                apiKeySaved = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { apiKeySaved = false }
                            }
                        }
                    }

                    Row(title: T("Модель Claude", "Claude model"),
                        subtitle: cloudModelSubtitle) {
                        WisprDropdown(selection: $settings.aiCloudModel,
                                      options: AIModelCatalog.cloud.map(\.id)) { id in
                            Text(AIModelCatalog.cloudModel(id: id)?.title ?? id)
                        }
                    }

                    // Ключ есть только у владельца машины, поэтому облачный
                    // путь нельзя проверить заранее. Одна кнопка проверяет
                    // всё сразу: ключ, поток, расширенные поля, поиск и учёт.
                    Row(title: T("Проверить облако", "Check the cloud"),
                        subtitle: selfTestStatus) {
                        if isSelfTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            PillButton(title: T("Запустить проверку", "Run the check"), icon: .refresh) { runSelfTest() }
                        }
                    }

                    ForEach(selfTestResults) { check in
                        Row(title: check.name, subtitle: check.detail) {
                            IntactIcon(kind: check.ok ? .success : .error, size: 16)
                                .foregroundStyle(check.ok ? Palette.iconSuccess : Palette.iconDanger)
                        }
                    }
                }

                if settings.aiProviderKind == .local {
                    Row(title: T("Локальные модели GGUF", "Local GGUF models"),
                        subtitle: T("Загрузка и управление моделями llama-server", "Downloading and managing llama-server models")) {
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
            // Одна модель на всё приложение — это выбор между «умно, но
            // диктовка тормозит» и «быстро, но в чате слабая модель».
            // Здесь каждый раздел получает свою.
            Card(header: T("МОДЕЛЬ ПО РАЗДЕЛАМ", "MODEL PER SECTION")) {
                ForEach(Array(AIRole.allCases.enumerated()), id: \.element.id) { index, role in
                    AIRoleRow(role: role, first: index == 0,
                              onOpenSettings: {},
                              onOpenModels: { onOpenModels?() })
                }

                Row(title: T("Рассуждение локальной модели", "Local model reasoning"),
                    subtitle: T("В чате и брифах модель сначала обдумывает ответ. Медленнее, но заметно точнее на разборах. В причёсывании диктовки выключено всегда — там важнее секунды.", "In chat and briefs the model thinks before answering. Slower, but noticeably better on analysis. Always off in dictation cleanup — seconds matter more there.")) {
                    Toggle("", isOn: $settings.localThinkingInChat)
                        .toggleStyle(WisprToggleStyle())
                }
            }

            cloudSpendCard
            integrationsCard
        }
        .onAppear {
            apiKeyText = KeychainHelper.get(service: CloudAIProvider.keychainService) ?? ""
        }
    }

    private var selfTestStatus: String {
        if isSelfTesting { return selfTestStage }
        if selfTestResults.isEmpty {
            return T("Пять коротких запросов: ключ, поток, расширенные параметры, поиск, учёт расхода. Стоит доли цента.", "Five short requests: key, streaming, extended parameters, search, usage accounting. Costs a fraction of a cent.")
        }
        let failed = selfTestResults.filter { !$0.ok }.count
        return failed == 0
            ? T("Всё работает — \(selfTestResults.count) из \(selfTestResults.count)", "All good — \(selfTestResults.count) of \(selfTestResults.count)")
            : T("Не прошло проверок: \(failed) из \(selfTestResults.count)", "Checks failed: \(failed) of \(selfTestResults.count)")
    }

    private func runSelfTest() {
        isSelfTesting = true
        selfTestResults = []
        selfTestStage = T("Начинаю…", "Starting…")
        CloudAIProvider.shared.runSelfTest(
            webSearch: settings.enableLocalWebSearch,
            onProgress: { stage in selfTestStage = stage },
            completion: { results in
                selfTestResults = results
                isSelfTesting = false
            })
    }

    // MARK: - Интеграции

    /// Заметки и напоминания — это то, что приложение делает с чужими
    /// приложениями, а не часть какого-то одного экрана. Раньше эти
    /// настройки жили в «Брифах», где кроме них были ещё и сами брифы.
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

    // MARK: - Расход облака

    /// Причёсывание срабатывает на каждую диктовку, и при полутора сотнях
    /// диктовок за день выбор крупной модели в этой роли — решение с ценой.
    /// Раньше её нельзя было увидеть нигде, кроме счёта в конце месяца.
    private var cloudSpendCard: some View {
        let byRole = usage.todayByRole()
        return Card(header: T("РАСХОД ОБЛАКА", "CLOUD SPEND")) {
            Row(title: T("Сегодня", "Today"),
                subtitle: byRole.isEmpty
                    ? T("Облачных запросов сегодня не было. Локальные модели не считаются — они бесплатны.", "No cloud requests today. Local models are not counted — they are free.")
                    : T("Оценка сверху: чтение кэша на самом деле дешевле, чем считает этот счётчик.", "An upper bound: reading a cached prefix actually costs less than this counter assumes."),
                first: true) {
                HStack(spacing: 10) {
                    Text(UsageTracker.money(usage.todayCost))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text(UsageTracker.tokensShort(usage.todayTokens) + T(" ток.", " tok."))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            ForEach(byRole, id: \.role.id) { item in
                Row(title: item.role.title,
                    subtitle: T("\(item.requests) \(Plural.form(item.requests, "запрос", "запроса", "запросов")) · \(UsageTracker.tokensShort(item.tokens)) токенов", "\(item.requests) \(Plural.form(item.requests, "request", "requests", "requests")) · \(UsageTracker.tokensShort(item.tokens)) tokens")) {
                    Text(UsageTracker.money(item.cost))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            if usage.weekCost > 0 {
                Row(title: T("За последние 7 дней", "Over the last 7 days")) {
                    HStack(spacing: 10) {
                        Text(UsageTracker.money(usage.weekCost))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.textSecondary)
                        PillButton(title: T("Сбросить", "Discard"), icon: .clearAll) { usage.clear() }
                    }
                }
            }
        }
    }

    /// Подпись под выбором облачной модели: не «рекомендуем такую-то»,
    /// а честная цена и окно контекста того, что выбрано прямо сейчас.
    private var cloudModelSubtitle: String {
        guard let model = AIModelCatalog.cloudModel(id: settings.aiCloudModel) else {
            return T("Модель по умолчанию для всех разделов", "Default model for every section")
        }
        return "\(model.contextText) · \(model.priceText)"
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
                        settings.appTheme = .white
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
                        settings.appTheme = .terracotta
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
                        settings.appTheme = .dark
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
                        settings.appTheme = .system
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
