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

    var body: some View {
        SettingsPage(title: "Настройки") {

            // ── Оформление ──────────────────────────────────────────────
            Card(header: "ОФОРМЛЕНИЕ") {
                Row(title: "Язык интерфейса",
                    subtitle: "Язык отображения элементов программы (Русский / English)",
                    first: true) {
                    WisprDropdown(selection: $settings.interfaceLanguage,
                                  options: InterfaceLanguage.allCases) { lang in
                        Text(lang.title)
                    }
                }

                Row(title: "Плавающий индикатор записи",
                    subtitle: "Показывать индикатор поверх всех окон во время речи") {
                    Toggle("", isOn: $settings.showIndicator)
                        .toggleStyle(WisprToggleStyle())
                }
            }

            // Выбор темы
            themeSelectionCard

            // Выбор иконки приложения
            appIconSelectionCard

            // ── Система и звук ──────────────────────────────────────────
            Card(header: "СИСТЕМА И ЗВУК") {
                Row(title: "Запускать при входе в систему",
                    subtitle: "Автоматический запуск Intact вместе с macOS",
                    first: true) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .toggleStyle(WisprToggleStyle())
                        .onChange(of: settings.launchAtLogin) { _, new in LoginItem.set(enabled: new) }
                }

                Row(title: "Значок в Dock",
                    subtitle: "Отображать приложение в панели Dock") {
                    Toggle("", isOn: $settings.showDockIcon)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: "Заглушать системный звук во время речи",
                    subtitle: "Отключает вывод динамиков и наушников на время записи") {
                    Toggle("", isOn: $settings.muteAudioWhileDictating)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: "Приостанавливать музыку и видео",
                    subtitle: "Ставит на паузу Apple Music, Spotify и другие плееры на время речи") {
                    Toggle("", isOn: $settings.pauseMediaWhileDictating)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(title: "Звуковые сигналы",
                    subtitle: "Короткие звуки при начале, окончании и ошибке записи") {
                    Toggle("", isOn: $settings.playSounds)
                        .toggleStyle(WisprToggleStyle())
                }
            }

            // ── ИИ и провайдеры ──────────────────────────────────────────
            Card(header: "ИИ И ПРОВАЙДЕРЫ") {
                Row(title: "Провайдер ИИ",
                    subtitle: "Используется для умного причёсывания текста и чата",
                    first: true) {
                    WisprDropdown(selection: $settings.aiProviderKind,
                                  options: AIProviderKind.allCases) { kind in
                        Text(kind.title)
                    }
                }

                if settings.aiProviderKind == .cloud {
                    Row(title: "API-ключ Anthropic",
                        subtitle: "Ключ сохраняется в защищённом хранилище Keychain") {
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
                            PillButton(title: apiKeySaved ? "Сохранено" : "Сохранить",
                                       icon: apiKeySaved ? .success : .copied,
                                       tone: apiKeySaved ? .success : nil) {
                                KeychainHelper.set(apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines),
                                                   service: CloudAIProvider.keychainService)
                                apiKeySaved = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { apiKeySaved = false }
                            }
                        }
                    }

                    Row(title: "Модель Claude",
                        subtitle: cloudModelSubtitle) {
                        WisprDropdown(selection: $settings.aiCloudModel,
                                      options: AIModelCatalog.cloud.map(\.id)) { id in
                            Text(AIModelCatalog.cloudModel(id: id)?.title ?? id)
                        }
                    }
                }

                if settings.aiProviderKind == .local {
                    Row(title: "Локальные модели GGUF",
                        subtitle: "Загрузка и управление моделями llama-server") {
                        PillButton(title: "Хаб моделей", icon: .models) {
                            onOpenModels?()
                        }
                    }
                }

                Row(title: "Умное причёсывание диктовки",
                    subtitle: "Убирает слова-паразиты («э-э», «ну») и форматирует текст") {
                    Toggle("", isOn: $settings.enableAICleanup)
                        .toggleStyle(WisprToggleStyle())
                        .disabled(settings.aiProviderKind == .none)
                }
            }

            // ── Модель по разделам ───────────────────────────────────────
            // Одна модель на всё приложение — это выбор между «умно, но
            // диктовка тормозит» и «быстро, но в чате слабая модель».
            // Здесь каждый раздел получает свою.
            Card(header: "МОДЕЛЬ ПО РАЗДЕЛАМ") {
                ForEach(Array(AIRole.allCases.enumerated()), id: \.element.id) { index, role in
                    AIRoleRow(role: role, first: index == 0,
                              onOpenSettings: {},
                              onOpenModels: { onOpenModels?() })
                }
            }

            cloudSpendCard
        }
        .onAppear {
            apiKeyText = KeychainHelper.get(service: CloudAIProvider.keychainService) ?? ""
        }
    }

    // MARK: - Расход облака

    /// Причёсывание срабатывает на каждую диктовку, и при полутора сотнях
    /// диктовок за день выбор крупной модели в этой роли — решение с ценой.
    /// Раньше её нельзя было увидеть нигде, кроме счёта в конце месяца.
    private var cloudSpendCard: some View {
        let byRole = usage.todayByRole()
        return Card(header: "РАСХОД ОБЛАКА") {
            Row(title: "Сегодня",
                subtitle: byRole.isEmpty
                    ? "Облачных запросов сегодня не было. Локальные модели не считаются — они бесплатны."
                    : "Оценка сверху: чтение кэша на самом деле дешевле, чем считает этот счётчик.",
                first: true) {
                HStack(spacing: 10) {
                    Text(UsageTracker.money(usage.todayCost))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text(UsageTracker.tokensShort(usage.todayTokens) + " ток.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            ForEach(byRole, id: \.role.id) { item in
                Row(title: item.role.title,
                    subtitle: "\(item.requests) запросов · \(UsageTracker.tokensShort(item.tokens)) токенов") {
                    Text(UsageTracker.money(item.cost))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            if usage.weekCost > 0 {
                Row(title: "За последние 7 дней") {
                    HStack(spacing: 10) {
                        Text(UsageTracker.money(usage.weekCost))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.textSecondary)
                        PillButton(title: "Сбросить", icon: .clearAll) { usage.clear() }
                    }
                }
            }
        }
    }

    /// Подпись под выбором облачной модели: не «рекомендуем такую-то»,
    /// а честная цена и окно контекста того, что выбрано прямо сейчас.
    private var cloudModelSubtitle: String {
        guard let model = AIModelCatalog.cloudModel(id: settings.aiCloudModel) else {
            return "Модель по умолчанию для всех разделов"
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
