#if os(iOS)
import SwiftUI

struct SettingsView: View {
    @Binding var role: AppRole

    @AppStorage("bounties_api_base_url")
    private var apiBaseURL: String = "https://bounties-api.appwrite.network"

    // Version label — required by project standards.
    private let version: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "3"
        return "BountyHunter v\(v) (\(b))"
    }()

    private var roleDescription: String {
        switch role {
        case .holder:   return "Post jobs and fund bounties."
        case .hunter:   return "Browse open bounties and earn money."
        case .reviewer: return "Inspect evidence and resolve disputes."
        }
    }

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
                    Text(roleDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Backend") {
                    TextField("API Base URL", text: $apiBaseURL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    Text("Default: https://bounties-api.appwrite.network")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Section("Money (Simulated)") {
                    Label("Apple Pay funding is simulated", systemImage: "creditcard")
                    Label("Hunter payouts are ledger-only", systemImage: "banknote")
                    Text("Real charges and payouts are gated on owner Stripe Connect setup.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: version)
                    Text("BountyHunter — Uber for household chores. Post a job, fund it, and hunters complete it step by step with evidence photos.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Owner-gated (coming soon)") {
                    Text("Real Apple Pay charges (merchant entitlement)")
                    Text("Hunter bank payouts (Stripe Connect)")
                    Text("APNs push key (owner to add in ASC)")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
#endif
