import AppKit
import SwiftUI

/// Единый презентационный ряд для каталогов моделей (Whisper, LLM, Gemma-Audio).
/// Чисто презентационный компонент без жёсткой привязки к конкретным типам моделей.
struct ModelCatalogRow: View {
    // Подписка на тему: см. `ThemeReader` в Theme.swift. Без неё вид
    // останется в старых цветах при смене темы. Не удалять как неиспользуемое.
    @ThemeReader var themeStamp

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
    /// Короткая техническая метка рядом с размером — например, формат квантования.
    var badge: String? = nil
    /// Предупреждение под описанием: модель не поместится в память этой машины.
    var warning: String? = nil
    /// Сколько байт уже лежит в недокачанном файле — тогда вместо «Скачать»
    /// предлагается «Продолжить».
    var partialBytes: Int64 = 0
    var onPause: (() -> Void)? = nil
    var onDiscardPartial: (() -> Void)? = nil
    var first: Bool = false
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    var onUpdate: (() -> Void)? = nil

    @State private var hovering = false

    /// Гигабайты десятичные — так же считают Finder и HuggingFace,
    /// иначе цифра в приложении не сойдётся с цифрой на диске.
    private var sizeText: String {
        sizeMB >= 1000
            ? String(format: T("%.1f ГБ", "%.1f GB"), Double(sizeMB) / 1000.0)
            : T("\(sizeMB) МБ", "\(sizeMB) MB")
    }

    var body: some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 22)
            }
            HStack(alignment: .center, spacing: 14) {
                IntactIcon(kind: isActive ? .radioOn : .radioOff, size: 17)
                    .foregroundStyle(isActive ? Palette.accent : Palette.iconMuted)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                        Text(sizeText)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textTertiary)

                        if let badge {
                            Text(badge)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Palette.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Palette.pill))
                        }

                        if updateBadge {
                            HStack(spacing: 4) {
                                Circle().fill(Palette.iconWarning).frame(width: 6, height: 6)
                                Text(T("Доступно обновление", "Update available"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Palette.iconWarning)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Palette.iconWarning.opacity(0.12))
                            )
                        }
                    }
                    if let note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let warning {
                        HStack(alignment: .top, spacing: 6) {
                            IntactIcon(kind: .warning, size: 14)
                                .foregroundStyle(Palette.iconWarning)
                            Text(warning)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Palette.iconWarning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 2)
                    }
                    if isDownloading {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 280)
                            .padding(.top, 4)
                    } else if partialBytes > 0, !isInstalled {
                        Text(String(format: T("Скачано %.1f ГБ из %@ — можно продолжить", "%.1f GB of %@ downloaded — you can resume"),
                                    Double(partialBytes) / 1_000_000_000, sizeText))
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.accent)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 12)

                if isDownloading {
                    HStack(spacing: 8) {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Palette.textSecondary)
                        if let onPause {
                            PillButton(title: T("Пауза", "Pause"), icon: .stop) { onPause() }
                        }
                    }
                } else if !isInstalled {
                    HStack(spacing: 8) {
                        PillButton(title: partialBytes > 0 ? T("Продолжить", "Resume") : downloadLabel, icon: .download) {
                            onDownload()
                        }
                        if partialBytes > 0, let onDiscardPartial {
                            PillButton(title: T("Сбросить", "Discard"), icon: .clearAll, tone: .danger) { onDiscardPartial() }
                        }
                    }
                } else if updateBadge, let updateLabel {
                    PillButton(title: updateLabel, icon: .update) {
                        onUpdate?()
                    }
                } else if hovering {
                    HStack(spacing: 8) {
                        if let onUpdate {
                            PillButton(title: updateLabel ?? T("Обновить", "Refresh"), icon: .refresh) {
                                onUpdate()
                            }
                        }
                        if !isActive {
                            PillButton(title: T("Удалить", "Delete"), icon: .clearAll, tone: .danger) {
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
    // Подписка на тему: см. `ThemeReader` в Theme.swift. Без неё вид
    // останется в старых цветах при смене темы. Не удалять как неиспользуемое.
    @ThemeReader var themeStamp

    @ObservedObject var settings: AppSettings
    @StateObject private var whisperModels = ModelManager.shared
    @StateObject private var llmModels = LLMModelManager.shared
    @StateObject private var audioModels = GemmaAudioModelManager.shared
    @ObservedObject private var controller = DictationController.shared
    @State private var advanced = false
    /// Прятать модели, которые не влезут в память этой машины.
    /// Переживает перезапуск: у машины память не меняется от сессии к сессии.
    @AppStorage("modelsFitOnly") private var fitOnly = false

    private var totalInstalledGB: Double {
        let mb = whisperModels.installed.reduce(0) { $0 + $1.sizeMB }
                + llmModels.installedPairs.reduce(0) { $0 + $1.quant.sizeMB }
                + audioModels.installed.reduce(0) { $0 + $1.totalSizeMB }
        return Double(mb) / 1000.0
    }

    var body: some View {
        SettingsPage(title: L10n.tabModels) {
            if !whisperModels.hasAnyModelInstalled || whisperModels.downloading != nil {
                ModelOnboardingBanner()
            }

            diskUsageSummaryRow

            // 0. Кто чем занят прямо сейчас
            rolesCard

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
            audioModels.refresh()
        }
    }

    // MARK: - Индикатор занятого места

    private var diskUsageSummaryRow: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                IntactIcon(kind: .disk, size: 16)
                    .foregroundStyle(Palette.textSecondary)
                Text(T("\(String(format: "%.1f", totalInstalledGB)) ГБ занято на диске", "\(String(format: "%.1f", totalInstalledGB)) GB on disk"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button {
                fitOnly.toggle()
            } label: {
                HStack(spacing: 6) {
                    IntactIcon(kind: fitOnly ? .radioOn : .radioOff, size: 13)
                    Text(T("Только то, что влезет", "Only what fits"))
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(fitOnly ? Palette.accent : Palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5.5)
                .background(Capsule().fill(fitOnly ? Palette.accent.opacity(0.10) : Palette.pill))
            }
            .buttonStyle(.plain)
            .help(T("Скрыть модели, которые не поместятся в \(String(format: "%.0f", Hardware.physicalMemoryGB)) ГБ памяти", "Hide models that will not fit into \(String(format: "%.0f", Hardware.physicalMemoryGB)) GB of memory"))

            PillButton(title: T("Папки", "Folders"), icon: .folder) {
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
                Text(T("Распознавание речи (Whisper)", "Speech recognition (Whisper)").uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.leading, 4)
                if let msg = whisperModels.statusMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(whisperModels.updatesAvailable.isEmpty ? Palette.textTertiary : Palette.iconWarning)
                }
                Spacer()
                PillButton(title: whisperModels.isCheckingUpdates ? L10n.modelChecking : L10n.modelCheckUpdates,
                           icon: .update) {
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
                        downloadLabel: T("Скачать", "Download"),
                        updateBadge: whisperModels.hasUpdate(model),
                        updateLabel: T("Обновить", "Refresh"),
                        partialBytes: whisperModels.partialBytes(model),
                        onPause: { whisperModels.pauseDownload() },
                        onDiscardPartial: { whisperModels.discardPartial(model) },
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
                Text(err).font(.system(size: 12)).foregroundStyle(Palette.iconDanger).padding(.leading, 4)
            }
        }
    }

    // MARK: - Кто чем занят

    /// Раньше понять, какая модель отвечает за причёсывание, а какая за чат,
    /// можно было только перебирая разделы. Это же и главный вход в выбор:
    /// сюда приходят за моделями, здесь их и назначают.
    private var rolesCard: some View {
        Card(header: T("КАКАЯ МОДЕЛЬ ЗА ЧТО ОТВЕЧАЕТ", "WHICH MODEL DOES WHAT")) {
            ForEach(Array(AIRole.allCases.enumerated()), id: \.element.id) { index, role in
                AIRoleRow(role: role, first: index == 0,
                          onOpenSettings: { MainWindowState.shared.section = .settings },
                          onOpenModels: {})
            }
        }
    }

    // MARK: - Карточка LLM

    private var llmCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(visibleTiers, id: \.self) { tier in
                VStack(alignment: .leading, spacing: 10) {
                    llmGroup(tier, header: header(for: tier))

                    if let note = memoryNote(for: tier) {
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(fits(tier) ? Palette.textTertiary : Palette.iconWarning)
                            .padding(.leading, 4)
                    }
                }
            }

            if let err = llmModels.lastError {
                Text(err).font(.system(size: 12)).foregroundStyle(Palette.iconDanger).padding(.leading, 4)
            }
        }
    }

    /// Ярусы, в которых после фильтра что-то осталось: пустая карточка
    /// с заголовком «очень крупные» на машине, которая их не тянет, —
    /// это шум, а не информация.
    private var visibleTiers: [LLMTier] {
        LLMTier.allCases.filter { tier in
            !fitOnly || LLMModel.catalog(tier).contains { model in
                model.quantOptions.contains { model.fitsInMemory($0) }
            }
        }
    }

    private func header(for tier: LLMTier) -> String {
        switch tier {
        case .light:  return T("Лёгкие · причёсывание текста и короткие брифы", "Light · text cleanup and short briefs")
        case .large:  return T("Крупные · аналитика, код, рассуждения", "Large · analysis, code, reasoning")
        case .xlarge: return T("Очень крупные · настольный предел, спорят с облаком", "Very large · the desktop limit, a match for the cloud")
        }
    }

    private func fits(_ tier: LLMTier) -> Bool {
        Hardware.physicalMemoryGB >= tier.recommendedRAMGB
    }

    /// Не «нужно 16 ГБ» в вакууме, а сравнение с этой конкретной машиной:
    /// от него зависит, стоит ли вообще начинать качать двадцать гигабайт.
    private func memoryNote(for tier: LLMTier) -> String? {
        guard tier != .light else { return nil }
        let mine = String(format: "%.0f", Hardware.physicalMemoryGB)
        let need = String(format: "%.0f", tier.recommendedRAMGB)
        return fits(tier)
            ? T("Рекомендуется от \(need) ГБ памяти. В этом Mac — \(mine) ГБ, запас есть.", "\(need) GB of memory recommended. This Mac has \(mine) GB — room to spare.")
            : T("Рекомендуется от \(need) ГБ памяти, в этом Mac — \(mine) ГБ. Скачать можно, но работать будет через своп.", "\(need) GB of memory recommended, this Mac has \(mine) GB. You can download it, but it will run through swap.")
    }

    private func llmGroup(_ tier: LLMTier, header: String) -> some View {
        let models = LLMModel.catalog(tier).filter { model in
            !fitOnly || model.quantOptions.contains { model.fitsInMemory($0) }
        }
        return Card(header: header) {
            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                LLMQuantRow(model: model, settings: settings, models: llmModels, first: index == 0)
            }
        }
    }

    // MARK: - Карточка Gemma Audio

    private var gemmaAudioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Card(header: T("Экспериментально: аудио целиком (Gemma)", "Experimental: audio end to end (Gemma)")) {
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
                // Проверить модель имеет смысл там же, где её скачали.
                if !audioModels.installed.isEmpty {
                    GemmaAudioTestRow(settings: settings)
                }
            }

            if let err = audioModels.lastError {
                Text(err).font(.system(size: 12)).foregroundStyle(Palette.iconDanger).padding(.leading, 4)
            }
        }
    }

    // MARK: - Карточка Скорость и движок

    private var engineCard: some View {
        Card(header: T("Скорость и фоновый движок", "Speed and background engine")) {
            Row(title: T("Распознавать во время речи", "Transcribe while speaking"),
                subtitle: T("Модель держится загруженной, и текст считается, пока вы говорите. К отпусканию клавиши он обычно уже готов.", "The model stays loaded and the text is computed as you speak. By the time you release the key it is usually ready."),
                first: true) {
                Toggle("", isOn: $settings.streaming)
                    .toggleStyle(WisprToggleStyle())
                    .onChange(of: settings.streaming) { _, _ in controller.restartEngine() }
            }
            Row(title: T("Состояние whisper-server", "whisper-server status"), subtitle: engineStatus) {
                PillButton(title: T("Перезапустить", "Restart"), icon: .refresh) {
                    controller.restartEngine()
                }
            }
        }
    }

    // MARK: - Дополнительно

    private var advancedBlock: some View {
        AdvancedBlock(expanded: $advanced) {
            Row(title: T("Задержка последней вставки", "Latency of the last insert"), first: true) {
                Text(controller.lastLatencyMs == 0 ? T("мгновенно", "instant") : T("\(controller.lastLatencyMs) мс", "\(controller.lastLatencyMs) ms"))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(controller.lastLatencyMs == 0 ? Palette.iconSuccess : Palette.textSecondary)
            }
            Row(title: T("Черновик каждые", "Draft every")) {
                SliderControl(value: Binding(get: { Double(settings.draftIntervalMs) },
                                             set: { settings.draftIntervalMs = Int($0) }),
                              range: 200...1500, step: 50,
                              caption: T("\(settings.draftIntervalMs) мс", "\(settings.draftIntervalMs) ms"))
            }
            Row(title: T("Аудиоконтекст энкодера", "Encoder audio context"),
                subtitle: T("Урезанный считается быстрее, но обрезает окно распознавания", "A shorter one computes faster but narrows the recognition window")) {
                WisprDropdown(selection: $settings.draftAudioContext,
                              options: [0, 768, 512]) { ctx in
                    switch ctx {
                    case 768: Text(T("768 — окно 15 с", "768 — 15 s window"))
                    case 512: Text(T("512 — окно 10 с", "512 — 10 s window"))
                    default:  Text(T("Полный контекст", "Full context"))
                    }
                }
                .onChange(of: settings.draftAudioContext) { _, _ in controller.restartEngine() }
            }
            Row(title: T("Потоков CPU", "CPU threads")) {
                SliderControl(value: Binding(get: { Double(settings.threads) },
                                             set: { settings.threads = Int($0) }),
                              range: 1...Double(ProcessInfo.processInfo.activeProcessorCount), step: 1,
                              caption: "\(settings.threads)")
            }
            Row(title: T("Файл модели", "Model file"),
                subtitle: URL(fileURLWithPath: settings.modelPath).lastPathComponent) {
                HStack(spacing: 8) {
                    PillButton(title: T("Выбрать…", "Choose…")) { pickModel() }
                    PillButton(title: T("Папка", "Folder")) { NSWorkspace.shared.open(ModelManager.directory) }
                }
            }
        }
    }

    private var engineStatus: String {
        if !WhisperServer.shared.isAvailable { return T("whisper-server не найден — работает запасной режим CLI", "whisper-server not found — falling back to CLI mode") }
        if !settings.streaming { return T("Выключено: текст считается после отпускания клавиши", "Off: text is computed after the key is released") }
        return controller.engineReady ? T("Модель загружена в память и готова", "Model loaded into memory and ready") : T("Модель загружается…", "Model is loading…")
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

/// Ряд LLM-модели с выбором кванта: одна модель, несколько файлов на выбор
/// (Q3_K_M…Q8_0), скачивание/выбор/удаление применяются к выбранному кванту.
/// Отдельный компонент, а не расширение ModelCatalogRow: у остальных двух
/// каталогов (Whisper, Gemma-audio) кванта нет и добавлять им лишний параметр
/// незачем — так проще, чем тащить через ModelCatalogRow условную опцию.
struct LLMQuantRow: View {
    // Подписка на тему: см. `ThemeReader` в Theme.swift. Без неё вид
    // останется в старых цветах при смене темы. Не удалять как неиспользуемое.
    @ThemeReader var themeStamp

    let model: LLMModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var models: LLMModelManager
    var first: Bool = false

    @State private var selectedQuant: LLMQuantOption
    @State private var hovering = false

    init(model: LLMModel, settings: AppSettings, models: LLMModelManager, first: Bool = false) {
        self.model = model
        self.settings = settings
        self.models = models
        self.first = first
        _selectedQuant = State(initialValue: model.installedQuant ?? model.defaultQuant)
    }

    private var isInstalled: Bool { model.isInstalled(selectedQuant) }
    private var isActive: Bool { settings.aiLocalModelPath == model.localURL(for: selectedQuant).path }
    private var isDownloading: Bool { models.downloading == selectedQuant.filename }
    /// Сколько уже лежит в недокачанном файле.
    private var partial: Int64 { isInstalled ? 0 : models.partialBytes(model, selectedQuant) }
    /// Модель прямо сейчас держится в памяти пулом llama-server.
    private var isLoadedInMemory: Bool {
        LocalAIProvider.shared.loadedModelPaths.contains(model.localURL(for: selectedQuant).path)
    }

    private func gb(_ bytes: Int64) -> String {
        String(format: T("%.1f ГБ", "%.1f GB"), Double(bytes) / 1_000_000_000)
    }

    private var progressCaption: String {
        let done = gb(models.downloadedBytes)
        let total = models.totalBytes > 0 ? gb(models.totalBytes) : sizeText
        return models.resumed ? T("\(done) из \(total) · продолжено", "\(done) of \(total) · resumed") : T("\(done) из \(total)", "\(done) of \(total)")
    }

    /// Честное предупреждение до скачивания десяти гигабайт: без запаса памяти
    /// llama-server уйдёт в своп и будет отвечать минутами вместо секунд.
    private var warning: String? {
        guard !model.fitsInMemory(selectedQuant) else { return nil }
        return String(format: T("Нужно около %.0f ГБ памяти вместе с контекстом — в этом Mac %.0f ГБ. Скачать можно, но работать будет через своп.", "Needs about %.0f GB of memory including context — this Mac has %.0f GB. You can download it, but it will run through swap."),
                      model.estimatedRAMGB(for: selectedQuant) + 3, Hardware.physicalMemoryGB)
    }

    private var sizeText: String {
        selectedQuant.sizeMB >= 1000
            ? String(format: T("%.1f ГБ", "%.1f GB"), Double(selectedQuant.sizeMB) / 1000.0)
            : T("\(selectedQuant.sizeMB) МБ", "\(selectedQuant.sizeMB) MB")
    }

    var body: some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 22)
            }
            HStack(alignment: .center, spacing: 14) {
                IntactIcon(kind: isActive ? .radioOn : .radioOff, size: 17)
                    .foregroundStyle(isActive ? Palette.accent : Palette.iconMuted)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                        Text(sizeText)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textTertiary)
                        WisprDropdown(selection: $selectedQuant, options: model.quantOptions) { q in
                            Text(q.quant)
                        }
                        if model.reasons {
                            Text(model.thinking == .always ? T("рассуждает всегда", "always reasons") : T("умеет рассуждать", "can reason"))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Palette.iconProcess)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Palette.iconProcess.opacity(0.13)))
                                .help(T("В чате и брифах модель сначала обдумывает ответ. Дольше, но точнее — в причёсывании диктовки рассуждение всегда выключено.", "In chat and briefs the model thinks before answering. Slower but more accurate — in dictation cleanup reasoning is always off."))
                        }
                        if isLoadedInMemory {
                            HStack(spacing: 4) {
                                Circle().fill(Palette.iconSuccess).frame(width: 5, height: 5)
                                Text(T("в памяти", "in memory"))
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundStyle(Palette.iconSuccess)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Palette.iconSuccess.opacity(0.12)))
                            .help(T("Модель загружена в память и отвечает без задержки на старт", "Loaded in memory and answers without the start-up delay"))
                        }
                    }
                    Text(model.note)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let warning {
                        HStack(alignment: .top, spacing: 6) {
                            IntactIcon(kind: .warning, size: 14)
                                .foregroundStyle(Palette.iconWarning)
                            Text(warning)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Palette.iconWarning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 2)
                    }
                    if isDownloading {
                        VStack(alignment: .leading, spacing: 3) {
                            ProgressView(value: models.progress)
                                .progressViewStyle(.linear)
                                .frame(maxWidth: 280)
                            Text(progressCaption)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .padding(.top, 4)
                    } else if partial > 0 {
                        Text(T("Скачано \(gb(partial)) из \(sizeText) — можно продолжить", "\(gb(partial)) of \(sizeText) downloaded — you can resume"))
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.accent)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 12)

                if isDownloading {
                    HStack(spacing: 8) {
                        Text("\(Int(models.progress * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Palette.textSecondary)
                        PillButton(title: T("Пауза", "Pause"), icon: .stop) { models.pauseDownload() }
                    }
                } else if !isInstalled {
                    HStack(spacing: 8) {
                        if partial > 0 {
                            PillButton(title: T("Продолжить", "Resume"), icon: .download) {
                                models.download(model, selectedQuant)
                            }
                            PillButton(title: T("Сбросить", "Discard"), icon: .clearAll, tone: .danger) {
                                models.discardPartial(selectedQuant)
                            }
                        } else {
                            PillButton(title: T("Скачать", "Download"), icon: .download) {
                                models.download(model, selectedQuant)
                            }
                        }
                    }
                } else if hovering, !isActive {
                    PillButton(title: T("Удалить", "Delete"), icon: .clearAll, tone: .danger) {
                        models.delete(model, selectedQuant)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isInstalled {
                settings.aiLocalModelPath = model.localURL(for: selectedQuant).path
            }
        }
        .onHover { hovering = $0 }
    }
}


/// Пробная запись для экспериментальной аудио-модели: голос уходит в модель
/// целиком, минуя Whisper, и возвращается уже причёсанным текстом.
/// Живёт рядом с каталогом, потому что проверять модель идут сразу после того,
/// как её скачали.
struct GemmaAudioTestRow: View {
    // Подписка на тему: см. `ThemeReader` в Theme.swift. Без неё вид
    // останется в старых цветах при смене темы. Не удалять как неиспользуемое.
    @ThemeReader var themeStamp

    @ObservedObject var settings: AppSettings

    @State private var recorder = AudioRecorder()
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var result: String = ""
    @State private var error: String?

    var body: some View {
        Row(title: L10n.aiExperimentRecordBtn, subtitle: subtitle) {
            if isProcessing {
                ProgressView().controlSize(.small)
            } else {
                PillButton(title: isRecording ? L10n.aiExperimentStopBtn : L10n.aiExperimentRecordBtn,
                           icon: isRecording ? .stop : .voice) {
                    isRecording ? stop() : start()
                }
            }
        }
    }

    private var subtitle: String {
        if isProcessing { return L10n.aiExperimentProcessing }
        if let error { return error }
        return result.isEmpty ? T("Записать фразу и посмотреть, что вернёт модель", "Record a phrase and see what the model returns") : result
    }

    private func start() {
        error = nil
        result = ""
        do {
            try recorder.start(preferredDeviceUID: settings.inputDeviceUID)
            isRecording = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stop() {
        isRecording = false
        _ = recorder.stop()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("intact-gemma-test.wav")
        guard recorder.snapshot(to: url, trimTrailingSilence: false) != nil else {
            error = T("Слишком короткая запись.", "Recording too short.")
            return
        }
        isProcessing = true
        DispatchQueue.global(qos: .userInitiated).async {
            GemmaAudioProvider.shared.transcribeAndRefine(wav: url) { outcome in
                DispatchQueue.main.async {
                    isProcessing = false
                    switch outcome {
                    case .success(let text): result = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    case .failure(let err):  error = err.localizedDescription
                    }
                }
            }
        }
    }
}
