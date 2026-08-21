import AppKit
import SwiftUI

struct IndicatorView: View {
    @ObservedObject var controller: DictationController

    static let width: CGFloat = 470
    static let listeningSize = NSSize(width: 380, height: 58)
    private static let pad: CGFloat = 20
    private static let bodyFont = NSFont.systemFont(ofSize: 15)

    /// Высота считается по реальному тексту: fittingSize у NSHostingView
    /// до попадания в окно врёт, а фиксированная высота оставляла пустую полосу.
    static func copySize(for text: String) -> NSSize {
        NSSize(width: width, height: pad + 22 + 14 + textHeight(text) + 16 + 30 + pad)
    }

    static func textHeight(_ text: String) -> CGFloat {
        let lineHeight = ceil(bodyFont.boundingRectForFont.height) + 3
        let box = (text as NSString).boundingRect(
            with: NSSize(width: width - pad * 2, height: lineHeight * 3),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: bodyFont])
        return min(ceil(box.height), lineHeight * 3)
    }

    var body: some View {
        Group {
            if let pending = controller.pendingText {
                noPlaceToInsert(text: pending)
            } else {
                listening
            }
        }
        .padding(Self.pad)
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var size: NSSize {
        if let pending = controller.pendingText { return Self.copySize(for: pending) }
        return Self.listeningSize
    }

    // MARK: - Идёт запись

    private var listening: some View {
        HStack(spacing: 12) {
            switch controller.state {
            case .recording:
                Image(systemName: "mic.fill")
                    .foregroundStyle(.white.opacity(0.85))
                    .font(.system(size: 14, weight: .medium))
                Waveform(samples: controller.waveform)
                    .frame(height: 30)
            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Распознаю…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            case .idle:
                EmptyView()
            }
        }
    }

    // MARK: - Вставлять некуда

    private func noPlaceToInsert(text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer(minLength: 12)

                Text("Поставь курсор в поле и продиктуй снова")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)

                CircleIconButton(symbol: "xmark") { controller.dismissPending() }
            }
            .frame(height: 22)

            Spacer().frame(height: 14)

            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.95))
                .lineSpacing(3)
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.textHeight(text), alignment: .top)

            Spacer().frame(height: 16)

            HStack {
                Spacer()
                SoftButton(title: "Скопировать", symbol: "doc.on.doc") {
                    controller.copyPending()
                }
            }
            .frame(height: 30)
        }
    }
}

/// Свои кнопки вместо системных: в неактивной панели те рисуются серыми
/// и выглядят сломанными, а вид не должен зависеть от того, какое окно активно.
struct SoftButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.26 : 0.16)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct CircleIconButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.6))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.22 : 0.12)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Бегущая волна: новые отсчёты вплывают справа, старые уходят влево.
/// Тишина остаётся точками, громкая речь вытягивается в высокие штрихи —
/// сразу видно, что микрофон слышит именно голос, а не шум.
struct Waveform: View {
    let samples: [Float]
    var color: Color = Color(red: 0.36, green: 0.62, blue: 1.0)
    var bars: Int = 48

    var body: some View {
        Canvas { context, size in
            let slot = size.width / CGFloat(bars)
            let width = max(2, slot * 0.44)
            let middle = size.height / 2

            for i in 0..<bars {
                let index = samples.count - bars + i
                let value = (index >= 0 && index < samples.count) ? CGFloat(samples[index]) : 0

                // Минимум — точка размером в толщину штриха.
                let height = max(width, value * size.height)
                let x = CGFloat(i) * slot + (slot - width) / 2
                let rect = CGRect(x: x, y: middle - height / 2, width: width, height: height)

                context.fill(Path(roundedRect: rect, cornerRadius: width / 2),
                             with: .color(color.opacity(0.35 + 0.65 * min(1, value * 3))))
            }
        }
        .animation(.linear(duration: 0.05), value: samples.count)
    }
}

/// Плавающая панель поверх всех окон.
///
/// Во время записи она не должна перехватывать клики, а когда показывает
/// кнопку «Скопировать» — обязана, поэтому пересоздаётся при смене режима.
final class IndicatorPanel {
    private var panel: NSPanel?
    private var isInteractive = false

    func show(controller: DictationController, interactive: Bool = false) {
        if panel != nil, interactive == isInteractive { return }
        hide()

        let hosting = NSHostingView(rootView: IndicatorView(controller: controller))
        let size = interactive
            ? IndicatorView.copySize(for: controller.pendingText ?? "")
            : IndicatorView.listeningSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let p = KeyablePanel(contentRect: hosting.frame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.acceptsKey = interactive
        p.contentView = hosting
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = !interactive
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        reposition(p)
        // Фокус у чужого приложения не отнимаем: кнопки нарисованы своими стилями
        // и не зависят от того, активно окно или нет.
        p.orderFrontRegardless()

        panel = p
        isInteractive = interactive
    }

    private func reposition(_ p: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = p.frame.size
        let visible = screen.visibleFrame
        p.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                 y: visible.minY + 90))
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        isInteractive = false
    }
}

/// Обычная NSPanel не становится активной; здесь это включаемо,
/// чтобы работал Enter на кнопке по умолчанию.
final class KeyablePanel: NSPanel {
    var acceptsKey = false
    override var canBecomeKey: Bool { acceptsKey }
}
