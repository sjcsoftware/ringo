import AppKit
import Combine
import RingoEngine
import RingoUpdates
import Sparkle

@MainActor
final class UpdaterManager: NSObject, ObservableObject {
    static let shared = UpdaterManager()

    @Published private(set) var isChecking = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var message = "Check GitHub for the latest Ringo release."
    @Published private(set) var canInstall = false

    var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? RingoEngine.version
    }

    private let controller: SPUStandardUpdaterController

    private override init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canInstall)
    }

    func start() {
        #if !DEBUG
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        availableVersion = nil
        message = "Checking GitHub…"
        defer { isChecking = false }
        do {
            let release = try await GitHubReleaseClient().latest()
            #if arch(arm64)
            let architecture = "arm64"
            #else
            let architecture = "x86_64"
            #endif
            if try release.isNewer(than: installedVersion, architecture: architecture) {
                availableVersion = release.version
                message = "Ringo \(release.version) is available."
            } else {
                message = "You're up to date. You have Ringo \(installedVersion)."
            }
        } catch {
            message = "Couldn't check for updates. \(error.localizedDescription)"
        }
    }

    func installUpdate() {
        #if !DEBUG
        guard availableVersion != nil, canInstall else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
        #endif
    }
}
