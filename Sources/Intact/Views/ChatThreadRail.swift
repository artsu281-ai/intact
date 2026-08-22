import SwiftUI

/// Список диалогов слева от чата.
///
/// Ветку можно открыть, переименовать двойным щелчком и удалить. Активная
/// подсвечена; свежие сверху — порядок задаёт сам сервис при каждом ответе.
struct ChatThreadRail: View {
    @ObservedObject private var chat = AIChatService.shared
    @State private var renamingID: UUID? = nil
    @State private var draftTitle: String = ""
    @FocusState private var renameFocused: Bool

    static let width: CGFloat = 236

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(chat.threads) { thread in
                        row(thread)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .frame(width: Self.width)
        .background(Palette.sidebar)
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("ЧАТЫ", "CHATS"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .kerning(0.8)

            Button {
                chat.newThread()
            } label: {
                HStack(spacing: 7) {
                    IntactIcon(kind: .plus, size: 13, weight: .medium)
                    Text(T("Новый чат", "New chat"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.accent.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Palette.accent.opacity(0.20), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Строка ветки

    @ViewBuilder
    private func row(_ thread: ChatThread) -> some View {
        let isActive = thread.id == chat.activeThreadID

        if renamingID == thread.id {
            TextField("", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($renameFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Palette.accent.opacity(0.5), lineWidth: 1)
                        )
                )
                .onSubmit { commitRename(thread.id) }
                .onChange(of: renameFocused) { _, focused in
                    if !focused { commitRename(thread.id) }
                }
        } else {
            ChatThreadRow(
                thread: thread,
                isActive: isActive,
                onOpen: { chat.select(thread.id) },
                onRename: {
                    draftTitle = thread.title
                    renamingID = thread.id
                    renameFocused = true
                },
                onDelete: { chat.delete(thread.id) }
            )
        }
    }

    private func commitRename(_ id: UUID) {
        guard renamingID == id else { return }
        chat.rename(id, to: draftTitle)
        renamingID = nil
    }
}

private struct ChatThreadRow: View {
    let thread: ChatThread
    let isActive: Bool
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(thread.title)
                        .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? Palette.textPrimary : Palette.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(Self.dateText(thread.updatedAt))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                        if let model = thread.modelLabel {
                            Text("·").foregroundStyle(Palette.textTertiary).font(.system(size: 11))
                            Text(model)
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                if hovering {
                    Button(action: onDelete) {
                        IntactIcon(kind: .clearAll, size: 12)
                            .foregroundStyle(Palette.iconMuted)
                            .padding(3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(T("Удалить чат", "Delete chat"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Palette.selected : (hovering ? Palette.hover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onRename() })
        .contextMenu {
            Button(T("Переименовать", "Rename"), action: onRename)
            Button(T("Удалить", "Delete"), role: .destructive, action: onDelete)
        }
    }

    /// «15:24» для сегодняшних, «вчера», дальше — дата.
    private static func dateText(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            return T("вчера", "yesterday")
        } else {
            formatter.dateFormat = "d MMM"
        }
        return formatter.string(from: date)
    }
}
