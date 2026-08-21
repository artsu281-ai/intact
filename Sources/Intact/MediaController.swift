import AppKit
import AudioToolbox
import CoreAudio

/// Управление звуком и медиаплеерами во время диктовки:
///
/// 1. **Заглушение звука (Mute Output)** — временно глушит вывод динамиков/наушников
///    через CoreAudio, чтобы фоновый звук (YouTube, звонки, игры) не лез в микрофон
///    и не портил распознавание Whisper.
/// 2. **Пауза медиаплееров (Pause Media)** — ставит на паузу Apple Music, Spotify и другие
///    плееры во время речи (только если они запущены), а по завершении диктовки возобновляет.
final class MediaController {
    static let shared = MediaController()

    private let queue = DispatchQueue(label: "intact.mediacontroller", qos: .userInitiated)

    private var wasMutedBefore: Bool?
    private var didPauseMusic = false
    private var didPauseSpotify = false

    private init() {}

    // MARK: - Публичные методы

    /// Вызывается в момент старта записи.
    func begin(muteAudio: Bool, pauseMedia: Bool) {
        queue.async {
            if pauseMedia {
                self.pauseActiveMedia()
            }
            if muteAudio {
                self.muteSystemOutput()
            }
        }
    }

    /// Вызывается при завершении, отмене или прерывании записи.
    func end() {
        queue.async {
            self.unmuteSystemOutput()
            self.resumeActiveMedia()
        }
    }

    // MARK: - CoreAudio / Системный звук

    private func muteSystemOutput() {
        let deviceID = defaultOutputDeviceID()
        guard deviceID != 0 else {
            // Fallback через AppleScript
            runAppleScript("set volume with output muted")
            return
        }

        let currentlyMuted = isDeviceMuted(deviceID)
        self.wasMutedBefore = currentlyMuted

        if !currentlyMuted {
            setDeviceMuted(deviceID, muted: true)
        }
    }

    private func unmuteSystemOutput() {
        guard let wasMuted = wasMutedBefore else { return }
        self.wasMutedBefore = nil

        // Если до начала диктовки звук не был заглушен — возвращаем звук
        if !wasMuted {
            let deviceID = defaultOutputDeviceID()
            if deviceID != 0 {
                setDeviceMuted(deviceID, muted: false)
            } else {
                runAppleScript("set volume without output muted")
            }
        }
    }

    private func defaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : 0
    }

    private func isDeviceMuted(_ deviceID: AudioDeviceID) -> Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 0
        }
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        return status == noErr && muted != 0
    }

    private func setDeviceMuted(_ deviceID: AudioDeviceID, muted: Bool) {
        var val: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 0
        }
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &val)
        if status != noErr {
            // Резервный вариант через AppleScript, если устройство не поддерживает прямой Mute
            runAppleScript(muted ? "set volume with output muted" : "set volume without output muted")
        }
    }

    // MARK: - Плееры (Apple Music, Spotify)

    private func pauseActiveMedia() {
        // Apple Music: проверяем, запущен ли процесс перед выполнением скрипта
        let musicApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        if let music = musicApps.first, !music.isTerminated {
            let script = """
            tell application id "com.apple.Music"
                if player state is playing then
                    pause
                    return true
                end if
            end tell
            return false
            """
            if runAppleScriptBool(script) {
                didPauseMusic = true
            }
        }

        // Spotify: проверяем, запущен ли процесс перед выполнением скрипта
        let spotifyApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
        if let spotify = spotifyApps.first, !spotify.isTerminated {
            let script = """
            tell application id "com.spotify.client"
                if player state is playing then
                    pause
                    return true
                end if
            end tell
            return false
            """
            if runAppleScriptBool(script) {
                didPauseSpotify = true
            }
        }
    }

    private func resumeActiveMedia() {
        if didPauseMusic {
            didPauseMusic = false
            let musicApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            if let music = musicApps.first, !music.isTerminated {
                runAppleScript("tell application id \"com.apple.Music\" to play")
            }
        }

        if didPauseSpotify {
            didPauseSpotify = false
            let spotifyApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
            if let spotify = spotifyApps.first, !spotify.isTerminated {
                runAppleScript("tell application id \"com.spotify.client\" to play")
            }
        }
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        return result.stringValue
    }

    private func runAppleScriptBool(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        return result.booleanValue
    }
}
