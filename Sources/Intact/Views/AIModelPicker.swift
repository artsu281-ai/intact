import SwiftUI

/// Выбор версии ИИ прямо из чата.
///
/// Раньше сменить модель можно было только через раздел настроек, а шапка чата
/// показывала имя файла. Здесь один список: установленные локальные модели
/// и облачные модели Anthropic, с честной пометкой, что куда уходит.
struct AIModelPicker: View {
    var onOpenSettings: () -> Void
    var onOpenModels: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var llmModels = LLMModelManager.shared
    @State private var isOpen = false
    @State private var hovering = false

    private var current: AIModelChoice { AIModelCatalog.current }
    private var cloudReady: Bool { CloudAIProvider.shared.isReady }

    private var statusColor: Color {
        switch settings.aiProviderKind {
        case .none:  return Palette.iconMuted
        case .local: return LocalAIProvider.shared.isReady ? Palette.iconSuccess : Palette.iconWarning
        case .cloud: return cloudReady ? Palette.iconSuccess : Palette.iconWarning
        }
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                Text(AIModelCatalog.title(for: current))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)

                if let placement = AIModelCatalog.placement(for: current) {
                    Text(placement)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Palette.pill))
                }

                IntactIcon(kind: isOpen ? .chevronUp : .chevronDown, size: 8)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering || isOpen ? Palette.pillHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Сменить версию ИИ")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { picker }
    }

    // MARK: - Список

    private var picker: some View {
        VStack(alignment: .leading, spacing: 4) {
            let installed = llmModels.installed

            if !installed.isEmpty {
                sectionHeader("Локально · не покидает Mac")
                ForEach(installed) { model in
                    row(choice: .local(model.filename),
                        title: model.title,
                        subtitle: "\(model.quant) · \(sizeText(model.sizeMB))",
                        enabled: true)
                }
            }

            sectionHeader(installed.isEmpty ? "Локально" : "Облако Anthropic")

            if installed.isEmpty {
                hint("Ни одна локальная модель не установлена") { onOpenModels() }
                sectionHeader("Облако Anthropic")
            }

            ForEach(AIModelCatalog.cloud) { model in
                row(choice: .cloud(model.id),
                    title: model.title,
                    subtitle: model.note,
                    enabled: cloudReady)
            }

            if !cloudReady {
                hint("Нужен ключ Anthropic API") { onOpenSettings() }
            }

            Divider().overlay(Palette.hairline).padding(.vertical, 3)

            row(choice: .disabled, title: "Выключить ИИ",
                subtitle: "Диктовка продолжит работать", enabled: true)
        }
        .padding(7)
        .frame(width: 330)
        .background(Palette.card)
    }

    private func row(choice: AIModelChoice, title: String, subtitle: String, enabled: Bool) -> some View {
        WisprDropdownItemRow(
            isSelected: current == choice,
            action: {
                guard enabled else { return }
                AIModelCatalog.apply(choice)
                isOpen = false
            }
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(enabled ? Palette.textPrimary : Palette.iconMuted)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(enabled ? 1 : 0.5)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.textTertiary)
            .kerning(0.6)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func hint(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                IntactIcon(kind: .warning, size: 13)
                Text(text)
                    .font(.system(size: 11.5))
                Spacer(minLength: 0)
                IntactIcon(kind: .chevronRight, size: 9)
            }
            .foregroundStyle(Palette.iconWarning)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sizeText(_ mb: Int) -> String {
        mb >= 1000 ? String(format: "%.1f ГБ", Double(mb) / 1000.0) : "\(mb) МБ"
    }
}
