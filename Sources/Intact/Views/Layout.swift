import SwiftUI

// MARK: - Ширина контента
//
// До этого единственным правилом вёрстки был отступ в 40 pt по краям, поэтому
// на широком окне строка чата, поле ввода и списки растягивались на полторы
// тысячи пикселей. Длина строки — часть типографики, а не следствие размера окна.

enum Layout {
    /// Читаемая колонка: диалог, поле ввода, строки настроек и истории.
    /// Дальше строка становится слишком длинной, чтобы глаз находил её начало.
    static let reading: CGFloat = 880

    /// Широкая колонка для сеток карточек, где длина строки не решает.
    static let wide: CGFloat = 1200

    /// Отступ от края окна. Общий для всех экранов.
    static let gutter: CGFloat = 40
}

/// Ограничивает содержимое по ширине и прижимает его к левому краю —
/// так контент остаётся пристыкованным к боковому меню и не «уплывает»
/// на широком экране.
struct ContentColumn<Content: View>: View {
    // Подписка на тему: см. `ThemeReader` в Theme.swift. Без неё вид
    // останется в старых цветах при смене темы. Не удалять как неиспользуемое.
    @ThemeReader var themeStamp

    var maxWidth: CGFloat = Layout.reading
    var gutter: CGFloat = Layout.gutter
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
