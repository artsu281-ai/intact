import AppKit
import Foundation

/// Обновление через GitHub Releases: берёт последний релиз, сравнивает тег с
/// версией бандла, скачивает `Intact.zip`, подменяет приложение и перезапускается.
///
/// Подмену делает отдельный shell-процесс: сам себя запущенное приложение
/// заменить не может. Бандл подписан тем же сертификатом, что и прежний, поэтому
/// выданные системные разрешения переживают обновление.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    static let repo = "artsu281-ai/intact"
    private static let assetName = "Intact.zip"
    private static let lastCheckKey = "updater.lastCheck"

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private var assetURL: URL?
    private var releasePage: URL?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Тихая проверка при запуске — не чаще раза в сутки.
    func checkInBackground() {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        Task { await check() }
    }

    func check() async {
        guard state != .checking, state != .installing else { return }
        state = .checking
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 15
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                state = .failed(T("Релизы не найдены", "No releases found"))
                return
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            releasePage = (json["html_url"] as? String).flatMap(URL.init)
            let assets = json["assets"] as? [[String: Any]] ?? []
            assetURL = assets.first { $0["name"] as? String == Self.assetName }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init)

            if Self.isNewer(version, than: Self.currentVersion), assetURL != nil {
                state = .available(version: version)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func install() async {
        guard case .available = state, let assetURL else { return }
        state = .installing
        do {
            let (tmp, resp) = try await URLSession.shared.download(from: assetURL)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw NSError(domain: "Intact", code: 2, userInfo: [NSLocalizedDescriptionKey: T("Не удалось скачать обновление", "Download failed")])
            }
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("intact-update-\(UUID().uuidString)")
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent(Self.assetName)
            try fm.moveItem(at: tmp, to: zip)

            try run("/usr/bin/ditto", ["-xk", zip.path, work.path])
            let newApp = work.appendingPathComponent("Intact.app")
            guard fm.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS/Intact").path) else {
                throw NSError(domain: "Intact", code: 3, userInfo: [NSLocalizedDescriptionKey: T("Архив повреждён", "Corrupt archive")])
            }
            try run("/usr/bin/codesign", ["--verify", "--deep", newApp.path])

            let dest = Bundle.main.bundleURL.path
            let script = """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
            rm -rf "\(dest)" && cp -R "\(newApp.path)" "\(dest)" && xattr -cr "\(dest)"
            open "\(dest)"
            rm -rf "\(work.path)"
            """
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", script]
            try p.run()
            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func openReleasePage() {
        NSWorkspace.shared.open(releasePage ?? URL(string: "https://github.com/\(Self.repo)/releases")!)
    }

    private func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "Intact", code: 4, userInfo: [NSLocalizedDescriptionKey: "\((path as NSString).lastPathComponent) → \(p.terminationStatus)"])
        }
    }

    /// Сравнение по числовым компонентам: «1.10» новее «1.9».
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
