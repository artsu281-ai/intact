import Foundation

/// Минимальный клиент Anthropic Messages API. Ключ хранится только в Keychain,
/// никогда в UserDefaults.
final class CloudAIProvider: AIProvider {
    static let shared = CloudAIProvider()
    static let keychainService = "com.artsu.intact.anthropic-api-key"

    private init() {}

    var isReady: Bool {
        !(KeychainHelper.get(service: Self.keychainService) ?? "").isEmpty
    }

    func complete(messages: [AIMessage], maxTokens: Int, completion: @escaping (Result<String, AIError>) -> Void) {
        guard let apiKey = KeychainHelper.get(service: Self.keychainService), !apiKey.isEmpty else {
            completion(.failure(.notConfigured))
            return
        }

        let model = AppSettings.shared.aiCloudModel
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            completion(.failure(.badResponse))
            return
        }

        let systemPrompt = messages.first(where: { $0.role == .system })?.content
        let chatMessages = messages.filter { $0.role != .system }.map {
            ["role": $0.role.rawValue, "content": $0.content]
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": chatMessages
        ]
        if let systemPrompt, !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Модели с рассуждением отвечают дольше простых: на сложной сводке
        // двадцати секунд не хватает, и запрос обрывался посреди ответа.
        req.timeoutInterval = 120
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                completion(.failure((error as NSError).code == NSURLErrorTimedOut ? .timeout : .network(error)))
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.badResponse))
                return
            }

            // Отказ приходит обычным 200 и без текстового блока. Без этой
            // ветки он выглядел бы как «некорректный ответ от AI».
            if json["stop_reason"] as? String == "refusal" {
                let explanation = (json["stop_details"] as? [String: Any])?["explanation"] as? String
                completion(.failure(.refused(explanation)))
                return
            }

            // Блоки рассуждения идут перед ответом — берём именно текстовый.
            guard let content = json["content"] as? [[String: Any]],
                  let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String else {
                completion(.failure(.badResponse))
                return
            }
            completion(.success(text))
        }.resume()
    }
}
