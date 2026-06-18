#if os(iOS)
import SwiftUI
import BountiesKit

struct BountyDetailView: View {
    @State var vm: BountyDetailViewModel
    let marketplace: any MarketplaceService
    @State private var showEvidencePicker = false
    @State private var pendingStepIdx: Int?

    var body: some View {
        List {
            Section("Job") {
                Text(vm.bounty.description)
                if let summary = vm.bounty.summary {
                    Text(summary).foregroundColor(.secondary)
                }
                LabeledContent("Status", value: vm.bounty.status.rawValue.capitalized)
                if let km = vm.bounty.distanceKm {
                    LabeledContent("Distance", value: String(format: "%.1f km away", km))
                }
            }

            Section("Steps") {
                ForEach(vm.bounty.steps.indices, id: \.self) { idx in
                    let step = vm.bounty.steps[idx]
                    StepRow(
                        step: step,
                        canApprove: vm.canApproveSteps
                            && step.evidenceReference != nil && !step.isApproved,
                        canSubmitEvidence: vm.canSubmitEvidence
                            && step.evidenceReference == nil && !step.isApproved,
                        onApprove: {
                            Task { await vm.approveStep(at: idx) }
                        },
                        onSubmitEvidence: {
                            pendingStepIdx = idx
                            showEvidencePicker = true
                        }
                    )
                }
            }

            if vm.canApproveSteps {
                Section("Payout tracker") {
                    LabeledContent("Approved so far",
                                   value: FeeMath.formatted(cents: vm.bounty.approvedCents))
                    LabeledContent("Still pending",
                                   value: FeeMath.formatted(cents: vm.bounty.pendingCents))
                        .foregroundColor(.secondary)
                }
            }

            // Messages
            Section("Chat") {
                NavigationLink("Message Thread") {
                    MessageThreadView(bounty: vm.bounty, role: vm.role,
                                      marketplace: marketplace)
                }
            }

            // Dispute panel — available to holder, hunter, and reviewer.
            Section("Dispute") {
                NavigationLink("Dispute Panel") {
                    DisputeView(bounty: vm.bounty, role: vm.role,
                                marketplace: marketplace)
                }
            }

            if let err = vm.errorMessage {
                Section {
                    Text(err).foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Bounty Detail")
        .overlay {
            if vm.isBusy { ProgressView() }
        }
        .sheet(isPresented: $showEvidencePicker) {
            EvidencePickerView(onPick: { data in
                guard let idx = pendingStepIdx else { return }
                let ref = data.base64EncodedString()
                Task { await vm.submitEvidence(at: idx, base64Photo: ref) }
                showEvidencePicker = false
            })
        }
    }
}

// MARK: - Step row

private struct StepRow: View {
    let step: BountyStep
    let canApprove: Bool
    let canSubmitEvidence: Bool
    let onApprove: () -> Void
    let onSubmitEvidence: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: step.isApproved ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(step.isApproved ? .green : .secondary)
                Text(step.title)
                Spacer()
                Text(FeeMath.formatted(cents: step.amountCents))
                    .foregroundColor(.secondary)
            }

            if step.evidenceReference != nil && !step.isApproved {
                Text("Evidence submitted — awaiting approval")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if canSubmitEvidence {
                Button("Upload Evidence Photo") { onSubmitEvidence() }
                    .font(.caption)
                    .buttonStyle(.bordered)
            }

            if canApprove {
                Button("Approve Step") { onApprove() }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Evidence picker

private struct EvidencePickerView: UIViewControllerRepresentable {
    let onPick: (Data) -> Void
    @Environment(\.dismiss) var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject,
                              UINavigationControllerDelegate,
                              UIImagePickerControllerDelegate {
        let parent: EvidencePickerView
        init(_ parent: EvidencePickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage,
               let data = img.jpegData(compressionQuality: 0.7) {
                parent.onPick(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
