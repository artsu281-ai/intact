import SwiftUI
import Combine

/// Настройки опционального AI-слоя поверх диктовки: выбор провайдера (локально/облако),
/// ключ Anthropic, установка и выбор локальной модели, тумблеры фич.
struct AITab: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var models = LLMModelManager.shared
    @State private var apiKeyText: String = ""
    @State private var apiKeySaved = false
    @State private var isInstalling = false
    @State private var installLog: String = ""
    @State private var localAvailable = LocalAIProvider.shared.isAvailable
    @State private var localRunning = LocalAIProvider.shared.isRunning

    private let statusTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPage(title: L10n.tabAI) {
            Card(header: L10n.aiHeaderProvider) {
                Row(title: L10n.aiHeaderProvider, subtitle: L10n.aiProviderSubtitle, first: true) {
                    WisprDropdown(selection: $settings.aiProviderKind, options: AIProviderKind.allCases) { kind in
                        Text(kind.title)
                    }
                }
            }

            if settings.aiProviderKind == .cloud {
                cloudCard
            }

            if settings.aiProviderKind == .local {
                localCard
            }

            Card(header: L10n.aiHeaderFeatures) {
                Row(title: L10n.aiCleanupToggle, subtitle: L10n.aiCleanupToggleSub, first: true) {
                    Toggle("", isOn: $settings.enableAICleanup)
                        .toggleStyle(WisprToggleStyle())
                        .disabled(settings.aiProviderKind == .none)
                }
            }
        }
        .onAppear {
            apiKeyText = KeychainHelper.get(service: CloudAIProvider.keychainService) ?? ""
            refreshLocalStatus()
        }
        .onReceive(statusTimer) { _ in refreshLocalStatus() }
    }

    private func refreshLocalStatus() {
        localAvailable = LocalAIProvider.shared.isAvailable
        localRunning = LocalAIProvider.shared.isRunning
    }

    // MARK: - Облако

    private var cloudCard: some View {
        Card(header: L10n.aiHeaderCloud) {
            Row(title: L10n.aiApiKeyLabel, subtitle: L10n.aiApiKeySavedSub, first: true) {
                HStack(spacing: 8) {
                    SecureField(L10n.aiApiKeyPlaceholder, text: $apiKeyText)
                        .textFieldStyle(.plain)
                        .frame(width: 220)
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
                    PillButton(title: apiKeySaved ? "✓" : L10n.aiApiKeySave, symbol: apiKeySaved ? nil : "checkmark") {
                        KeychainHelper.set(apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines),
                                           service: CloudAIProvider.keychainService)
                        apiKeySaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { apiKeySaved = false }
                    }
                }
            }
            Row(title: L10n.aiCloudModelLabel) {
                Text(settings.aiCloudModel)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    // MARK: - Локально

    private var localCard: some View {
        Card(header: L10n.aiHeaderLocal) {
            if !localAvailable {
                Row(title: L10n.aiLocalServerMissing, subtitle: L10n.aiLocalServerMissingSub, first: true) {
                    if isInstalling {
                        ProgressView().controlSize(.small)
                    } else if LocalAIProvider.shared.isHomebrewAvailable {
                        PillButton(title: L10n.aiInstallHomebrewBtn, symbol: "arrow.down.circle") {
                            installLocalServer()
                        }
                    } else {
                        Text(L10n.aiHomebrewMissing)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: 260, alignment: .trailing)
                    }
                }
                if !installLog.isEmpty {
                    Row(title: L10n.aiInstalling) {
                        Text(installLog)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(2)
                            .frame(maxWidth: 300, alignment: .trailing)
                    }
                }
            } else {
                Row(title: L10n.aiLocalServerStatus,
                    subtitle: localRunning ? L10n.aiLocalServerRunning : L10n.aiLocalServerStopped,
                    first: true) {
                    PillButton(title: L10n.aiRestartBtn, symbol: "arrow.clockwise") {
                        LocalAIProvider.shared.stop()
                        LocalAIProvider.shared.ensureRunning { _ in
                            DispatchQueue.main.async { refreshLocalStatus() }
                        }
                    }
                }
            }

            VStack(spacing: 0) {
                ForEach(LLMModel.catalog) { model in
                    LLMModelRow(model: model, settings: settings, models: models, first: false)
                }
            }

            if let err = models.lastError {
                Row(title: L10n.micError, subtitle: err) { EmptyView() }
            }
        }
    }

    private func installLocalServer() {
        isInstalling = true
        installLog = ""
        LocalAIProvider.shared.installViaHomebrew(output: { line in
            installLog = line.trimmingCharacters(in: .whitespacesAndNewlines)
        }, completion: { _ in
            isInstalling = false
            refreshLocalStatus()
        })
    }
}

struct LLMModelRow: View {
    let model: LLMModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var models: LLMModelManager
    var first: Bool = false
    @State private var hovering = false

    private var isActive: Bool { settings.aiLocalModelPath == model.localURL.path }
    private var isDownloading: Bool { models.downloading == model.filename }

    var body: some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 22)
            }
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? Palette.textPrimary : Palette.textTertiary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                        Text("\(model.sizeMB) МБ")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Text(model.note)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isDownloading {
                        ProgressView(value: models.progress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 280)
                            .padding(.top, 4)
                    }
                }

                Spacer(minLength: 12)

                if isDownloading {
                    Text("\(Int(models.progress * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                } else if !model.isInstalled {
                    PillButton(title: "Скачать", symbol: "arrow.down.circle") {
                        models.download(model)
                    }
                } else if hovering, !isActive {
                    PillButton(title: "Удалить", symbol: "trash") {
                        models.delete(model)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isInstalled {
                // Смена пути сама триггерит onAIProviderChange → прогрев нового сервера;
                // явный stop() здесь убил бы только что запущенный процесс.
                settings.aiLocalModelPath = model.localURL.path
            }
        }
        .onHover { hovering = $0 }
    }
}
