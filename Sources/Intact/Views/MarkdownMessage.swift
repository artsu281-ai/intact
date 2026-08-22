import AppKit
import SwiftUI

// MARK: - Разбор ответа
//
// Системный промпт просит модель отвечать разметкой Markdown, и она это делает —
// но раньше ответ показывался одним куском обычного текста: заголовки выглядели
// решётками, а код нельзя было забрать иначе, чем выделив мышью.

/// Кусок ответа: обычный текст или блок кода в тройных кавычках.
enum MessageBlock: Identifiable {
    case prose(id: Int, text: String)
    case code(id: Int, language: String?, code: String)

    var id: Int {
        switch self {
        case .prose(let id, _):   return id
        case .code(let id, _, _): return id
        }
    }
}

enum MessageParser {

    /// Делит ответ по строкам с тройными кавычками.
    ///
    /// Незакрытая кавычка — обычное дело для потоковой генерации, поэтому
    /// «хвост» после последней открывающей всё равно отдаётся как код.
    static func blocks(from raw: String) -> [MessageBlock] {
        var result: [MessageBlock] = []
        var buffer: [Substring] = []
        var codeLanguage: String? = nil
        var inCode = false
        var nextID = 0

        func flush() {
            let text = buffer.joined(separator: "\n")
            buffer.removeAll()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            if inCode {
                result.append(.code(id: nextID, language: codeLanguage, code: text
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))))
            } else {
                result.append(.prose(id: nextID, text: trimmed))
            }
            nextID += 1
        }

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flush()
                if !inCode {
                    let tag = line.trimmingCharacters(in: .whitespaces).dropFirst(3)
                        .trimmingCharacters(in: .whitespaces)
                    codeLanguage = tag.isEmpty ? nil : tag
                }
                inCode.toggle()
                continue
            }
            buffer.append(line)
        }
        flush()

        // Ответ без разметки вообще — один блок текста.
        if result.isEmpty {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(.prose(id: 0, text: trimmed)) }
        }
        return result
    }
}

// MARK: - Отрисовка ответа

/// Ответ ассистента с разобранной разметкой: заголовки, списки, выделения
/// и блоки кода, каждый со своей кнопкой копирования.
struct MarkdownMessage: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(MessageParser.blocks(from: text)) { block in
                switch block {
                case .prose(_, let value):
                    ProseBlock(text: value)
                case .code(_, let language, let code):
                    CodeBlock(language: language, code: code)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Текстовая часть

private struct ProseBlock: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(for: line)
            }
        }
    }

    private var lines: [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    @ViewBuilder
    private func row(for raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)

        if line.isEmpty {
            Color.clear.frame(height: 3)
        } else if let level = headingLevel(line) {
            Text(inline(String(line.dropFirst(level + 1))))
                .font(.system(size: level == 1 ? 17 : (level == 2 ? 15.5 : 14.5), weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 2)
        } else if let bullet = bulletContent(line) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.accent)
                body(inline(bullet))
            }
            .padding(.leading, 2)
        } else if let (number, content) = numberedContent(line) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.accent)
                body(inline(content))
            }
            .padding(.leading, 2)
        } else {
            body(inline(line))
        }
    }

    private func body(_ value: AttributedString) -> some View {
        Text(value)
            .font(.system(size: 14))
            .foregroundStyle(Palette.textPrimary)
            .lineSpacing(3.5)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Разбор строки

    private func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...4).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return hashes
    }

    private func bulletContent(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private func numberedContent(_ line: String) -> (Int, String)? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return (number, String(rest.dropFirst(2)))
    }

    /// Жирный, курсив, ссылки и `код` внутри строки.
    ///
    /// Разбираем только строчную разметку: блочную (списки, заголовки) мы уже
    /// разобрали сами, а встроенный парсер схлопнул бы переносы строк.
    private func inline(_ source: String) -> AttributedString {
        guard var attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return AttributedString(source)
        }

        // Фон под текстовым фрагментом SwiftUI не рисует, поэтому `код`
        // выделяем моноширинным начертанием и акцентным цветом.
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].font = .system(size: 13, design: .monospaced)
            attributed[run.range].foregroundColor = Palette.accent
        }
        return attributed
    }
}

// MARK: - Блок кода

/// Код с заголовком, языком и копированием в одно нажатие.
private struct CodeBlock: View {
    let language: String?
    let code: String

    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Palette.hairline)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.dropdownBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(language?.uppercased() ?? T("КОД", "CODE"))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
                .kerning(0.6)

            Spacer(minLength: 8)

            Button(action: copy) {
                HStack(spacing: 5) {
                    IntactIcon(kind: copied ? .copied : .copy, size: 12)
                    Text(copied ? T("Скопировано", "Copied") : T("Копировать", "Copy"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(copied ? Palette.accent : Palette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(copied ? Palette.accent.opacity(0.10) : (hovering ? Palette.pill : Color.clear))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(T("Скопировать этот блок кода", "Copy this code block"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.pill.opacity(0.5))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
    }
}
