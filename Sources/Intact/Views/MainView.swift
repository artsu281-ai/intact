import SwiftUI

/// Главный контейнер окна Intact с переключением между Чатом с ИИ и разделом Настроек.
struct MainView: View {
    @ObservedObject var state = MainWindowState.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            topNavBar
            Rectangle().fill(Palette.hairline).frame(height: 1)

            Group {
                switch state.selectedTab {
                case .chat:
                    ChatView(onOpenSettings: { targetSection in
                        state.selectedTab = .settings
                        if let s = targetSection {
                            state.settingsSection = s
                        }
                    })
                case .settings:
                    SettingsView(section: $state.settingsSection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 880, minHeight: 640)
        .background(Palette.page)
        .preferredColorScheme(settings.appTheme.colorScheme)
        .id(settings.appTheme)
    }

    // MARK: - Верхняя полоса навигации

    private var topNavBar: some View {
        HStack(alignment: .center, spacing: 14) {
            // Бренд Intact
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.accent.opacity(0.14))
                        .frame(width: 26, height: 26)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.accent)
                }
                Text("Intact")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.leading, 18)

            Spacer()

            // Переключатель вкладок
            HStack(spacing: 4) {
                tabButton(tab: .chat, title: "Чат с ИИ", symbol: "sparkles")
                tabButton(tab: .settings, title: "Настройки", symbol: "slider.horizontal.3")
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.dropdownBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
            )

            Spacer()

            // Индикатор текущей активной модели / провайдера ИИ
            Button {
                state.selectedTab = .settings
                state.settingsSection = .ai
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(providerStatusColor)
                        .frame(width: 6, height: 6)
                    Text(providerStatusText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Palette.dropdownBg)
                        .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 18)
            .help("Настройки ИИ и распознавания речи")
        }
        .frame(height: 46)
        .background(Palette.card)
    }

    private func tabButton(tab: MainTab, title: String, symbol: String) -> some View {
        let isSelected = state.selectedTab == tab

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                state.selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Palette.card : Color.clear)
                    .shadow(color: isSelected ? Color.black.opacity(0.04) : Color.clear, radius: 2, y: 1)
            )
            .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var providerStatusColor: Color {
        switch settings.aiProviderKind {
        case .none: return .orange
        case .local: return LocalAIProvider.shared.isReady ? .green : .orange
        case .cloud: return CloudAIProvider.shared.isReady ? .green : .orange
        }
    }

    private var providerStatusText: String {
        switch settings.aiProviderKind {
        case .none:
            return "ИИ выключен"
        case .local:
            let modelName = URL(fileURLWithPath: settings.aiLocalModelPath).deletingPathExtension().lastPathComponent
            return modelName.isEmpty ? "Локальная модель" : "Локально · \(modelName)"
        case .cloud:
            return "Облако · \(settings.aiCloudModel)"
        }
    }
}
