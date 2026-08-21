import AppKit
import SwiftUI

/// Единый презентационный ряд для каталогов моделей (Whisper, LLM, Gemma-Audio).
/// Чисто презентационный компонент без жёсткой привязки к конкретным типам моделей.
struct ModelCatalogRow: View {
    let title: String
    let sizeMB: Int
    let note: String?
    let isInstalled: Bool
    let isActive: Bool
    let isDownloading: Bool
    let progress: Double
    let downloadLabel: String
    var updateBadge: Bool = false
    var updateLabel: String? = nil
    var first: Bool = false
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    var onUpdate: (() -> Void)? = nil

    @State private var hovering = false

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
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                        Text("\(sizeMB) МБ")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textTertiary)

                        if updateBadge {
                            HStack(spacing: 4) {
                                Circle().fill(Color.orange).frame(width: 6, height: 6)
                                Text("Доступно обновление")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.orange)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.orange.opacity(0.12))
                            )
                        }
                    }
                    if let note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isDownloading {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 280)
                            .padding(.top, 4)
                    }
                }

                Spacer(minLength: 12)

                if isDownloading {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                } else if !isInstalled {
                    PillButton(title: downloadLabel, symbol: "arrow.down.circle") {
                        onDownload()
                    }
                } else if updateBadge, let updateLabel {
                    PillButton(title: updateLabel, symbol: "arrow.triangle.2.circlepath") {
                        onUpdate?()
                    }
                } else if hovering {
                    HStack(spacing: 8) {
                        if let onUpdate {
                            PillButton(title: updateLabel ?? "Обновить", symbol: "arrow.clockwise") {
                                onUpdate()
                            }
                        }
                        if !isActive {
                            PillButton(title: "Удалить", symbol: "trash") {
                                onDelete()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isInstalled {
                onSelect()
            }
        }
        .onHover { hovering = $0 }
    }
}

/// Единый хаб «Модели»: объединяет все каталоги (Whisper, LLM для причёсывания, Gemma-audio),
/// сводку по диску, настройки движка распознавания и технические параметры.
struct ModelsHub: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var whisperModels = ModelManager.shared
    @StateObject private var llmModels = LLMModelManager.shared
    @StateObject private var audioModels = GemmaAudioModelManager.shared
    @ObservedObject private var controller = DictationController.shared
    @State private var advanced = false

    private var totalInstalledGB: Double {
        let mb = whisperModels.installed.reduce(0) { $0 + $1.sizeMB }
                + llmModels.installed.reduce(0) { $0 + $1.sizeMB }
                + audioModels.installed.reduce(0) { $0 + $1.totalSizeMB }
        return Double(mb) / 1024.0
    }

    var body: some View {
        SettingsPage(title: L10n.tabModels) {
            if !whisperModels.hasAnyModelInstalled || whisperModels.downloading != nil {
                ModelOnboardingBanner()
            }

            diskUsageSummaryRow

            // 1. Каталог Whisper (распознавание речи)
            whisperCard

            // 2. Каталог LLM (причёсывание текста)
            llmCard

            // 3. Каталог Gemma Audio (экспериментальный all-in-one)
            gemmaAudioCard

            // 4. Скорость и фоновый движок
            engineCard

            // 5. Дополнительно (тонкая настройка)
            advancedBlock
        }
        .onAppear {
            if whisperModels.lastCheckTime == nil {
                whisperModels.checkForUpdates()
            }
            llmModels.refresh()
            audioModels.refresh()
        }
    }

    // MARK: - Индикатор занятого места

    private var diskUsageSummaryRow: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textSecondary)
                Text("\(String(format: "%.1f", totalInstalledGB)) ГБ занято на диске")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            PillButton(title: "Папки", symbol: "folder") {
                NSWorkspace.shared.open(ModelManager.directory)
                NSWorkspace.shared.open(LLMModelManager.directory)
                NSWorkspace.shared.open(GemmaAudioModelManager.directory)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    // MARK: - Карточка Whisper

    private var whisperCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("Распознавание речи (Whisper)".uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.leading, 4)
                if let msg = whisperModels.statusMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(whisperModels.updatesAvailable.isEmpty ? Palette.textTertiary : Color.orange)
                }
                Spacer()
                PillButton(title: whisperModels.isCheckingUpdates ? L10n.modelChecking : L10n.modelCheckUpdates,
                           symbol: "arrow.triangle.2.circlepath") {
                    whisperModels.checkForUpdates()
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(WhisperModel.catalog.enumerated()), id: \.element.id) { index, model in
                    ModelCatalogRow(
                        title: model.title,
                        sizeMB: model.sizeMB,
                        note: model.note,
                        isInstalled: model.isInstalled,
                        isActive: settings.modelPath == model.localURL.path,
                        isDownloading: whisperModels.downloading == model.filename,
                        progress: whisperModels.progress,
                        downloadLabel: "Скачать",
                        updateBadge: whisperModels.hasUpdate(model),
                        updateLabel: "Обновить",
                        first: index == 0,
                        onSelect: { settings.modelPath = model.localURL.path },
                        onDownload: { whisperModels.download(model) },
                        onDelete: { whisperModels.delete(model) },
                        onUpdate: { whisperModels.download(model, isUpdate: true) }
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
                    .shadow(color: Color(red: 0.35, green: 0.25, blue: 0.15).opacity(0.035), radius: 6, y: 2)
            )

            if let err = whisperModels.lastError {
                Text(err).font(.system(size: 12)).foregroundStyle(.red).padding(.leading, 4)
            }
        }
    }

    // MARK: - Карточка LLM

    private var llmCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Card(header: "Причёсывание текста (LLM)") {
                ForEach(Array(LLMModel.catalog.enumerated()), id: \.element.id) { index, model in
                    ModelCatalogRow(
                        title: model.title,
                        sizeMB: model.sizeMB,
                        note: model.note,
                        isInstalled: model.isInstalled,
                        isActive: settings.aiLocalModelPath == model.localURL.path,
                        isDownloading: llmModels.downloading == model.filename,
                        progress: llmModels.progress,
                        downloadLabel: "Скачать",
                        first: index == 0,
                        onSelect: { settings.aiLocalModelPath = model.localURL.path },
                        onDownload: { llmModels.download(model) },
                        onDelete: { llmModels.delete(model) }
                    )
                }
            }

            if let err = llmModels.lastError {
                Text(err).font(.system(size: 12)).foregroundStyle(.red).padding(.leading, 4)
            }
        }
    }

    // MARK: - Карточка Gemma Audio

    private var gemmaAudioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Card(header: "Экспериментально: аудио целиком (Gemma)") {
                ForEach(Array(GemmaAudioModel.catalog.enumerated()), id: \.element.id) { index, model in
                    ModelCatalogRow(
                        title: model.title,
                        sizeMB: model.totalSizeMB,
                        note: model.isInstalled ? nil : L10n.aiExperimentNotInstalled,
                        isInstalled: model.isInstalled,
                        isActive: settings.gemmaAudioModelFilename == model.mainFilename && model.isInstalled,
                        isDownloading: audioModels.downloading == model.mainFilename,
                        progress: audioModels.progress,
                        downloadLabel: L10n.aiExperimentDownloadBtn,
                        first: index == 0,
                        onSelect: {
                            settings.gemmaAudioModelFilename = model.mainFilename
                            GemmaAudioProvider.shared.stop()
                        },
                        onDownload: { audioModels.download(model) },
                        onDelete: { audioModels.delete(model) }
                    )
                }
            }

            if let err = audioModels.lastError {
                Text(err).font(.system(size: 12)).foregroundStyle(.red).padding(.leading, 4)
            }
        }
    }

    // MARK: - Карточка Скорость и движок

    private var engineCard: some View {
        Card(header: "Скорость и фоновый движок") {
            Row(title: "Распознавать во время речи",
                subtitle: "Модель держится загруженной, и текст считается, пока вы говорите. К отпусканию клавиши он обычно уже готов.",
                first: true) {
                Toggle("", isOn: $settings.streaming)
                    .toggleStyle(WisprToggleStyle())
                    .onChange(of: settings.streaming) { _, _ in controller.restartEngine() }
            }
            Row(title: "Состояние whisper-server", subtitle: engineStatus) {
                PillButton(title: "Перезапустить", symbol: "arrow.clockwise") {
                    controller.restartEngine()
                }
            }
        }
    }

    // MARK: - Дополнительно

    private var advancedBlock: some View {
        AdvancedBlock(expanded: $advanced) {
            Row(title: "Задержка последней вставки", first: true) {
                Text(controller.lastLatencyMs == 0 ? "мгновенно" : "\(controller.lastLatencyMs) мс")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(controller.lastLatencyMs == 0 ? Color.green : Palette.textSecondary)
            }
            Row(title: "Черновик каждые") {
                SliderControl(value: Binding(get: { Double(settings.draftIntervalMs) },
                                             set: { settings.draftIntervalMs = Int($0) }),
                              range: 200...1500, step: 50,
                              caption: "\(settings.draftIntervalMs) мс")
            }
            Row(title: "Аудиоконтекст энкодера",
                subtitle: "Урезанный считается быстрее, но обрезает окно распознавания") {
                WisprDropdown(selection: $settings.draftAudioContext,
                              options: [0, 768, 512]) { ctx in
                    switch ctx {
                    case 768: Text("768 — окно 15 с")
                    case 512: Text("512 — окно 10 с")
                    default:  Text("Полный контекст")
                    }
                }
                .onChange(of: settings.draftAudioContext) { _, _ in controller.restartEngine() }
            }
            Row(title: "Потоков CPU") {
                SliderControl(value: Binding(get: { Double(settings.threads) },
                                             set: { settings.threads = Int($0) }),
                              range: 1...Double(ProcessInfo.processInfo.activeProcessorCount), step: 1,
                              caption: "\(settings.threads)")
            }
            Row(title: "Файл модели",
                subtitle: URL(fileURLWithPath: settings.modelPath).lastPathComponent) {
                HStack(spacing: 8) {
                    PillButton(title: "Выбрать…") { pickModel() }
                    PillButton(title: "Папка") { NSWorkspace.shared.open(ModelManager.directory) }
                }
            }
        }
    }

    private var engineStatus: String {
        if !WhisperServer.shared.isAvailable { return "whisper-server не найден — работает запасной режим CLI" }
        if !settings.streaming { return "Выключено: текст считается после отпускания клавиши" }
        return controller.engineReady ? "Модель загружена в память и готова" : "Модель загружается…"
    }

    private func pickModel() {
        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.directoryURL = ModelManager.directory
        if panel.runModal() == .OK, let url = panel.url {
            settings.modelPath = url.path
        }
    }
}
