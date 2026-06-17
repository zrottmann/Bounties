#if os(iOS)
import SwiftUI
import BountiesKit
// NOTE: Apple Pay (PassKit) is stubbed for this first TestFlight build.
// The PKPaymentAuthorizationController integration requires an Apple Pay
// merchant ID entitlement in the provisioning profile. To keep signing simple
// for TestFlight v0.1.0, the funding screen shows "Coming Soon" instead of
// launching the real payment sheet. See DESIGN.md § Next Increments.
// Re-enable by: adding merchant.com.zrottmann.bounties to the App ID,
// generating a new profile, importing PassKit, and restoring ApplePayButton.

struct PostBountyView: View {
    @State var vm: PostBountyViewModel

    var body: some View {
        NavigationStack {
            switch vm.phase {
            case .idle, .analyzing:
                InputForm(vm: vm)
            case .reviewing:
                BreakdownReview(vm: vm)
            case .funding:
                FundingView(vm: vm)
            case .posted:
                PostedConfirmation(bounty: vm.postedBounty!)
            }
        }
        .navigationTitle("Post a Bounty")
    }
}

// MARK: - Input form

private struct InputForm: View {
    @State var vm: PostBountyViewModel
    @State private var showPicker = false

    var body: some View {
        Form {
            Section("What do you need done?") {
                TextEditor(text: $vm.description)
                    .frame(minHeight: 80)
                    .accessibilityLabel("Job description")
            }

            Section("Your price") {
                PriceSlider(cents: $vm.priceCents)
            }

            Section("Photo (optional)") {
                Button("Attach a photo") { showPicker = true }
                    .sheet(isPresented: $showPicker) {
                        PhotoPickerView(imageData: $vm.photoData)
                    }
                if vm.photoData != nil {
                    Label("Photo attached", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            if let err = vm.errorMessage {
                Section {
                    Text(err).foregroundColor(.red)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if vm.phase == .analyzing {
                    ProgressView()
                } else {
                    Button("Analyze") {
                        Task { await vm.analyze() }
                    }
                    .disabled(vm.description.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Price slider (cents)

private struct PriceSlider: View {
    @Binding var cents: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(FeeMath.formatted(cents: cents))
                .font(.title2.bold())
            Slider(value: Binding(
                get: { Double(cents) },
                set: { cents = Int($0) }
            ), in: 500...50000, step: 100)
            HStack {
                Text("$5").foregroundColor(.secondary)
                Spacer()
                Text("$500").foregroundColor(.secondary)
            }
            .font(.caption)
        }
    }
}

// MARK: - Breakdown review

private struct BreakdownReview: View {
    @State var vm: PostBountyViewModel

    var body: some View {
        List {
            Section("Job summary") {
                Text(vm.breakdown?.summary ?? "").foregroundColor(.secondary)
            }

            Section("Step-by-step breakdown") {
                ForEach(vm.breakdown?.steps ?? []) { step in
                    HStack {
                        Text(step.title)
                        Spacer()
                        Text(FeeMath.formatted(cents: step.amountCents))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Payment breakdown") {
                LabeledContent("Total you pay",
                               value: FeeMath.formatted(cents: vm.priceCents))
                LabeledContent("Platform fee (1%)",
                               value: FeeMath.formatted(cents: vm.appFeeCents))
                    .foregroundColor(.secondary)
                LabeledContent("Hunter receives",
                               value: FeeMath.formatted(cents: vm.hunterPayoutCents))
                    .bold()
            }

            Section {
                // v0.1.0: Apple Pay is coming — tapping "Fund" simulates payment
                // so the holder flow is exercisable end-to-end in TestFlight.
                Button("Fund Bounty (Coming Soon)") {
                    Task { await vm.fundingSucceeded(paymentToken: nil) }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                Button("Edit") { vm.reset() }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Review Breakdown")
    }
}

// MARK: - Funding view (stub — Apple Pay wired in next increment)

private struct FundingView: View {
    @State var vm: PostBountyViewModel

    var body: some View {
        VStack(spacing: 24) {
            ProgressView("Posting bounty…")
        }
        .navigationTitle("Funding")
        .task {
            // Stub: immediately succeed so the holder flow works in TestFlight.
            await vm.fundingSucceeded(paymentToken: nil)
        }
    }
}

// MARK: - Posted confirmation

private struct PostedConfirmation: View {
    let bounty: Bounty

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            Text("Bounty Posted!")
                .font(.title.bold())
            Text("Hunters nearby can now see and accept your job.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Text(FeeMath.formatted(cents: bounty.totalCents))
                .font(.title2.bold())
            ForEach(bounty.steps) { step in
                HStack {
                    Text(step.title)
                    Spacer()
                    Text(FeeMath.formatted(cents: step.amountCents))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .padding()
    }
}

// MARK: - Minimal photo picker shim

private struct PhotoPickerView: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: PhotoPickerView
        init(_ parent: PhotoPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.imageData = img.jpegData(compressionQuality: 0.8)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Apple Pay button wrapper (STUB for v0.1.0 TestFlight)
// Real PKPaymentAuthorizationController implementation is the next increment.
// Stubbed here so signing succeeds without an Apple Pay merchant entitlement.

private struct ApplePayButton: UIViewRepresentable {
    let totalCents: Int
    let onSuccess: (Data?) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle("Fund Bounty (Coming Soon)", for: .normal)
        btn.backgroundColor = .systemGreen
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 10
        return btn
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        uiView.removeTarget(nil, action: nil, for: .allEvents)
        uiView.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
    }

    final class Coordinator: NSObject {
        let parent: ApplePayButton
        init(_ parent: ApplePayButton) { self.parent = parent }

        @objc func tap() {
            // Stub: simulate immediate payment success so the holder flow
            // is exercisable in TestFlight without the merchant entitlement.
            parent.onSuccess(nil)
        }

    }
}
#endif
