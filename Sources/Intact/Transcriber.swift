import Foundation

enum TranscribeError: LocalizedError {
    case binaryMissing
    case modelMissing(String)
    case failed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "Не найден whisper-cli. Установи его: brew install whisper-cpp"
        case .modelMissing(let path):
            return "Модель не найдена: \(path)"
        case .failed(let code, let err):
            let tail = err.split(separator: "\n").suffix(3).joined(separator: " ")
            return "whisper-cli завершился с кодом \(code). \(tail)"
        }
    }
}

/// Обёртка над whisper-cli из whisper.cpp.
enum Transcriber {

    static var binaryPath: String? {
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            NSString(string: "~/.local/bin/whisper-cli").expandingTildeInPath
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Синхронно распознаёт WAV. Вызывать с фонового потока.
    static func transcribe(wav: URL, settings s: AppSettings) throws -> String {
        guard let bin = binaryPath else { throw TranscribeError.binaryMissing }
        guard FileManager.default.fileExists(atPath: s.modelPath) else {
            throw TranscribeError.modelMissing(s.modelPath)
        }

        var args = [
            "-m", s.modelPath,
            "-f", wav.path,
            "-l", s.language,
            "-t", String(s.threads),
            "-nt", "-np"
        ]
        if s.translateToEnglish { args.append("-tr") }
        if s.suppressNonSpeech { args.append("-sns") }
        let prompt = s.initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty { args += ["--prompt", prompt] }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: bin)
        task.arguments = args

        let outPipe = Pipe(), errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        try task.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw TranscribeError.failed(task.terminationStatus,
                                         String(data: errData, encoding: .utf8) ?? "")
        }
        return clean(String(data: outData, encoding: .utf8) ?? "")
    }

    /// whisper печатает по строке на сегмент и любит служебные пометки в скобках.
    static func clean(_ raw: String) -> String {
        let noiseMarkers = ["[BLANK_AUDIO]", "[MUSIC]", "[SOUND]", "(музыка)", "[Music]"]
        var text = raw
        for marker in noiseMarkers { text = text.replacingOccurrences(of: marker, with: " ") }

        let joined = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return collapseRepetitions(joined
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Whisper умеет уходить в петлю и повторять одну фразу десяток раз подряд.
    /// Три и более одинаковых куска идут в текст как один.
    static func collapseRepetitions(_ text: String) -> String {
        guard text.count > 40 else { return text }
        let pattern = "(.{10,160}?)(?:\\s*\\1){2,}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let result = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
        if result != text {
            Log.write("схлопнут повтор: \(text.count) → \(result.count) симв.")
        }
        return result
    }
}
