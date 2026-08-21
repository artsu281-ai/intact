import AppKit
import SwiftUI

struct IndicatorView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var settings = AppSettings.shared

    static let width: CGFloat = 420
    static let listeningSize = NSSize(width: 156, height: 40)
    private static let copyPad: CGFloat = 16
    private static let bodyFont = NSFont.systemFont(ofSize: 14)

    static func copySize(for text: String) -> NSSize {
        NSSize(width: width, height: copyPad + 20 + 12 + textHeight(text) + 14 + 28 + copyPad)
    }

    static func textHeight(_ text: String) -> CGFloat {
        let lineHeight = ceil(bodyFont.boundingRectForFont.height) + 3
        let box = (text as NSString).boundingRect(
            with: NSSize(width: width - copyPad * 2, height: lineHeight * 3),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: bodyFont])
        return min(ceil(box.height), lineHeight * 3)
    }

    var body: some View {
        Group {
            if let pending = controller.pendingText {
                noPlaceToInsert(text: pending)
                    .padding(Self.copyPad)
                    .frame(width: Self.copySize(for: pending).width,
                           height: Self.copySize(for: pending).height)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.18), radius: 16, y: 6)
                    )
            } else {
                listening
                    .padding(.horizontal, 14)
                    .frame(width: Self.listeningSize.width, height: Self.listeningSize.height)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.88))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                            )
                            .shadow(color: Color.black.opacity(0.22), radius: 12, y: 4)
                    )
            }
        }
        .preferredColorScheme(settings.appTheme.colorScheme)
    }

    // MARK: - Компактный эстетичный спектр и индикатор записи

    private var listening: some View {
        HStack(spacing: 8) {
            switch controller.state {
            case .recording:
                Image(systemName: "mic.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                CompactEqualizer(level: controller.level)
                    .frame(width: 34, height: 16)

                Spacer(minLength: 0)

                Text(controller.elapsedText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))

            case .transcribing:
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)

                Text("Распознаю…")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
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
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary)

                Spacer(minLength: 8)

                Text("Поставьте курсор в поле ввода")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)

                CircleIconButton(symbol: "xmark") { controller.dismissPending() }
            }
            .frame(height: 20)

            Spacer().frame(height: 12)

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary)
                .lineSpacing(3)
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.textHeight(text), alignment: .top)

            Spacer().frame(height: 14)

            HStack {
                Spacer()
                SoftButton(title: "Скопировать", symbol: "doc.on.doc") {
                    controller.copyPending()
                }
            }
            .frame(height: 28)
        }
    }
}

// MARK: - Компактный анимированный эквалайзер

/// Короткий, ультра-эстетичный спектр из 5 живых анимированных столбиков,
/// реагирующих на громкость голоса в реальном времени.
struct CompactEqualizer: View {
    let level: Float

    var body: some View {
        HStack(spacing: 3) {
            EqualizerBar(index: 0, level: level, minH: 3, maxH: 10, weight: 0.6)
            EqualizerBar(index: 1, level: level, minH: 4, maxH: 15, weight: 0.9)
            EqualizerBar(index: 2, level: level, minH: 5, maxH: 18, weight: 1.0)
            EqualizerBar(index: 3, level: level, minH: 4, maxH: 15, weight: 0.85)
            EqualizerBar(index: 4, level: level, minH: 3, maxH: 10, weight: 0.55)
        }
    }
}

private struct EqualizerBar: View {
    let index: Int
    let level: Float
    let minH: CGFloat
    let maxH: CGFloat
    let weight: CGFloat

    private var calculatedHeight: CGFloat {
        let raw = CGFloat(max(0, min(1, level)))
        let h = minH + (maxH - minH) * (raw * weight * 1.8)
        return min(maxH, max(minH, h))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.95, blue: 0.98),
                        Color(red: 0.78, green: 0.84, blue: 0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 2.8, height: calculatedHeight)
            .animation(.spring(response: 0.12, dampingFraction: 0.65), value: calculatedHeight)
    }
}

// MARK: - Кнопки панели

struct SoftButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.primary.opacity(hovering ? 0.14 : 0.08))
            )
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
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(hovering ? 1.0 : 0.7))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.12 : 0.06)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Панель NSPanel

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
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = !interactive
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        reposition(p)
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

final class KeyablePanel: NSPanel {
    var acceptsKey = false
    override var canBecomeKey: Bool { acceptsKey }
}
