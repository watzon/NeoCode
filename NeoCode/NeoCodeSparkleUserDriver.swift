import Foundation
import Sparkle

@MainActor
final class NeoCodeSparkleUserDriver: NSObject, SPUUserDriver {
    weak var service: AppUpdateService?

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        service?.handleUserInitiatedUpdateCheckStarted()
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let isInformationalUpdate = appcastItem.fileURL == nil && appcastItem.infoURL != nil
        if isInformationalUpdate {
            service?.handleInformationalUpdate(appcastItem: appcastItem)
            reply(SPUUserUpdateChoice(rawValue: 2)!)
            return
        }

        service?.handleUpdateFound(appcastItem: appcastItem, stageRawValue: Int(state.stage.rawValue), reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        service?.handleUpdateNotFound(error: error, acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        service?.handleUpdaterError(error, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        service?.handleDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        service?.handleExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        service?.handleDownloadedData(length: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        service?.handleExtractionStarted()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        service?.handleExtractionProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        service?.handleReadyToInstall(reply: reply)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        service?.handleInstallingUpdate()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        service?.handleInstalledUpdate(acknowledgement: acknowledgement)
    }

    func dismissUpdateInstallation() {
        service?.handleDismissedUpdateFlow()
    }
}
