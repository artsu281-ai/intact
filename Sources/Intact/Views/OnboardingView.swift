import AppKit
import AVFoundation
import SwiftUI

/// Первый запуск: три шага вместо россыпи системных запросов и каталога моделей.
/// Человеку, который только скачал приложение, нужно ровно три вещи — разрешить
/// микрофон, разрешить клавиатуру и скачать модель речи. Остальное уже настроено.
struct OnboardingView: View {
    @ThemeReader var themeStamp

    @ObservedObject private var models = ModelManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var gemini = GeminiBridgeService.shared
    var onFinish: () -> Void

    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var inputMonitoring = Permissions.inputMonitoring
    @State private var accessibility = Permissions.accessibility
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Запуск с `--onboarding-preview`: показывает окно как у нового пользователя,
    /// ничего не меняя в настройках. Нужен, чтобы посмотреть вид на настроенном Mac.
    static let preview = CommandLine.arguments.contains("--onboarding-preview")

    private var micDone: Bool { !Self.preview && micStatus == .authorized }
    private var hasInputMonitoring: Bool { !Self.preview && inputMonitoring }
    private var hasAccessibility: Bool { !Self.preview && accessibility }
    private var keysDone: Bool { hasInputMonitoring && hasAccessibility }
    private var modelDone: Bool { models.hasAnyModelInstalled }
    private var geminiReady: Bool { gemini.isInstalled }
    /// Для распознавания хватает Gemini или локальной модели — что-то одно.
    private var speechDone: Bool { !Self.preview && (geminiReady || modelDone) }
    private var allDone: Bool { micDone && keysDone && speechDone }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(T("Давайте настроим Intact", "Let's set up Intact"))
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(Palette.textPrimary)
                Text(T("Три шага, пара минут. Диктовка работает через Gemini, а локальная модель подстрахует без интернета.",
                       "Three steps, a couple of minutes. Dictation runs on Gemini, with a local model as an offline backup."))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 22)

            VStack(spacing: 12) {
                step(number: 1, done: micDone,
                     title: T("Микрофон", "Microphone"),
                     text: T("Чтобы слышать, что вы говорите.", "So Intact can hear you.")) {
                    if !micDone {
                        PillButton(title: micStatus == .notDetermined ? T("Разрешить", "Allow") : T("Открыть настройки", "Open Settings")) {
                            if micStatus == .notDetermined {
                                AVCaptureDevice.requestAccess(for: .audio) { _ in
                                    DispatchQueue.main.async { refresh() }
                                }
                            } else {
                                Permissions.openMicrophoneSettings()
                            }
                        }
                    }
                }

                step(number: 2, done: keysDone,
                     title: T("Клавиатура", "Keyboard"),
                     text: T("Чтобы ловить ⌥ и вставлять текст. Два права — macOS спросит дважды.",
                             "To catch ⌥ and insert text. Two permissions — macOS asks twice.")) {
                    VStack(alignment: .trailing, spacing: 8) {
                        if !hasInputMonitoring {
                            PillButton(title: T("Мониторинг ввода", "Input Monitoring")) {
                                Permissions.requestInputMonitoring()
                                Permissions.openInputMonitoringSettings()
                            }
                        }
                        if !hasAccessibility {
                            PillButton(title: T("Универсальный доступ", "Accessibility")) {
                                Permissions.requestAccessibility()
                                Permissions.openAccessibilitySettings()
                            }
                        }
                    }
                }

                speechStep
            }

            Spacer(minLength: 16)

            if allDone {
                readyBlock
            } else {
                HStack {
                    Spacer()
                    Button(T("Пропустить", "Skip")) { onFinish() }
                        .buttonStyle(.intact(.quiet))
                }
            }
        }
        .padding(32)
        .frame(width: 560, height: 600, alignment: .topLeading)
        .background(Palette.page)
        .onReceive(poll) { _ in refresh() }
    }

    // MARK: - Шаг 3

    /// Gemini — основной путь: самый точный и ничего не надо качать. Локальная
    /// модель — запас на случай, когда Gemini недоступен или нет интернета.
    private var speechStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                badge(number: 3, done: speechDone)
                VStack(alignment: .leading, spacing: 3) {
                    Text(T("Распознавание речи", "Speech recognition"))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(T("Нужен один из двух вариантов. Gemini — лучший, локальный — запасной.",
                           "One of two options is enough. Gemini is the best; local is the backup."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            optionRow(
                title: "Gemini",
                tag: T("Рекомендуем", "Recommended"),
                text: geminiReady
                    ? T("Приложение найдено. Самое мощное и точное распознавание, ничего скачивать не нужно.",
                        "App found. The most powerful and accurate option — nothing to download.")
                    : T("Самое мощное и точное. Нужно приложение Gemini для Mac — установите его и войдите в аккаунт.",
                        "The most powerful and accurate. Needs the Gemini app for Mac — install it and sign in."),
                ready: geminiReady) {
                if !geminiReady {
                    PillButton(title: T("Открыть Gemini", "Open Gemini")) {
                        NSWorkspace.shared.open(URL(string: "https://gemini.google.com/")!)
                    }
                }
            }

            optionRow(
                title: T("Локальная модель", "Local model"),
                tag: T("Без интернета", "Offline"),
                text: modelDone
                    ? T("Установлена — подстрахует, если Gemini недоступен.", "Installed — covers you when Gemini is unavailable.")
                    : models.downloading != nil
                        ? T("Скачиваю… \(Int(models.progress * 100))%", "Downloading… \(Int(models.progress * 100))%")
                        : T("Работает офлайн, речь не покидает Mac. Скачивается один раз.",
                            "Works offline; speech never leaves the Mac. Downloaded once."),
                ready: modelDone) {
                if !modelDone {
                    if models.downloading != nil {
                        ProgressView(value: models.progress).frame(width: 90)
                    } else {
                        VStack(alignment: .trailing, spacing: 6) {
                            PillButton(title: T("Скачать · 1.5 ГБ", "Download · 1.5 GB"), icon: .download) {
                                models.download(models.recommendedModel)
                            }
                            Button(T("Лёгкая · 148 МБ", "Light · 148 MB")) { models.download(models.baseModel) }
                                .buttonStyle(.intact(.quiet))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(cardBackground(done: speechDone))
    }

    private func optionRow<Action: View>(title: String, tag: String, text: String, ready: Bool,
                                         @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(tag)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.pill))
                    if ready {
                        IntactIcon(kind: .copied, size: 12).foregroundStyle(Palette.iconSuccess)
                    }
                }
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action()
        }
        .padding(.leading, 44)
    }

    // MARK: - Готово

    private var readyBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IntactIcon(kind: .success, size: 18).foregroundStyle(Palette.iconSuccess)
                Text(T("Готово. Зажмите ⌥ и говорите — текст появится там, где курсор.",
                       "Done. Hold ⌥ and speak — the text appears where your cursor is."))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(gemini.isInstalled
                 ? T("Диктовка, чат и ассистент работают через Gemini — основной режим. Локальная модель подстрахует без интернета.",
                     "Dictation, chat and the assistant run on Gemini — the main mode. The local model covers you offline.")
                 : T("Диктовка пойдёт через локальную модель. Установите Gemini позже — и она переключится на него сама.",
                     "Dictation will use the local model. Install Gemini later and it switches over on its own."))
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(T("Начать", "Get started")) { onFinish() }
                    .buttonStyle(.intact(.accent))
            }
        }
    }

    // MARK: - Карточка шага

    private func badge(number: Int, done: Bool) -> some View {
        ZStack {
            Circle().fill(done ? Palette.iconSuccess.opacity(0.16) : Palette.pill)
            if done {
                IntactIcon(kind: .copied, size: 14).foregroundStyle(Palette.iconSuccess)
            } else {
                Text("\(number)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(width: 30, height: 30)
    }

    private func cardBackground(done: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Palette.card)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(done ? Palette.iconSuccess.opacity(0.35) : Palette.hairline, lineWidth: 1))
    }

    private func step<Action: View>(number: Int, done: Bool, title: String, text: String,
                                    @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .center, spacing: 14) {
            badge(number: number, done: done)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.card)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(done ? Palette.iconSuccess.opacity(0.35) : Palette.hairline, lineWidth: 1))
        )
    }

    private func refresh() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        inputMonitoring = Permissions.inputMonitoring
        accessibility = Permissions.accessibility
    }
}

/// Окно первого запуска. Показывается один раз; «Пропустить» тоже считается.
final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private var window: NSWindow?
    private static let doneKey = "onboardingDone"

    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    /// Показывать нужно тем, у кого чего-то не хватает. Если всё уже работает
    /// (обновление со старой версии), окно не появляется вовсе.
    static var needed: Bool {
        guard !isDone else { return false }
        let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if micOK && Permissions.allGranted && ModelManager.shared.hasAnyModelInstalled {
            UserDefaults.standard.set(true, forKey: doneKey)
            return false
        }
        return true
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView(onFinish: { [weak self] in self?.finish() }))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        PipelineManager.shared.preferGeminiIfUntouched()
        window?.close()
        window = nil
        MainWindow.shared.show(section: .home)
    }
}
