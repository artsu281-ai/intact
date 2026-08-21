import AVFoundation
import CoreAudio
import Foundation

struct InputDevice: Identifiable, Hashable {
    let id: String      // UID
    let name: String
    let deviceID: AudioDeviceID
}

/// Запись с микрофона в 16 кГц моно. Сэмплы копятся в памяти, чтобы в любой
/// момент можно было снять срез и отправить его на распознавание, не прерывая запись.
final class AudioRecorder {
    static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let bufferLock = NSLock()
    private var samples: [Float] = []
    private var lastSpeechSample: Int = 0

    private(set) var isRecording = false
    private var startTime = Date()

    /// Уровень сигнала 0...1 для индикатора.
    var onLevel: ((Float) -> Void)?

    var duration: TimeInterval { isRecording ? Date().timeIntervalSince(startTime) : recordedDuration }

    var recordedDuration: TimeInterval {
        bufferLock.lock(); defer { bufferLock.unlock() }
        return Double(samples.count) / Self.sampleRate
    }

    /// Момент последней речи в секундах от начала записи.
    /// По нему видно, договорил ли человек до того, как отпустил клавишу.
    var lastSpeechTime: TimeInterval {
        bufferLock.lock(); defer { bufferLock.unlock() }
        return Double(lastSpeechSample) / Self.sampleRate
    }

    private static var targetFormat: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    }

    // MARK: - Устройства ввода

    static func availableInputDevices() -> [InputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id -> InputDevice? in
            guard deviceHasInput(id), let uid = deviceString(id, kAudioDevicePropertyDeviceUID),
                  let name = deviceString(id, kAudioObjectPropertyName) else { return nil }
            return InputDevice(id: uid, name: name, deviceID: id)
        }
    }

    private static func deviceHasInput(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func deviceString(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString? = nil
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value as String?
    }

    private func applyPreferredDevice(uid: String) {
        guard !uid.isEmpty,
              let dev = Self.availableInputDevices().first(where: { $0.id == uid }),
              let unit = engine.inputNode.audioUnit else { return }
        var deviceID = dev.deviceID
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0,
                             &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    // MARK: - Запись

    func start(preferredDeviceUID: String) throws {
        guard !isRecording else { return }

        bufferLock.lock()
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(Int(Self.sampleRate) * 30)
        lastSpeechSample = 0
        bufferLock.unlock()

        applyPreferredDevice(uid: preferredDeviceUID)

        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else {
            throw NSError(domain: "VoiceInput", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Микрофон недоступен. Проверь разрешение в «Конфиденциальность и безопасность → Микрофон»."
            ])
        }

        let target = Self.targetFormat
        converter = AVAudioConverter(from: inFormat, to: target)

        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, target: target)
        }

        engine.prepare()
        try engine.start()
        startTime = Date()
        isRecording = true
    }

    private func process(buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        guard let converter else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let ch = out.floatChannelData?[0] else { return }

        let n = Int(out.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = sqrt(sum / Float(n))

        bufferLock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: ch, count: n))
        // Порог речи: ловит даже тихую речь
        if rms > 0.003 { lastSpeechSample = samples.count }
        bufferLock.unlock()

        let db = 20 * log10(max(rms, 1e-7))
        onLevel?(max(0, min(1, (db + 55) / 55)))
    }

    @discardableResult
    func stop() -> TimeInterval {
        guard isRecording else { return 0 }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        isRecording = false
        onLevel?(0)
        return recordedDuration
    }

    // MARK: - Срезы для распознавания

    /// Пишет текущее содержимое буфера в WAV. Возвращает файл и то,
    /// сколько секунд записи он покрывает — по этому числу видно, свеж ли черновик.
    func snapshot(to url: URL, trimTrailingSilence: Bool = true) -> TimeInterval? {
        bufferLock.lock()
        var copy = samples
        let speechEnd = lastSpeechSample
        bufferLock.unlock()

        // Тишина в хвосте — главный триггер галлюцинаций whisper: на пустом
        // куске декодер уходит в петлю и повторяет последнюю фразу.
        // Оставляем небольшой запас после последней речи и обрезаем остальное.
        if trimTrailingSilence, speechEnd > 0 {
            let keep = min(copy.count, speechEnd + Int(Self.sampleRate * 0.35))
            if keep > Int(Self.sampleRate * 0.2) { copy = Array(copy[0..<keep]) }
        }

        guard copy.count > Int(Self.sampleRate * 0.2) else { return nil }
        guard writeWAV(copy, to: url) else { return nil }
        return Double(copy.count) / Self.sampleRate
    }

    /// 16-bit PCM WAV — ровно то, что ест whisper, без лишних зависимостей.
    private func writeWAV(_ floats: [Float], to url: URL) -> Bool {
        let dataBytes = floats.count * 2
        var data = Data(capacity: 44 + dataBytes)

        func le32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func le16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8));  le32(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8));  le32(16)
        le16(1); le16(1)
        le32(UInt32(Self.sampleRate))
        le32(UInt32(Self.sampleRate) * 2)
        le16(2); le16(16)
        data.append(contentsOf: Array("data".utf8));  le32(UInt32(dataBytes))

        for f in floats {
            let clamped = max(-1, min(1, f))
            le16(UInt16(bitPattern: Int16(clamped * 32767)))
        }
        return (try? data.write(to: url)) != nil
    }
}
