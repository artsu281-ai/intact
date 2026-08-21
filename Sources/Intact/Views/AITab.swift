import SwiftUI
import Combine

/// Настройки опционального AI-слоя поверх диктовки: выбор провайдера (локально/облако),
/// ключ Anthropic, установка и выбор локальной модели, тумблеры фич.
struct AITab: View {
    @ObservedObject var settings: AppSettings
    var onOpenModels: (() -> Void)? = nil

    @StateObject private var models = LLMModelManager.shared
    @State private var apiKeyText: String = ""
    @State private var apiKeySaved = false
    @State private var isInstalling = false
    @State private var installLog: String = ""
    @State private var localAvailable = LocalAIProvider.shared.isAvailable
    @State private var localRunning = LocalAIProvider.shared.isRunning

    @StateObject private var audioModel = GemmaAudioModelManager.shared
    @State private var testRecorder = AudioRecorder()
    @State private var isTestRecording = false
    @State private var isTestProcessing = false
    @State private var testResult: String = ""
    @State private var testError: String?

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

            experimentCard
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

            let currentModelName = URL(fileURLWithPath: settings.aiLocalModelPath).lastPathComponent
            Row(title: "Модель",
                subtitle: currentModelName.isEmpty ? "Не выбрана" : currentModelName) {
                PillButton(title: "Управлять моделями", symbol: "square.stack.3d.up") {
                    onOpenModels?()
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

    // MARK: - Эксперимент: всё-в-одном через Gemma

    private var experimentCard: some View {
        Card(header: L10n.aiExperimentHeader) {
            Row(title: L10n.aiExperimentHeader, subtitle: L10n.aiExperimentSubtitle, first: true) { EmptyView() }

            let currentAudioModelName = settings.gemmaAudioModelFilename
            Row(title: "Модель",
                subtitle: currentAudioModelName.isEmpty ? "Не выбрана" : currentAudioModelName) {
                PillButton(title: "Управлять моделями", symbol: "square.stack.3d.up") {
                    onOpenModels?()
                }
            }

            if !audioModel.installed.isEmpty {
                Row(title: L10n.aiExperimentRecordBtn, subtitle: statusOrResultSubtitle) {
                    if isTestProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        PillButton(title: isTestRecording ? L10n.aiExperimentStopBtn : L10n.aiExperimentRecordBtn,
                                   symbol: isTestRecording ? "stop.fill" : "mic.fill") {
                            isTestRecording ? stopTest() : startTest()
                        }
                    }
                }
                if !testResult.isEmpty {
                    Row(title: L10n.aiExperimentResultTitle) {
                        Text(testResult)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: 320, alignment: .trailing)
                            .textSelection(.enabled)
                    }
                }
            }

            if let err = testError ?? audioModel.lastError {
                Row(title: L10n.micError, subtitle: err) { EmptyView() }
            }
        }
    }

    private var statusOrResultSubtitle: String {
        isTestProcessing ? L10n.aiExperimentProcessing : ""
    }

    private func startTest() {
        testError = nil
        testResult = ""
        do {
            try testRecorder.start(preferredDeviceUID: settings.inputDeviceUID)
            isTestRecording = true
        } catch {
            testError = error.localizedDescription
        }
    }

    private func stopTest() {
        isTestRecording = false
        _ = testRecorder.stop()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("intact-gemma-test.wav")
        guard testRecorder.snapshot(to: url, trimTrailingSilence: false) != nil else {
            testError = "Слишком короткая запись."
            return
        }
        isTestProcessing = true
        DispatchQueue.global(qos: .userInitiated).async {
            GemmaAudioProvider.shared.transcribeAndRefine(wav: url) { result in
                DispatchQueue.main.async {
                    isTestProcessing = false
                    switch result {
                    case .success(let text):
                        testResult = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    case .failure(let err):
                        testError = err.localizedDescription
                    }
                }
            }
        }
    }
}
