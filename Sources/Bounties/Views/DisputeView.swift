#if os(iOS)
import SwiftUI
import BountiesKit

// MARK: - Dispute panel (reviewer + holder/hunter escalation)
//
// Reviewer role: sees the evidence photo, can resolve any open dispute.
// Holder/Hunter: can open a dispute on a step where evidence was submitted.

struct DisputeView: View {
    let bounty: Bounty
    let role: AppRole
    let marketplace: any MarketplaceService

    @State private var disputes: [BountyDispute] = []
    @State private var showOpenDispute = false
    @State private var selectedStep: BountyStep?
    @State private var disputeReason = ""
    @State private var resolveText = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    private var accountID: String { BackendMarketplaceService.loadOrCreateAccountID() }
    private var serverBountyID: String { bounty.serverID ?? bounty.id.uuidString }

    // Steps that have pending evidence and no approved status yet.
    private var disputeableSteps: [BountyStep] {
        bounty.steps.filter { $0.evidenceReference != nil && !$0.isApproved }
    }

    var body: some View {
        List {
            Section("Bounty") {
                Text(bounty.description)
                LabeledContent("Status", value: bounty.status.rawValue.capitalized)
            }

            Section("Evidence") {
                ForEach(bounty.steps.indices, id: \.self) { idx in
                    let step = bounty.steps[idx]
                    VStack(alignment: .leading, spacing: 4) {
                        Label(step.title, systemImage: step.isApproved
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(step.isApproved ? .green : .primary)
                        if step.evidenceReference != nil {
                            Text("Evidence uploaded")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            if !disputes.isEmpty {
                Section("Disputes") {
                    ForEach(disputes) { dispute in
                        DisputeRow(dispute: dispute,
                                   canResolve: role == .reviewer && dispute.state == "open",
                                   resolveText: $resolveText,
                                   onResolve: {
                            Task { await resolve(dispute: dispute) }
                        })
                    }
                }
            }

            if let err = errorMessage {
                Section {
                    Text(err).foregroundColor(.red)
                }
            }

            // Holder or hunter can open a dispute on a step with evidence.
            if role != .reviewer && !disputeableSteps.isEmpty {
                Section {
                    Button("Open a Dispute") { showOpenDispute = true }
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Dispute Panel")
        .overlay { if isBusy { ProgressView() } }
        .sheet(isPresented: $showOpenDispute) {
            OpenDisputeSheet(
                steps: disputeableSteps,
                selectedStep: $selectedStep,
                reason: $disputeReason,
                onSubmit: {
                    Task { await openDispute() }
                    showOpenDispute = false
                },
                onCancel: { showOpenDispute = false }
            )
        }
        .task { await loadDisputes() }
    }

    private func loadDisputes() async {
        // Backend returns disputes on the bounty in the approve-step response;
        // we fetch by listing open bounties for now — stub returns empty array.
        // In production, add GET /disputes?bountyId= to the backend.
        disputes = []  // placeholder; backend v2 will add a /disputes endpoint
    }

    private func openDispute() async {
        guard let step = selectedStep,
              let idx = bounty.steps.firstIndex(where: { $0.id == step.id }) else { return }
        let reason = disputeReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let d = try await marketplace.openDispute(serverBountyID: serverBountyID,
                                                      stepIdx: idx,
                                                      accountID: accountID,
                                                      reason: reason)
            disputes.append(d)
            disputeReason = ""
            selectedStep = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolve(dispute: BountyDispute) async {
        let resolution = resolveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolution.isEmpty else {
            errorMessage = "Enter a resolution before submitting."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let updated = try await marketplace.resolveDispute(disputeID: dispute.id,
                                                               resolution: resolution,
                                                               accountID: accountID)
            if let idx = disputes.firstIndex(where: { $0.id == updated.id }) {
                disputes[idx] = updated
            }
            resolveText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Subviews

private struct DisputeRow: View {
    let dispute: BountyDispute
    let canResolve: Bool
    @Binding var resolveText: String
    let onResolve: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Step \(dispute.stepIdx + 1): \(dispute.reason)",
                  systemImage: dispute.state == "resolved"
                  ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(dispute.state == "resolved" ? .green : .orange)

            if let res = dispute.resolution {
                Text("Resolution: \(res)").font(.caption).foregroundColor(.secondary)
            }

            if canResolve {
                TextField("Resolution…", text: $resolveText)
                    .textFieldStyle(.roundedBorder)
                Button("Resolve Dispute", action: onResolve)
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct OpenDisputeSheet: View {
    let steps: [BountyStep]
    @Binding var selectedStep: BountyStep?
    @Binding var reason: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Which step?") {
                    Picker("Step", selection: $selectedStep) {
                        Text("Choose…").tag(Optional<BountyStep>.none)
                        ForEach(steps) { step in
                            Text(step.title).tag(Optional(step))
                        }
                    }
                }
                Section("Reason") {
                    TextEditor(text: $reason)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Open Dispute")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { onSubmit() }
                        .disabled(selectedStep == nil
                                  || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
#endif
