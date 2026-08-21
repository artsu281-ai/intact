import AppKit
import SwiftUI

/// Палитра и дизайн-система в эстетике Wispr Flow.
///
/// Тёплые бежево-песочные тона, благородная типографика с засечками (Serif)
/// для заголовков, мягкие скругленные карточки, кастомные минималистичные
/// переключатели-таблетки и аккуратные бейджи хоткеев.
enum Palette {
    // Основные фоны (Oatmeal Linen & Warm Canvas)
    static let page           = dynamic(light: (0.980, 0.965, 0.941), dark: (0.086, 0.082, 0.078)) // #FAF6F0
    static let sidebar        = dynamic(light: (0.949, 0.922, 0.878), dark: (0.118, 0.114, 0.110)) // #F2EBE0
    static let card           = dynamic(light: (0.996, 0.992, 0.984), dark: (0.145, 0.141, 0.137)) // #FCFAF6
    static let cardHighlight  = dynamic(light: (0.957, 0.925, 0.882), dark: (0.185, 0.180, 0.175)) // #F4ECE1
    static let pill           = dynamic(light: (0.929, 0.898, 0.847), dark: (0.205, 0.200, 0.192)) // #EDE5D8
    static let pillHover      = dynamic(light: (0.894, 0.855, 0.796), dark: (0.260, 0.252, 0.245)) // #E4DACB
    static let dropdownBg     = dynamic(light: (0.996, 0.992, 0.984), dark: (0.170, 0.165, 0.160))

    // Брендовый терракотовый акцент (Terracotta Clay)
    static let accent         = dynamic(light: (0.780, 0.435, 0.318), dark: (0.900, 0.580, 0.460)) // #C76F51
    static let accentHover    = dynamic(light: (0.720, 0.375, 0.260), dark: (0.940, 0.640, 0.520))

    // Типографика (Deep Espresso & Warm Cocoa Slate)
    static let textPrimary    = dynamic(light: (0.133, 0.110, 0.094), dark: (0.975, 0.968, 0.952)) // #221C18
    static let textSecondary  = dynamic(light: (0.459, 0.416, 0.365), dark: (0.680, 0.665, 0.640)) // #756A5D
    static let textTertiary   = dynamic(light: (0.620, 0.576, 0.522), dark: (0.480, 0.465, 0.445)) // #9E9385

    // Разделители и состояния
    static let hairline       = dynamicAlpha(light: (0.50, 0.40, 0.30, 0.14), dark: (1, 1, 1, 0.08))
    static let selected       = dynamicAlpha(light: (0.780, 0.435, 0.318, 0.12), dark: (1, 1, 1, 0.10))
    static let hover          = dynamicAlpha(light: (0.50, 0.40, 0.30, 0.06), dark: (1, 1, 1, 0.055))

    // Переключатели
    static let toggleOn       = dynamic(light: (0.780, 0.435, 0.318), dark: (0.880, 0.550, 0.430)) // #C76F51
    static let toggleOff      = dynamic(light: (0.860, 0.825, 0.780), dark: (0.245, 0.240, 0.230))
    static let toggleKnob     = dynamic(light: (1.000, 1.000, 1.000), dark: (0.110, 0.105, 0.100))

    // HUD Pill (плавающий мини-индикатор записи и тосты)
    static func hudBg(isDark: Bool) -> Color {
        isDark ? Color(red: 0.095, green: 0.090, blue: 0.086).opacity(0.94)
               : Color(red: 0.957, green: 0.925, blue: 0.882).opacity(0.96) // #F4ECE1
    }

    static func hudBorder(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.14)
               : Color(red: 0.50, green: 0.40, blue: 0.30).opacity(0.18)
    }

    static func hudShadow(isDark: Bool) -> Color {
        isDark ? Color.black.opacity(0.40)
               : Color(red: 0.35, green: 0.25, blue: 0.15).opacity(0.14)
    }

    static func hudIcon(isDark: Bool) -> Color {
        isDark ? Color(red: 0.98, green: 0.95, blue: 0.91)
               : Color(red: 0.780, green: 0.435, blue: 0.318) // Terracotta accent icon
    }

    static func hudText(isDark: Bool) -> Color {
        isDark ? Color(red: 0.98, green: 0.95, blue: 0.91)
               : Color(red: 0.133, green: 0.110, blue: 0.094)
    }

    static func hudTextMuted(isDark: Bool) -> Color {
        isDark ? Color(red: 0.80, green: 0.76, blue: 0.72)
               : Color(red: 0.459, green: 0.416, blue: 0.365)
    }

    static func hudEqTop(isDark: Bool) -> Color {
        isDark ? Color(red: 0.98, green: 0.94, blue: 0.90)
               : Color(red: 0.780, green: 0.435, blue: 0.318) // Terracotta #C76F51
    }

    static func hudEqBottom(isDark: Bool) -> Color {
        isDark ? Color(red: 0.86, green: 0.62, blue: 0.49)
               : Color(red: 0.900, green: 0.580, blue: 0.460)
    }

    private static func dynamic(light: (CGFloat, CGFloat, CGFloat),
                                dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        dynamicAlpha(light: (light.0, light.1, light.2, 1), dark: (dark.0, dark.1, dark.2, 1))
    }

    private static func dynamicAlpha(light: (CGFloat, CGFloat, CGFloat, CGFloat),
                                     dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
    }
}

/// Кастомный минималистичный переключатель в стиле Wispr Flow.
struct WisprToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                    configuration.isOn.toggle()
                }
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(configuration.isOn ? Palette.toggleOn : Palette.toggleOff)
                        .frame(width: 44, height: 26)

                    Circle()
                        .fill(Palette.toggleKnob)
                        .frame(width: 20, height: 20)
                        .padding(3)
                        .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// Страница раздела: крупный заголовок с засечками и прокручиваемое содержимое.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 32, weight: .regular, design: .serif))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 40)
                .padding(.top, 46)
                .padding(.bottom, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    content
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.page)
    }
}

/// Карточка с заголовком: мягкий фон, скругленные углы, разделители-волоски.
struct Card<Content: View>: View {
    var header: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header {
                Text(header.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .kerning(0.8)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) {
                content
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
        }
    }
}

/// Строка карточки: название, пояснение под ним, управляющий элемент справа.
struct Row<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    var first: Bool = false
    @ViewBuilder var control: Control

    var body: some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                    .padding(.leading, 22)
            }
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 14)
                control
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
    }
}

/// Кнопка-таблетка в правой части строки (в стиле кнопки "Change" из Wispr Flow).
struct PillButton: View {
    let title: String
    var symbol: String? = nil
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 7.5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? Palette.pillHover : Palette.pill)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Бейдж горячей клавиши (например, ⌥ Opt, ⌘V).
struct KeyCapBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Palette.pill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
            )
    }
}

/// Элегантный выпадающий список в стиле Wispr Flow (кнопка с текущим значением и chevron).
struct WisprDropdown<T: Hashable, Label: View>: View {
    @Binding var selection: T
    let options: [T]
    @ViewBuilder let label: (T) -> Label
    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    label(item)
                }
            }
        } label: {
            HStack(spacing: 8) {
                label(selection)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Palette.pillHover : Palette.dropdownBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
    }
}

/// Ползунок в правой части строки — с аккуратной подписью значения.
struct SliderControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let caption: String

    var body: some View {
        HStack(spacing: 12) {
            Slider(value: $value, in: range, step: step)
                .frame(width: 170)
                .tint(Palette.toggleOn)
            Text(caption)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 58, alignment: .trailing)
        }
    }
}
