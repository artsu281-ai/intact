import AVFoundation
import AppKit
import SwiftUI

enum DictationState: Equatable {
    case idle, recording, transcribing
}

/// Склеивает всё вместе: клавиша → запись → whisper → вставка текста.
///
/// Ключевая идея: пока человек говорит, в фоне уже считаются черновики.
/// К моменту, когда клавишу отпускают, текст обычно уже готов — и вставка
/// происходит мгновенно, без паузы на распознавание.
final class DictationController: ObservableObject {
    static let shared = DictationController()

    @Published var state: DictationState = .idle
    @Published var level: Float = 0
    /// Последние уровни сигнала — из них рисуется бегущая волна.
    @Published private(set) var waveform: [Float] = []
    private let waveformLength = 64
    @Published var elapsedText = "0:00"
    @Published var blink = false
    @Published var draftText: String = ""
    @Published var lastResult: String = ""
    @Published var lastError: String? = nil
    @Published var lastLatencyMs: Int = 0
    @Published var engineReady = false
    @Published var permissionsOK = Permissions.allGranted
    /// Текст, который не удалось никуда вставить: показывается в панели с кнопкой.
    @Published var pendingText: String? = nil
    /// Текст сохраненной заметки для всплывающего статуса.
    @Published var noteSavedText: String? = nil
    /// Текст сохраненного напоминания для всплывающего статуса.
    @Published var reminderSavedText: String? = nil
    /// Секунды до авто-закрытия карточки копирования.
    @Published var pendingRemainingSeconds: Int = 0

    private var pendingTimer: Timer?

    private let recorder = AudioRecorder()
    private let indicator = IndicatorPanel()
    private let settings = AppSettings.shared

    private var ticker: Timer?
    private var draftTimer: Timer?
    private var startedAt = Date()

    /// Сколько секунд записи покрывает готовый черновик.
    private var draftCoverage: TimeInterval = 0
    /// Сколько секунд покрывает запрос, который прямо сейчас в работе.
    private var inFlightCoverage: TimeInterval = -1
    private var inFlight = false
    /// Клавишу уже отпустили, и мы ждём завершения последнего запроса.
    private var awaitingFinish = false
    private var releaseTime = Date()

    private let queue = DispatchQueue(label: "intact.transcribe", qos: .userInitiated)

    private var draftURL: URL { FileManager.default.temporaryDirectory.appendingPathComponent("intact-draft.wav") }
    private var finalURL: URL { FileManager.default.temporaryDirectory.appendingPathComponent("intact-final.wav") }

    private init() {
        recorder.onLevel = { [weak self] value in
            DispatchQueue.main.async {
                guard let self else { return }
                self.level = value
                self.waveform.append(value)
                if self.waveform.count > self.waveformLength {
                    self.waveform.removeFirst(self.waveform.count - self.waveformLength)
                }
            }
        }
    }

    // MARK: - Движок

    /// Поднимает whisper-server заранее, чтобы первая же диктовка была быстрой.
    func warmUp() {
        guard settings.streaming, WhisperServer.shared.isAvailable else {
            DispatchQueue.main.async { self.engineReady = false }
            return
        }
        WhisperServer.shared.ensureRunning(settings: settings) { ok in
            DispatchQueue.main.async { self.engineReady = ok }
        }
    }

    func restartEngine() {
        WhisperServer.shared.stop()
        DispatchQueue.main.async { self.engineReady = false }
        warmUp()
    }

    // MARK: - Управление записью

    func toggle() {
        switch state {
        case .idle:         start()
        case .recording:    stop()
        case .transcribing: break
        }
    }

    func start() {
        guard state == .idle else { return }
        guard ModelManager.shared.hasAnyModelInstalled else {
            Log.write("start() отклонён: модель Whisper не установлена, открываю настройки")
            DispatchQueue.main.async {
                SettingsWindow.shared.show()
            }
            return
        }
        ensureMicPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.fail("Нет доступа к микрофону. Разреши его в «Настройки → Конфиденциальность и безопасность → Микрофон».")
                return
            }
            do {
                try self.recorder.start(preferredDeviceUID: self.settings.inputDeviceUID)
                self.state = .recording
                self.startedAt = Date()
                self.lastError = nil
                self.draftText = ""
                self.draftCoverage = 0
                self.inFlightCoverage = -1
                self.awaitingFinish = false
                self.elapsedText = "0:00"
                self.pendingText = nil
                self.pendingTimer?.invalidate()
                if self.settings.showIndicator { self.indicator.show(controller: self) }
                if self.settings.playSounds { NSSound(named: "Tink")?.play() }
                MediaController.shared.begin(muteAudio: self.settings.muteAudioWhileDictating,
                                             pauseMedia: self.settings.pauseMediaWhileDictating)
                self.startTicker()
                self.startDrafting()
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    func stop() {
        guard state == .recording else { return }

        MediaController.shared.end()
        let heldMs = Date().timeIntervalSince(startedAt) * 1000
        let duration = recorder.stop()
        let lastSpeech = recorder.lastSpeechTime
        stopTicker()
        stopDrafting()
        releaseTime = Date()

        // Случайный чирк по клавише — не диктовка (менее 0.25 сек).
        if heldMs < Double(settings.minHoldMs) || duration < 0.25 {
            indicator.hide()
            state = .idle
            draftText = ""
            return
        }

        // Черновик уже покрывает всю речь — вставляем без единой миллисекунды ожидания.
        if settings.streaming, !draftText.isEmpty, draftCoverage >= lastSpeech - 0.05 {
            indicator.hide()
            state = .idle
            finish(text: draftText, seconds: duration, latencyMs: 0)
            return
        }

        state = .transcribing
        if settings.showIndicator { indicator.show(controller: self) }

        // Запрос, который сейчас в работе, уже захватил всю речь — дешевле дождаться его,
        // чем гонять модель ещё раз по тем же данным.
        if settings.streaming, inFlight, inFlightCoverage >= lastSpeech - 0.05 {
            awaitingFinish = true
            return
        }

        runFinalPass(duration: duration)
    }

    func cancel() {
        guard state == .recording else { return }
        MediaController.shared.end()
        recorder.stop()
        stopTicker()
        stopDrafting()
        indicator.hide()
        state = .idle
        draftText = ""
        if settings.playSounds { NSSound(named: "Basso")?.play() }
    }

    /// Пользователь нажал что-то ещё, пока держал триггер, — молча свернуться.
    func abort() {
        guard state == .recording else { return }
        MediaController.shared.end()
        recorder.stop()
        stopTicker()
        stopDrafting()
        indicator.hide()
        state = .idle
        draftText = ""
    }

    // MARK: - Черновики во время речи

    private func startDrafting() {
        guard settings.streaming, WhisperServer.shared.isRunning else { return }
        let interval = Double(settings.draftIntervalMs) / 1000
        draftTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tickDraft()
        }
    }

    private func stopDrafting() {
        draftTimer?.invalidate()
        draftTimer = nil
    }

    private func tickDraft() {
        guard state == .recording, !inFlight else { return }
        // Гонять модель по той же тишине смысла нет.
        let speech = recorder.lastSpeechTime
        guard speech > draftCoverage + 0.05 else { return }
        guard let coverage = recorder.snapshot(to: draftURL) else { return }

        inFlight = true
        inFlightCoverage = coverage
        let started = Date()

        queue.async { [weak self] in
            guard let self else { return }
            let text = (try? WhisperServer.shared.transcribe(wav: self.draftURL, settings: self.settings)) ?? ""
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            DispatchQueue.main.async {
                self.inFlight = false
                if !text.isEmpty {
                    self.draftText = text
                    self.draftCoverage = coverage
                    self.lastLatencyMs = ms
                }
                if self.awaitingFinish {
                    self.awaitingFinish = false
                    let waited = Int(Date().timeIntervalSince(self.releaseTime) * 1000)
                    self.indicator.hide()
                    self.state = .idle
                    self.finish(text: text, seconds: self.recorder.recordedDuration, latencyMs: waited)
                }
            }
        }
    }

    // MARK: - Финальный проход

    private func runFinalPass(duration: TimeInterval) {
        guard recorder.snapshot(to: finalURL) != nil else {
            indicator.hide()
            state = .idle
            return
        }
        let started = Date()
        let useServer = settings.streaming && WhisperServer.shared.isRunning

        queue.async { [weak self] in
            guard let self else { return }
            do {
                let text = useServer
                    ? try WhisperServer.shared.transcribe(wav: self.finalURL, settings: self.settings)
                    : try Transcriber.transcribe(wav: self.finalURL, settings: self.settings)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                DispatchQueue.main.async {
                    self.indicator.hide()
                    self.state = .idle
                    self.finish(text: text, seconds: duration, latencyMs: ms)
                }
            } catch {
                DispatchQueue.main.async {
                    self.indicator.hide()
                    self.state = .idle
                    self.fail(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Результат

    private func finish(text raw: String, seconds: TimeInterval, latencyMs: Int) {
        let text = postProcess(raw)
        draftText = ""
        lastLatencyMs = latencyMs
        lastResult = text.trimmingCharacters(in: .whitespaces)

        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            if settings.playSounds { NSSound(named: "Basso")?.play() }
            lastError = "Речь не распознана — тишина или слишком тихий микрофон."
            return
        }

        // Проверяем команду создания заметки в Apple Notes
        if settings.enableVoiceNotes, let noteContent = AppleNotesService.extractNoteText(from: text) {
            AppleNotesService.createNote(text: noteContent, folderName: settings.voiceNotesFolder)
            if settings.playSounds { NSSound(named: "Glass")?.play() }
            if settings.keepHistory {
                History.shared.add(HistoryEntry(text: "📝 \(noteContent)",
                                                seconds: seconds,
                                                model: URL(fileURLWithPath: settings.modelPath).lastPathComponent))
            }
            showNoteSavedToast(title: noteContent)
            return
        }

        // Проверяем команду создания напоминания в Apple Reminders
        if settings.enableVoiceReminders, let rem = AppleRemindersService.extractReminder(from: text) {
            AppleRemindersService.createReminder(title: rem.title, dueDate: rem.dueDate, listName: settings.voiceRemindersList)
            if settings.playSounds { NSSound(named: "Glass")?.play() }
            if settings.keepHistory {
                let dueInfo = rem.dueDate != nil ? " (\(DateFormatter.localizedString(from: rem.dueDate!, dateStyle: .short, timeStyle: .short)))" : ""
                History.shared.add(HistoryEntry(text: "⏰ \(rem.title)\(dueInfo)",
                                                seconds: seconds,
                                                model: URL(fileURLWithPath: settings.modelPath).lastPathComponent))
            }
            showReminderSavedToast(title: rem.title, dueDate: rem.dueDate)
            return
        }

        // Проверяем, доступно ли активное окно/поле для вставки
        let insertable = FocusInspector.canInsertText
        if !insertable && settings.outputMode != .clipboard {
            offerCopy(lastResult)
            return
        }

        TextInserter.deliver(text, mode: settings.outputMode)
        if settings.playSounds { NSSound(named: "Pop")?.play() }
        if settings.keepHistory {
            History.shared.add(HistoryEntry(text: lastResult,
                                            seconds: seconds,
                                            model: URL(fileURLWithPath: settings.modelPath).lastPathComponent))
        }
    }

    /// Показывает короткое всплывающее подтверждение сохранения заметки
    private func showNoteSavedToast(title: String) {
        noteSavedText = title
        indicator.show(controller: self, interactive: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.state == .idle else { return }
            self.noteSavedText = nil
            self.indicator.hide()
        }
    }

    /// Показывает короткое всплывающее подтверждение сохранения напоминания
    private func showReminderSavedToast(title: String, dueDate: Date?) {
        if let dueDate {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "ru_RU")
            fmt.dateFormat = "d MMM в HH:mm"
            reminderSavedText = "\(title) (\(fmt.string(from: dueDate)))"
        } else {
            reminderSavedText = title
        }
        indicator.show(controller: self, interactive: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self, self.state == .idle else { return }
            self.reminderSavedText = nil
            self.indicator.hide()
        }
    }

    // MARK: - Вставлять некуда

    /// Показывает результат в панели с кнопкой «Скопировать».
    private func offerCopy(_ text: String) {
        Log.write("вставить некуда — показываю кнопку копирования")
        pendingText = text
        let timeout = max(2, settings.copyDismissTimeoutSeconds)
        pendingRemainingSeconds = timeout
        indicator.show(controller: self, interactive: true)
        if settings.playSounds { NSSound(named: "Funk")?.play() }

        pendingTimer?.invalidate()
        pendingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.pendingRemainingSeconds -= 1
            if self.pendingRemainingSeconds <= 0 {
                self.dismissPending()
            }
        }
    }

    func copyPending() {
        guard let text = pendingText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        dismissPending()
    }

    func dismissPending() {
        pendingTimer?.invalidate()
        pendingTimer = nil
        pendingRemainingSeconds = 0
        pendingText = nil
        indicator.hide()
    }

    private func postProcess(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.trimTrailingPeriod, text.hasSuffix(".") { text.removeLast() }
        if settings.appendSpace, !text.isEmpty { text += " " }
        return text
    }

    private func fail(_ message: String) {
        state = .idle
        MediaController.shared.end()
        lastError = message
        NSLog("Intact: \(message)")
        let alert = NSAlert()
        alert.messageText = "Intact"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func ensureMicPermission(_ done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            done(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { done(ok) }
            }
        default:
            done(false)
        }
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.state == .recording else { return }
            let d = Int(self.recorder.duration)
            self.elapsedText = String(format: "%d:%02d", d / 60, d % 60)
            self.blink.toggle()
            if d >= self.settings.maxSeconds { self.stop() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        blink = false
        level = 0
        waveform = []
    }
}
