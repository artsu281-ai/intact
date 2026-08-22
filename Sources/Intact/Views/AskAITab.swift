import AppKit
import SwiftUI

/// Экран «Спросите ИИ»: второй, независимый от диктовки хоткей — держишь клавишу,
/// задаёшь вопрос голосом, и вместо причёсанного текста вставляется прямой ответ ИИ.
/// Вынесено отдельным пунктом сайдбара из вкладки «Диктовка», чтобы фичу было проще найти.
struct AskAITab: View {
    @ObservedObject var settings: AppSettings
    var onOpenSection: ((SettingsSection) -> Void)? = nil

    @ObservedObject private var controller = DictationController.shared
    @State private var copiedID: UUID? = nil

    private var aiReady: Bool { AIRouter.shared.isReady(for: .quickAnswer) }

    /// Сравнение через `==` пропустило бы «Любой ⌥ Option» (по умолчанию у основной
    /// диктовки) против «Правый ⌥ Option» (по умолчанию у вопроса к ИИ) — разные
    /// значения enum, но физически одна и та же клавиша. Сверяем по кодам клавиш.
    private var triggerKeysCollide: Bool {
        guard settings.activationMode == .modifierHold else { return false }
        return !settings.triggerKey.keyCodes.isDisjoint(with: settings.aiTriggerKey.keyCodes)
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

            Card(header: T("ХОТКЕЙ", "HOTKEY")) {
                Row(title: T("Отдельный хоткей для вопросов", "Separate hotkey for questions"),
                    subtitle: T("Держишь клавишу, спрашиваешь — вместо диктовки вставится ответ ИИ", "Hold the key, ask — the AI's answer is inserted instead of dictation"),
                    first: true) {
                    Toggle("", isOn: $settings.enableAIHotkey)
                        .toggleStyle(WisprToggleStyle())
                }
                if settings.enableAIHotkey {
                    Row(title: T("Клавиша", "Key"),
                        subtitle: triggerKeysCollide
                            ? T("⚠︎ Пересекается с клавишей обычной диктовки (\(settings.triggerKey.title)) — выбери другую", "⚠︎ Clashes with the dictation key (\(settings.triggerKey.title)) — pick another")
                            : T("Удерживай во время вопроса, как основной хоткей диктовки", "Hold it while you ask, like the main dictation hotkey")) {
                        WisprDropdown(selection: $settings.aiTriggerKey,
                                      options: TriggerKey.allCases) { key in
                            Text(key.title)
                        }
                    }
                }
            }

            if !controller.recentAnswers.isEmpty {
                recentCard
            }

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
