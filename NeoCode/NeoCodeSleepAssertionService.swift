import Foundation
import IOKit.pwr_mgt

@MainActor
final class NeoCodeSleepAssertionService {
    private var assertionID: IOPMAssertionID = 0
    private var isActive = false

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active

        if active {
            acquireAssertion()
        } else {
            releaseAssertion()
        }
    }

    private func acquireAssertion() {
        guard assertionID == 0 else { return }

        let reason = "NeoCode is actively running work"
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )

        if result != kIOReturnSuccess {
            assertionID = 0
        }
    }

    private func releaseAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    deinit {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
        }
    }
}
