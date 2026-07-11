import SwiftUI

struct LedgerIntegrityIssueSection: View {
    let issues: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Issues")
                .font(.headline)
            ForEach(issues, id: \.self) { issue in
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }
}
