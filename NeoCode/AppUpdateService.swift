import AppKit
import Foundation
import Observation
import OSLog
import Sparkle

@MainActor
@Observable
final class AppUpdateService: NSObject, SPUUpdaterDelegate {
    struct UpdateRelease: Equatable {
        let displayVersion: String
        let buildVersion: String?
        let infoURL: URL?

        var versionDescription: String {
            guard let buildVersion, buildVersion != displayVersion else {
                return displayVersion
            }

            return "\(displayVersion) (\(buildVersion))"
        }
    }

    struct UpdateProgress: Equatable {
        let release: UpdateRelease
        let fractionCompleted: Double?
    }

    enum Phase: Equatable {
        case unavailable(String)
        case idle
        case checking
        case available(UpdateRelease)
        case downloading(UpdateProgress)
        case extracting(UpdateProgress)
        case readyToInstall(UpdateRelease)
        case installing(UpdateRelease)
        case upToDate(Date?)
        case error(String)
    }

    @ObservationIgnored private static let installChoice = SPUUserUpdateChoice(rawValue: 1)!
    @ObservationIgnored private let logger = Logger(subsystem: "tech.watzon.NeoCode", category: "AppUpdateService")
    @ObservationIgnored private let titlebarAccessoryController = TitlebarUpdateAccessoryController()
    @ObservationIgnored private let installedRelease = AppUpdateService.currentInstalledRelease()

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var pendingChoiceHandler: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored private var downloadCancellationHandler: (() -> Void)?
    @ObservationIgnored private var expectedDownloadBytes: UInt64 = 0
    @ObservationIgnored private var downloadedBytes: UInt64 = 0

    var phase: Phase = .idle
    var lastCheckedAt: Date?

    override init() {
        super.init()

        if Self.isRunningTests {
            phase = .unavailable("Updates are disabled while NeoCode is running under tests.")
            return
        }

        if let configurationIssue = Self.configurationIssue() {
            phase = .unavailable(configurationIssue)
            return
        }

        let userDriver = NeoCodeSparkleUserDriver()
        userDriver.service = self

        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: self
        )
        updater.automaticallyDownloadsUpdates = false
        _ = updater.clearFeedURLFromUserDefaults()

        do {
            try updater.start()
        } catch {
            let message = error.localizedDescription.isEmpty ? "Sparkle failed to start." : error.localizedDescription
            logger.error("Failed to start Sparkle updater: \(message, privacy: .public)")
            phase = .error(message)
            return
        }

        self.updater = updater
        lastCheckedAt = updater.lastUpdateCheckDate
        if let lastCheckedAt {
            phase = .upToDate(lastCheckedAt)
        }
    }

    var installedVersionDescription: String {
        installedRelease.versionDescription
    }

    var availableVersionDescription: String? {
        activeRelease?.versionDescription
    }

    var isAvailableInThisBuild: Bool {
        updater != nil
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            updater?.automaticallyChecksForUpdates ?? false
        }
        set {
            guard let updater else { return }
            updater.automaticallyChecksForUpdates = newValue
            let state = newValue ? "enabled" : "disabled"
            logger.info("Automatic update checks \(state, privacy: .public)")
        }
    }

    var canCheckForUpdates: Bool {
        return updater?.canCheckForUpdates ?? false
    }

    var canPerformPrimaryAction: Bool {
        switch phase {
        case .available, .readyToInstall:
            return pendingChoiceHandler != nil
        default:
            return false
        }
    }

    var statusTitle: String {
        switch phase {
        case .unavailable:
            return "Unavailable"
        case .idle:
            return automaticallyChecksForUpdates ? "Watching for releases" : "Automatic checks paused"
        case .checking:
            return "Checking now"
        case .available:
            return "Update available"
        case .downloading:
            return "Downloading"
        case .extracting:
            return "Preparing update"
        case .readyToInstall:
            return "Ready to install"
        case .installing:
            return "Installing"
        case .upToDate:
            return "Up to date"
        case .error:
            return "Update error"
        }
    }

    var statusDetail: String {
        switch phase {
        case .unavailable(let message):
            return message
        case .idle:
            return automaticallyChecksForUpdates
                ? "NeoCode will keep checking GitHub releases in the background and surface new builds in the titlebar instead of interrupting you with a modal."
                : "Automatic background checks are off. You can still ask Sparkle to check manually at any time."
        case .checking:
            return "Sparkle is contacting the release feed and validating the latest signed build."
        case .available(let release):
            return "Version \(release.versionDescription) is ready to download. Use the blue titlebar control or the action below when you want to start it."
        case .downloading(let progress):
            return "NeoCode is downloading version \(progress.release.versionDescription). The titlebar control mirrors the live percentage so you can keep working."
        case .extracting(let progress):
            return "Sparkle finished downloading version \(progress.release.versionDescription) and is unpacking it for installation."
        case .readyToInstall(let release):
            return "Version \(release.versionDescription) is staged and ready. Install it when you are ready to relaunch NeoCode."
        case .installing(let release):
            return "Sparkle is installing version \(release.versionDescription). NeoCode may relaunch automatically when the process completes."
        case .upToDate:
            return "You are already running the newest compatible signed release available from the appcast feed."
        case .error(let message):
            return message
        }
    }

    var manualCheckButtonTitle: String {
        canCheckForUpdates ? "Check now" : "Checking…"
    }

    var primaryActionTitle: String? {
        switch phase {
        case .available(let release):
            return "Download \(release.displayVersion)"
        case .readyToInstall(let release):
            return "Install \(release.displayVersion)"
        default:
            return nil
        }
    }

    func attach(to window: NSWindow) {
        titlebarAccessoryController.attach(to: window, updateService: self)
    }

    func checkForUpdates() {
        guard let updater else {
            phase = .unavailable(Self.configurationIssue() ?? "Sparkle is not configured for this build.")
            return
        }

        guard updater.canCheckForUpdates else { return }

        logger.info("Checking for updates")
        phase = .checking
        updater.checkForUpdates()
    }

    func performPrimaryAction() {
        switch phase {
        case .available(let release):
            logger.info("Starting download for version \(release.versionDescription, privacy: .public)")
            phase = .downloading(.init(release: release, fractionCompleted: 0))
            respondToPendingChoice(with: Self.installChoice)
        case .readyToInstall(let release):
            logger.info("Installing version \(release.versionDescription, privacy: .public)")
            phase = .installing(release)
            respondToPendingChoice(with: Self.installChoice)
        default:
            break
        }
    }

    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
        false
    }

    func handleUserInitiatedUpdateCheckStarted() {
        phase = .checking
    }

    func handleUpdateFound(appcastItem: SUAppcastItem, stageRawValue: Int, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        clearTransientState()
        pendingChoiceHandler = reply

        let release = release(from: appcastItem)
        switch stageRawValue {
        case 1:
            phase = .readyToInstall(release)
        case 2:
            phase = .installing(release)
        default:
            phase = .available(release)
        }
    }

    func handleInformationalUpdate(appcastItem: SUAppcastItem) {
        let release = release(from: appcastItem)
        let destination = appcastItem.infoURL?.absoluteString ?? "the release feed"
        phase = .error("Sparkle found an informational update for \(release.versionDescription). Review it at \(destination).")
    }

    func handleUpdateNotFound(error: Error, acknowledgement: @escaping () -> Void) {
        clearTransientState()
        lastCheckedAt = Date()
        phase = .upToDate(lastCheckedAt)
        acknowledgement()
    }

    func handleUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        clearTransientState()
        let message = error.localizedDescription.isEmpty ? "Sparkle failed to complete the update check." : error.localizedDescription
        logger.error("Sparkle updater error: \(message, privacy: .public)")
        phase = .error(message)
        acknowledgement()
    }

    func handleDownloadInitiated(cancellation: @escaping () -> Void) {
        downloadCancellationHandler = cancellation
        expectedDownloadBytes = 0
        downloadedBytes = 0

        if let release = activeRelease {
            phase = .downloading(.init(release: release, fractionCompleted: 0))
        }
    }

    func handleExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedDownloadBytes = expectedContentLength
        downloadedBytes = 0
        updateDownloadProgress()
    }

    func handleDownloadedData(length: UInt64) {
        downloadedBytes += length
        if downloadedBytes > expectedDownloadBytes {
            expectedDownloadBytes = downloadedBytes
        }

        updateDownloadProgress()
    }

    func handleExtractionStarted() {
        guard let release = activeRelease else { return }
        phase = .extracting(.init(release: release, fractionCompleted: nil))
    }

    func handleExtractionProgress(_ progress: Double) {
        guard let release = activeRelease else { return }
        phase = .extracting(.init(release: release, fractionCompleted: progress.clamped(to: 0 ... 1)))
    }

    func handleReadyToInstall(reply: @escaping (SPUUserUpdateChoice) -> Void) {
        pendingChoiceHandler = reply
        guard let release = activeRelease else { return }
        phase = .readyToInstall(release)
    }

    func handleInstallingUpdate() {
        pendingChoiceHandler = nil
        downloadCancellationHandler = nil
        guard let release = activeRelease else { return }
        phase = .installing(release)
    }

    func handleInstalledUpdate(acknowledgement: @escaping () -> Void) {
        clearTransientState()
        lastCheckedAt = Date()
        phase = .idle
        acknowledgement()
    }

    func handleTerminationCancelledDuringInstall() {
        if case .installing = phase, let release = activeRelease {
            phase = .readyToInstall(release)
        }
    }

    func handleDismissedUpdateFlow() {
        clearTransientState()

        switch phase {
        case .available, .downloading, .extracting, .readyToInstall, .installing:
            phase = .idle
        default:
            break
        }
    }

    private var activeRelease: UpdateRelease? {
        switch phase {
        case .available(let release), .readyToInstall(let release), .installing(let release):
            return release
        case .downloading(let progress), .extracting(let progress):
            return progress.release
        default:
            return nil
        }
    }

    private func release(from appcastItem: SUAppcastItem) -> UpdateRelease {
        let displayVersion = appcastItem.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildVersion = appcastItem.versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayVersion = displayVersion.isEmpty ? buildVersion : displayVersion
        let normalizedBuildVersion = buildVersion.isEmpty || buildVersion == normalizedDisplayVersion ? nil : buildVersion

        return UpdateRelease(
            displayVersion: normalizedDisplayVersion,
            buildVersion: normalizedBuildVersion,
            infoURL: appcastItem.infoURL
        )
    }

    private func respondToPendingChoice(with choice: SPUUserUpdateChoice) {
        let handler = pendingChoiceHandler
        pendingChoiceHandler = nil
        handler?(choice)
    }

    private func updateDownloadProgress() {
        guard let release = activeRelease else { return }

        let fractionCompleted: Double?
        if expectedDownloadBytes > 0 {
            fractionCompleted = Double(downloadedBytes) / Double(expectedDownloadBytes)
        } else if downloadedBytes > 0 {
            fractionCompleted = 0
        } else {
            fractionCompleted = nil
        }

        phase = .downloading(.init(release: release, fractionCompleted: fractionCompleted?.clamped(to: 0 ... 1)))
    }

    private func clearTransientState() {
        pendingChoiceHandler = nil
        downloadCancellationHandler = nil
        expectedDownloadBytes = 0
        downloadedBytes = 0
    }

    private static func currentInstalledRelease() -> UpdateRelease {
        let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayVersion = (shortVersion?.isEmpty == false ? shortVersion : buildVersion) ?? "Unknown"
        let normalizedBuildVersion = buildVersion?.isEmpty == false && buildVersion != displayVersion ? buildVersion : nil

        return UpdateRelease(displayVersion: displayVersion, buildVersion: normalizedBuildVersion, infoURL: nil)
    }

    private static func configurationIssue() -> String? {
        let infoDictionary = Bundle.main.infoDictionary ?? [:]
        let publicKey = (infoDictionary["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let feedURL = (infoDictionary["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if publicKey?.isEmpty != false {
            return "Sparkle is missing its embedded public key for this build. Run `just sparkle-public-key` and make sure `SPARKLE_PUBLIC_ED_KEY` matches the active NeoCode Sparkle key."
        }

        if feedURL?.isEmpty != false {
            return "Sparkle is missing an appcast feed URL in this build. Add SUFeedURL before shipping update-enabled builds."
        }

        return nil
    }

    private static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["NEOCODE_UI_TEST_MODE"] == "1"
    }

}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
