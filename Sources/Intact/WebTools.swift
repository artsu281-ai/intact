import Foundation

/// Доступ в интернет для локальной модели — через собственный контейнер SearXNG
/// (см. ~/searxng, поднят через Docker/Colima), а не через сторонний API с ключом
/// или платной подпиской. Агрегирует Google/Bing/Brave/DuckDuckGo и ещё десяток
/// движков одним запросом, работает только на 127.0.0.1 — наружу не торчит.
enum WebTools {
    static let searxngURL = "http://127.0.0.1:8888"

    struct SearchResultItem {
        let title: String
        let url: String
        let content: String
    }

    /// Описания инструментов в формате, который понимает llama-server
    /// (OpenAI-совместимое поле `tools` в /v1/chat/completions).
    static let toolDefinitions: [[String: Any]] = [
        [
            "type": "function",
            "function": [
                "name": "web_search",
                "description": "Искать в интернете по запросу и получить список ссылок с краткими описаниями.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "поисковый запрос"]
                    ],
                    "required": ["query"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "fetch_page",
                "description": "Открыть страницу по точному URL и получить её текстовое содержимое.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "url": ["type": "string", "description": "полный URL страницы, включая https://"]
                    ],
                    "required": ["url"]
                ]
            ]
        ]
    ]

    static func search(query: String, completion: @escaping (String) -> Void) {
        var comps = URLComponents(string: "\(searxngURL)/search")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = comps.url else { completion("Ошибка: некорректный запрос."); return }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, error in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]], !results.isEmpty else {
                completion("Поиск не дал результатов или локальный поисковый сервер (SearXNG в Docker) недоступен.")
                return
            }
            let lines = results.prefix(6).map { r -> String in
                let title = (r["title"] as? String) ?? ""
                let content = (r["content"] as? String) ?? ""
                let link = (r["url"] as? String) ?? ""
                return "- \(title): \(content) (\(link))"
            }
            completion(lines.joined(separator: "\n"))
        }.resume()
    }

    static func fetchPage(urlString: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: urlString), let scheme = url.scheme, scheme.hasPrefix("http") else {
            completion("Ошибка: некорректный URL.")
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Mozilla/5.0 (compatible; IntactBot/1.0)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, error in
            guard let data, let html = String(data: data, encoding: .utf8) else {
                completion("Не удалось загрузить страницу: \(error?.localizedDescription ?? "неизвестная ошибка").")
                return
            }
            completion(Self.stripHTML(html))
        }.resume()
    }

    /// Грубая, но достаточная для чтения статьи очистка HTML: без специального
    /// парсера, только вырезание тегов/скриптов и декодирование частых сущностей —
    /// проект принципиально не тянет новые зависимости.
    private static func stripHTML(_ html: String) -> String {
        var text = html
        for tag in ["script", "style", "noscript", "svg"] {
            text = text.replacingOccurrences(of: "<\(tag)[^>]*>.*?</\(tag)>",
                                             with: " ", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(6000))
    }
}
