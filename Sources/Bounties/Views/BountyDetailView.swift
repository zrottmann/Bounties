#if os(iOS)
import SwiftUI
import BountiesKit

struct BountyDetailView: View {
    @State var vm: BountyDetailViewModel
    @State private var showEvidencePicker = false
    @State private var pendingStep: BountyStep?

    var body: some View {
        List {
            Section("Job") {
                Text(vm.bounty.description)
                if let summary = vm.bounty.summary {
                    Text(summary).foregroundColor(.secondary)
                }
                LabeledContent("Status", value: vm.bounty.status.rawValue.capitalized)
            }

            Section("Steps") {
                ForEach(vm.bounty.steps) { step in
                    StepRow(
                        step: step,
                        canApprove: vm.canApproveSteps && step.evidenceReference != nil && !step.isApproved,
                        canSubmitEvidence: vm.canSubmitEvidence && step.evidenceReference == nil && !step.isApproved,
                        onApprove: {
                            Task { await vm.approveStep(step) }
                        },
                        onSubmitEvidence: {
                            pendingStep = step
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
        // Evidence photo picker (simplified — in production use PHPickerViewController).
        .sheet(isPresented: $showEvidencePicker) {
            EvidencePickerView(onPick: { data in
                guard let step = pendingStep else { return }
                // Convert to a base-64 string as the evidence reference.
                let ref = data.base64EncodedString()
                Task { await vm.submitEvidence(for: step, reference: ref) }
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

// MARK: - Evidence picker shim

private struct EvidencePickerView: UIViewControllerRepresentable {
    let onPick: (Data) -> Void
    @Environment(\.dismiss) var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
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
