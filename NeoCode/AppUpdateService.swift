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

    func statusTitle(locale: Locale) -> String {
        switch phase {
        case .unavailable:
            return localized("Unavailable", locale: locale)
        case .idle:
            return automaticallyChecksForUpdates
                ? localized("Watching for releases", locale: locale)
                : localized("Automatic checks paused", locale: locale)
        case .checking:
            return localized("Checking now", locale: locale)
        case .available:
            return localized("Update available", locale: locale)
        case .downloading:
            return localized("Downloading", locale: locale)
        case .extracting:
            return localized("Preparing update", locale: locale)
        case .readyToInstall:
            return localized("Ready to install", locale: locale)
        case .installing:
            return localized("Installing", locale: locale)
        case .upToDate:
            return localized("Up to date", locale: locale)
        case .error:
            return localized("Update error", locale: locale)
        }
    }

    func statusDetail(locale: Locale) -> String {
        switch phase {
        case .unavailable(let message):
            return message
        case .idle:
            return automaticallyChecksForUpdates
                ? localized("NeoCode will keep checking GitHub releases in the background and surface new builds in the titlebar instead of interrupting you with a modal.", locale: locale)
                : localized("Automatic background checks are off. You can still ask Sparkle to check manually at any time.", locale: locale)
        case .checking:
            return localized("Sparkle is contacting the release feed and validating the latest signed build.", locale: locale)
        case .available(let release):
            return String(format: localized("Version %@ is ready to download. Use the blue titlebar control or the action below when you want to start it.", locale: locale), release.versionDescription)
        case .downloading(let progress):
            return String(format: localized("NeoCode is downloading version %@. The titlebar control mirrors the live percentage so you can keep working.", locale: locale), progress.release.versionDescription)
        case .extracting(let progress):
            return String(format: localized("Sparkle finished downloading version %@ and is unpacking it for installation.", locale: locale), progress.release.versionDescription)
        case .readyToInstall(let release):
            return String(format: localized("Version %@ is staged and ready. Install it when you are ready to relaunch NeoCode.", locale: locale), release.versionDescription)
        case .installing(let release):
            return String(format: localized("Sparkle is installing version %@. NeoCode may relaunch automatically when the process completes.", locale: locale), release.versionDescription)
        case .upToDate:
            return localized("You are already running the newest compatible signed release available from the appcast feed.", locale: locale)
        case .error(let message):
            return message
        }
    }

    func manualCheckButtonTitle(locale: Locale) -> String {
        canCheckForUpdates ? localized("Check now", locale: locale) : localized("Checking…", locale: locale)
    }

    func primaryActionTitle(locale: Locale) -> String? {
        switch phase {
        case .available(let release):
            return String(format: localized("Download %@", locale: locale), release.displayVersion)
        case .readyToInstall(let release):
            return String(format: localized("Install %@", locale: locale), release.displayVersion)
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
