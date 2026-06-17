#if os(iOS)
import SwiftUI

struct SettingsView: View {
    @Binding var role: AppRole

    // Version label — required by project standards.
    private let version: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Bounties v\(v) (\(b))"
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Role") {
                    Picker("I am a", selection: $role) {
                        ForEach(AppRole.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(role == .holder
                         ? "Post jobs and fund bounties."
                         : "Browse open bounties and earn money.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: version)
                    Text("Bounties — Uber for household chores. Post a job, fund it with Apple Pay, and hunters complete it step by step with evidence photos.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Next Steps (Future)") {
                    Text("Real Appwrite marketplace backend")
                    Text("Hunter bank payouts (Stripe / ACH)")
                    Text("Location / geofencing for nearby jobs")
                    Text("In-app messaging between holder and hunter")
                    Text("Reviewer / dispute panel")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
#endif
