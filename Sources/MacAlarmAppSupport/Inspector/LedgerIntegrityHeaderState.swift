import MacAlarmCore
import SwiftUI

struct LedgerIntegrityHeaderState {
    var subtitle: String
    var tintColor: Color

    init(
        snapshot: LedgerIntegritySnapshot?,
        isLoading: Bool,
        errorMessage: String?
    ) {
        if isLoading {
            subtitle = "Verifying HMAC chain"
            tintColor = .secondary
            return
        }

        if let errorMessage {
            subtitle =
                if errorMessage.localizedCaseInsensitiveContains("HMAC key") {
                    "Recorder setup needed"
                } else {
                    "Verification unavailable"
                }
            tintColor = .orange
            return
        }

        guard let snapshot else {
            subtitle = "Waiting for verification"
            tintColor = .secondary
            return
        }

        subtitle = snapshot.verification.isValid ? "HMAC chain verified" : "Ledger integrity issue"
        tintColor = snapshot.verification.isValid ? .green : .red
    }
}
