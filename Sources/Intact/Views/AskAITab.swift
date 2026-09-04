import AppKit
import SwiftUI

/// Экран «Спросите ИИ»: второй, независимый от диктовки хоткей — держишь клавишу,
/// задаёшь вопрос голосом, и вместо причёсанного текста вставляется прямой ответ ИИ.
/// Вынесено отдельным пунктом сайдбара из вкладки «Диктовка», чтобы фичу было проще найти.
struct AskAITab: View {
    // Подписка на тему: см. `ThemeReader` в Theme.swift. Без неё вид
    // останется в старых цветах при смене темы. Не удалять как неиспользуемое.
    @ThemeReader var themeStamp

    @ObservedObject var settings: AppSettings
    var onOpenSection: ((SettingsSection) -> Void)? = nil

    @ObservedObject private var controller = DictationController.shared
    @ObservedObject private var geminiBridge = GeminiBridgeService.shared
    @ObservedObject private var pipelineManager = PipelineManager.shared
    @State private var copiedID: UUID? = nil
    @State private var isTestingGemini: Bool = false
    @State private var testResult: String? = nil

    private var aiReady: Bool { AIRouter.shared.isReady(for: .quickAnswer) }

    /// Клавиши и кнопки мыши, которые можно назначить пайплайну.
    private static let triggerOptions: [TriggerSource] =
        TriggerKey.allCases.map { TriggerSource.modifierKey($0) }
        + MouseButtonType.allCases.map { TriggerSource.mouseButton($0) }

    /// Правка одного поля пайплайна прямо в списке.
    private func pipelineBinding<V: Equatable>(
        _ pipeline: VoicePipeline,
        _ keyPath: WritableKeyPath<VoicePipeline, V>
    ) -> Binding<V> {
        Binding(
            get: {
                (pipelineManager.pipelines.first { $0.id == pipeline.id } ?? pipeline)[keyPath: keyPath]
            },
            set: { newValue in
                var updated = pipelineManager.pipelines.first { $0.id == pipeline.id } ?? pipeline
                updated[keyPath: keyPath] = newValue
                pipelineManager.updatePipeline(updated)
            }
        )
    }

    var body: some View {
        SettingsPage(title: L10n.tabAskAI) {
            VStack(alignment: .leading, spacing: 8) {
                Text(T("Отдельный хоткей, который не диктует, а спрашивает", "A separate hotkey that asks instead of dictating"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(T("Держишь клавишу, говоришь вопрос или просьбу — приложение отправляет сказанное в ИИ и сразу вставляет прямой ответ вместо обычной диктовки, без вступлений и лишних слов.", "Hold the key, ask a question or make a request — the app sends what you said to the AI and inserts the answer straight away instead of the usual dictation, with no preamble."))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 2)

            pipelinesCard

            if !aiReady {
                Card(header: nil) {
                    Row(title: T("ИИ ещё не настроен", "AI is not set up yet"),
                        subtitle: T("Хоткей сработает только после выбора модели — локальной или облачной", "The hotkey only works once a model is chosen — local or cloud"),
                        first: true) {
                        PillButton(title: T("Настроить ИИ", "Set up AI"), icon: .settingsPage) {
                            onOpenSection?(.settings)
                        }
                    }
                }
            }

            // Выбор модели прямо здесь: у быстрого ответа свои требования —
            // он должен успеть, пока человек ждёт текст под курсором, — и они
            // не совпадают с тем, что нужно чату.
            Card(header: T("МОДЕЛЬ", "MODEL")) {
                AIRoleRow(role: .quickAnswer, first: true,
                          onOpenSettings: { onOpenSection?(.settings) },
                          onOpenModels: { onOpenSection?(.models) })
            }

            if !controller.recentAnswers.isEmpty {
                recentCard
            }

            geminiCard

            VStack(alignment: .leading, spacing: 6) {
                Text(T("НАПРИМЕР", "FOR EXAMPLE"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.leading, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("«Сколько будет 24 умножить на 17» → 408", "“What is 24 times 17” → 408"))
                    Text(T("«Столица Австралии» → Канберра", "“Capital of Australia” → Canberra"))
                    Text(T("«Напиши короткое поздравление с днём рождения» → готовый текст", "“Write a short birthday greeting” → ready-to-paste text"))
                }
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    // MARK: - Интеграция с Gemini.app

    private var geminiCard: some View {
        Card(header: L10n.geminiCardHeader) {
            Row(
                title: L10n.geminiIntegrationTitle,
                subtitle: geminiBridge.isInstalled
                    ? (geminiBridge.isRunning ? "\(L10n.geminiInstalled) · \(L10n.geminiRunning)" : "\(L10n.geminiInstalled) · \(L10n.geminiNotRunning)")
                    : L10n.geminiNotInstalled,
                first: true
            ) {
                Toggle("", isOn: $settings.geminiIntegrationEnabled)
                    .toggleStyle(WisprToggleStyle())
            }

            if settings.geminiIntegrationEnabled {
                // Выбор экземпляра появляется, только если копия действительно есть:
                // одинокий выпадающий список с единственным вариантом — мусор в интерфейсе.
                let instances = GeminiBridgeService.availableInstances()
                if instances.count > 1 {
                    Row(
                        title: T("Экземпляр Gemini", "Gemini instance"),
                        subtitle: T("Отдельная копия работает со своим аккаунтом и своей перепиской — Intact не вмешивается в ваш рабочий чат",
                                    "A separate copy runs with its own account and its own history — Intact stays out of your working chat")
                    ) {
                        WisprDropdown(
                            selection: $settings.geminiBundleIdentifier,
                            options: instances.map(\.bundleId)
                        ) { id in
                            Text(instances.first(where: { $0.bundleId == id })?.title ?? id)
                        }
                    }
                }

                Row(
                    title: L10n.geminiBackgroundModeTitle,
                    subtitle: L10n.geminiBackgroundModeSub
                ) {
                    Toggle("", isOn: $settings.geminiBackgroundMode)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(
                    title: L10n.geminiVoiceCommandTitle,
                    subtitle: L10n.geminiVoiceCommandSub
                ) {
                    Toggle("", isOn: $settings.geminiVoiceCommandEnabled)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(
                    title: L10n.geminiAutoSubmitTitle,
                    subtitle: L10n.geminiAutoSubmitSub
                ) {
                    Toggle("", isOn: $settings.geminiAutoSubmit)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(
                    title: L10n.geminiNewChatTitle,
                    subtitle: L10n.geminiNewChatSub
                ) {
                    Toggle("", isOn: $settings.geminiCreateNewChat)
                        .toggleStyle(WisprToggleStyle())
                }

                Row(
                    title: L10n.geminiTestButton,
                    subtitle: isTestingGemini ? T("Отправка запроса в Gemini...", "Sending prompt to Gemini...") : (testResult ?? T("Нажмите для проверки работы AppleScript с приложением Gemini", "Click to test AppleScript communication with Gemini.app"))
                ) {
                    HStack(spacing: 8) {
                        if isTestingGemini {
                            ProgressView().controlSize(.small)
                        } else {
                            PillButton(
                                title: L10n.geminiTestButton,
                                icon: .aiStar,
                                tone: testResult != nil ? .success : nil
                            ) {
                                isTestingGemini = true
                                testResult = nil
                                geminiBridge.testSend { success, msg in
                                    isTestingGemini = false
                                    testResult = success ? T("✓ Успешно отправлено!", "✓ Sent successfully!") : (msg ?? "Ошибка")
                                }
                            }
                        }

                        PillButton(title: L10n.geminiOpenButton, icon: .folder) {
                            geminiBridge.openGemini()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Модульные голосовые пайплайны и органы управления

    private var pipelinesCard: some View {
        Card(header: T("ГОЛОСОВЫЕ ПАЙПЛАЙНЫ И ОРГАНЫ УПРАВЛЕНИЯ", "VOICE PIPELINES & CONTROLS")) {
            ForEach(Array(pipelineManager.pipelines.enumerated()), id: \.element.id) { index, pipeline in
                pipelineRow(pipeline, first: index == 0)
            }
        }
    }

    @ViewBuilder
    private func pipelineRow(_ pipeline: VoicePipeline, first: Bool) -> some View {
        let clash = pipelineManager.conflicts(with: pipeline).first
        VStack(alignment: .leading, spacing: 8) {
            Row(
                title: pipeline.name,
                subtitle: clash.map {
                    T("⚠︎ Та же клавиша, что у «\($0.name)» — выбери другую",
                      "⚠︎ Same key as “\($0.name)” — pick another one")
                } ?? "\(pipeline.trigger.title) · \(pipeline.sttEngine.title)",
                first: first
            ) {
                Toggle("", isOn: pipelineBinding(pipeline, \.enabled))
                    .toggleStyle(WisprToggleStyle())
            }

            if pipeline.enabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(T("Клавиша:", "Key:"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 62, alignment: .leading)

                        WisprDropdown(
                            selection: pipelineBinding(pipeline, \.trigger),
                            options: Self.triggerOptions
                        ) { trigger in
                            Text(trigger.title)
                        }
                    }

                    HStack(spacing: 10) {
                        Text(T("Действие:", "Action:"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 62, alignment: .leading)

                        WisprDropdown(
                            selection: pipelineBinding(pipeline, \.postProcessing),
                            options: PostProcessingMode.allCases
                        ) { mode in
                            Text(mode.title)
                        }
                    }

                    // Строка «Движок» убрана: STTEngineType — enum с единственным
                    // кейсом (локальный Whisper), выбирать больше не из чего.
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Последние ответы

    /// Ответ вставляется под курсор и исчезает. Если поле оказалось не тем —
    /// или ответ хочется перепроверить моделью посильнее — доставать его
    /// было неоткуда.
    private var recentCard: some View {
        Card(header: T("ПОСЛЕДНИЕ ОТВЕТЫ", "RECENT ANSWERS")) {
            ForEach(Array(controller.recentAnswers.prefix(3).enumerated()), id: \.element.id) { index, item in
                Row(title: item.question,
                    subtitle: item.answer,
                    first: index == 0) {
                    HStack(spacing: 8) {
                        Text(item.model)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                        PillButton(title: copiedID == item.id ? T("Скопировано", "Copied") : T("Копировать", "Copy"),
                                   icon: copiedID == item.id ? .copied : .copy,
                                   tone: copiedID == item.id ? .success : nil) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.answer, forType: .string)
                            copiedID = item.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedID == item.id { copiedID = nil }
                            }
                        }
                        PillButton(title: T("Переспросить", "Ask again"), icon: .refresh) {
                            controller.askAgain(item.question)
                        }
                        .disabled(controller.state != .idle)
                        .opacity(controller.state == .idle ? 1 : 0.45)
                    }
                }
            }
        }
    }
}
