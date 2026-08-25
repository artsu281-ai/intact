import Foundation

/// Одна «версия ИИ», которую можно выбрать в разделе приложения.
/// Доступны только нативные приложения на Mac и локальные офлайн-модели (0 API токенов).
enum AIModelChoice: Hashable, Identifiable {
    case disabled
    /// Десктопное приложение Gemini на Mac (0 токенов)
    case gemini
    /// Имя файла установленной GGUF-модели (офлайн)
    case local(String)

    var id: String {
        switch self {
        case .disabled:        return "disabled"
        case .gemini:          return "gemini:app"
        case .local(let file): return "local:\(file)"
        }
    }

    /// Разбор `id` обратно в выбор — так переопределение роли хранится
    /// в UserDefaults одной строкой, без отдельного Codable-слоя.
    init?(id: String) {
        if id == "disabled" { self = .disabled; return }
        if id == "gemini" || id == "gemini:app" { self = .gemini; return }
        if id.hasPrefix("local:") { self = .local(String(id.dropFirst("local:".count))); return }
        return nil
    }
}

enum AIModelCatalog {

    // MARK: - Текущий выбор

    /// Выбор «по умолчанию» — то, чем пользуются все разделы, у которых нет
    /// собственного переопределения.
    static var current: AIModelChoice {
        let settings = AppSettings.shared
        switch settings.aiProviderKind {
        case .none:
            return .disabled
        case .gemini:
            return .gemini
        case .local:
            let file = URL(fileURLWithPath: settings.aiLocalModelPath).lastPathComponent
            return file.isEmpty ? .disabled : .local(file)
        }
    }

    /// Что реально выполнит задачу этой роли.
    static func resolved(for role: AIRole) -> AIModelChoice {
        guard let raw = AppSettings.shared.aiRoleOverrides[role.rawValue],
              let choice = AIModelChoice(id: raw),
              isAvailable(choice) else { return current }
        return choice
    }

    /// Есть ли у роли собственный выбор, отличный от «по умолчанию».
    static func hasOverride(_ role: AIRole) -> Bool {
        guard let raw = AppSettings.shared.aiRoleOverrides[role.rawValue],
              let choice = AIModelChoice(id: raw) else { return false }
        return isAvailable(choice)
    }

    /// Существует ли выбранное физически: файл на диске для локальной модели,
    /// установленное приложение для Gemini.
    static func isAvailable(_ choice: AIModelChoice) -> Bool {
        switch choice {
        case .disabled:
            return true
        case .gemini:
            return GeminiBridgeService.isAppAvailable
        case .local(let filename):
            guard let match = LLMModel.matching(path: filename) else { return false }
            return match.model.isInstalled(match.quant)
        }
    }

    /// Путь к файлу локальной модели для выбора `.local`.
    static func localPath(for choice: AIModelChoice) -> String? {
        guard case .local(let filename) = choice,
              let match = LLMModel.matching(path: filename) else { return nil }
        return match.model.localURL(for: match.quant).path
    }

    // MARK: - Применение

    /// Применяет выбор как общий по умолчанию.
    @MainActor
    static func apply(_ choice: AIModelChoice) {
        let settings = AppSettings.shared
        switch choice {
        case .disabled:
            settings.aiProviderKind = .none
        case .gemini:
            settings.aiProviderKind = .gemini
        case .local(let filename):
            guard let match = LLMModel.matching(path: filename) else { return }
            settings.aiLocalModelPath = match.model.localURL(for: match.quant).path
            settings.aiProviderKind = .local
        }
    }

    /// Применяет выбор к одной роли. `nil` возвращает роль к общему умолчанию.
    @MainActor
    static func apply(_ choice: AIModelChoice?, to role: AIRole) {
        var overrides = AppSettings.shared.aiRoleOverrides
        if let choice {
            overrides[role.rawValue] = choice.id
        } else {
            overrides.removeValue(forKey: role.rawValue)
        }
        AppSettings.shared.aiRoleOverrides = overrides
    }

    // MARK: - Подписи

    /// Короткое имя для шапки раздела.
    static func title(for choice: AIModelChoice) -> String {
        switch choice {
        case .disabled:
            return T("ИИ выключен", "AI is off")
        case .gemini:
            return "Gemini"
        case .local(let filename):
            guard let match = LLMModel.matching(path: filename) else {
                return URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            }
            return LLMModel.displayName(model: match.model, quant: match.quant)
        }
    }

    /// Где именно выполняется модель: десктопное приложение или локально на Mac.
    static func placement(for choice: AIModelChoice) -> String? {
        switch choice {
        case .disabled: return nil
        case .gemini:   return T("Приложение", "App")
        case .local:    return T("Локально", "Local")
        }
    }
}
