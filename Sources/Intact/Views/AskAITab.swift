import SwiftUI

/// Экран «Спросите ИИ»: второй, независимый от диктовки хоткей — держишь клавишу,
/// задаёшь вопрос голосом, и вместо причёсанного текста вставляется прямой ответ ИИ.
/// Вынесено отдельным пунктом сайдбара из вкладки «Диктовка», чтобы фичу было проще найти.
struct AskAITab: View {
    @ObservedObject var settings: AppSettings
    var onOpenSection: ((SettingsSection) -> Void)? = nil

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
                Text("Отдельный хоткей, который не диктует, а спрашивает")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Держишь клавишу, говоришь вопрос или просьбу — приложение отправляет сказанное в ИИ и сразу вставляет прямой ответ вместо обычной диктовки, без вступлений и лишних слов.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 2)

            if !aiReady {
                Card(header: nil) {
                    Row(title: "ИИ ещё не настроен",
                        subtitle: "Хоткей сработает только после выбора модели — локальной или облачной",
                        first: true) {
                        PillButton(title: "Настроить ИИ", icon: .settingsPage) {
                            onOpenSection?(.settings)
                        }
                    }
                }
            }

            // Выбор модели прямо здесь: у быстрого ответа свои требования —
            // он должен успеть, пока человек ждёт текст под курсором, — и они
            // не совпадают с тем, что нужно чату.
            Card(header: "МОДЕЛЬ") {
                AIRoleRow(role: .quickAnswer, first: true,
                          onOpenSettings: { onOpenSection?(.settings) },
                          onOpenModels: { onOpenSection?(.models) })
            }

            Card(header: "ХОТКЕЙ") {
                Row(title: "Отдельный хоткей для вопросов",
                    subtitle: "Держишь клавишу, спрашиваешь — вместо диктовки вставится ответ ИИ",
                    first: true) {
                    Toggle("", isOn: $settings.enableAIHotkey)
                        .toggleStyle(WisprToggleStyle())
                }
                if settings.enableAIHotkey {
                    Row(title: "Клавиша",
                        subtitle: triggerKeysCollide
                            ? "⚠︎ Пересекается с клавишей обычной диктовки (\(settings.triggerKey.title)) — выбери другую"
                            : "Удерживай во время вопроса, как основной хоткей диктовки") {
                        WisprDropdown(selection: $settings.aiTriggerKey,
                                      options: TriggerKey.allCases) { key in
                            Text(key.title)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("НАПРИМЕР")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.leading, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("«Сколько будет 24 умножить на 17» → 408")
                    Text("«Столица Австралии» → Канберра")
                    Text("«Напиши короткое поздравление с днём рождения» → готовый текст")
                }
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
            }
        }
    }
}
