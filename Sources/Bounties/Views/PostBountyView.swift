#if os(iOS)
import SwiftUI
import BountiesKit
// Apple Pay is wired via ApplePayFunding.swift (PassKit). The entitlement
// merchant.com.zrottmann.bounties is provisioned on the App ID. When Apple Pay
// is unavailable on a given device/simulator, presentApplePay immediately calls
// onCancel and the VM falls back to simulated funding (no charge).

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
        .navigationTitle("Post a Job")
        .busyBannerForError($vm.busyError) {
            // Retry: stay on reviewing phase — user taps Pay again.
        }
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

            if let market = vm.breakdown?.suggestedMarketCents, market != vm.priceCents {
                Section {
                    Label(
                        "AI market price: \(FeeMath.formatted(cents: market))",
                        systemImage: "sparkles"
                    )
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
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

            Section("Surge pricing") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Starting offer")
                        .font(.caption).foregroundColor(.secondary)
                    PriceSlider(cents: $vm.priceCents)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max offer (if no one accepts quickly)")
                        .font(.caption).foregroundColor(.secondary)
                    PriceSlider(cents: $vm.maxPriceCents)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rises to max over: \(surgeLabel(vm.surgeHours))")
                        .font(.caption).foregroundColor(.secondary)
                    Slider(value: $vm.surgeHours, in: 0.5...12.0, step: 0.5)
                }
                .onChange(of: vm.maxPriceCents) { _, new in
                    // Keep max ≥ base.
                    if new < vm.priceCents { vm.maxPriceCents = vm.priceCents }
                }
            }

            Section("Payment breakdown") {
                LabeledContent("Starting offer",
                               value: FeeMath.formatted(cents: vm.priceCents))
                LabeledContent("Max offer",
                               value: FeeMath.formatted(cents: vm.maxPriceCents))
                LabeledContent("Platform fee (1%)",
                               value: FeeMath.formatted(cents: vm.appFeeCents))
                    .foregroundColor(.secondary)
                LabeledContent("Hunter receives (min)",
                               value: FeeMath.formatted(cents: vm.hunterPayoutCents))
                    .bold()
            }

            Section {
                ApplePayFundButton(vm: vm)
                Button("Edit") { vm.reset() }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Review Breakdown")
    }

    private func surgeLabel(_ hours: Double) -> String {
        if hours < 1 { return "\(Int(hours * 60))m" }
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

// MARK: - Apple Pay fund button
// Presents the real Apple Pay sheet when available; falls back to simulated
// funding (no charge) on devices / simulators where Apple Pay can't run.

private struct ApplePayFundButton: View {
    @State var vm: PostBountyViewModel

    var body: some View {
        Button(action: fund) {
            Label(
                applePayAvailable() ? "Pay with Apple Pay" : "Fund Bounty (Simulated)",
                systemImage: applePayAvailable() ? "apple.logo" : "checkmark.circle"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(applePayAvailable() ? .black : .green)
    }

    private func fund() {
        vm.beginFunding()
        if applePayAvailable() {
            Task {
                await MainActor.run {
                    presentApplePay(
                        amountCents: vm.priceCents,
                        onToken: { token in
                            Task { await vm.fundingSucceeded(applePayToken: token) }
                        },
                        onCancel: {
                            vm.fundingCancelled()
                        }
                    )
                }
            }
        } else {
            // Apple Pay unavailable — simulate immediately (demo/TestFlight safe).
            Task { await vm.fundingSucceeded(applePayToken: nil) }
        }
    }
}

// MARK: - Funding / waiting view (Uber-style "finding hunters" screen)

private struct FundingView: View {
    @State var vm: PostBountyViewModel
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            // Pulsing circle animation — grows/shrinks to signal activity.
            ZStack {
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(1 + 0.1 * sin(elapsed * 2))
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.accentColor)
            }
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                        value: elapsed)

            VStack(spacing: 8) {
                Text("Finding nearby hunters…")
                    .font(.title2.bold())
                Text("Your offer starts at \(FeeMath.formatted(cents: vm.priceCents))")
                    .foregroundColor(.secondary)
                if vm.maxPriceCents > vm.priceCents {
                    Text("and rises to \(FeeMath.formatted(cents: vm.maxPriceCents)) if no one accepts yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
        .navigationTitle("Finding Hunters")
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                elapsed += 0.05
            }
        }
        .onDisappear { timer?.invalidate() }
    }
}

// MARK: - Posted confirmation (transitions from "finding" to "live")

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

            // Show the live offer range if surge is configured.
            if bounty.maxPriceCents > bounty.basePriceCents {
                HStack(spacing: 4) {
                    Text("Offer:")
                        .foregroundColor(.secondary)
                    Text("\(FeeMath.formatted(cents: bounty.basePriceCents)) → \(FeeMath.formatted(cents: bounty.maxPriceCents))")
                        .bold()
                }
                Text(SurgePricing.countdownLabel(surgeHours: bounty.surgeHours,
                                                 postedAt: bounty.postedAt))
                    .font(.caption)
                    .foregroundColor(.accentColor)
            } else {
                Text(FeeMath.formatted(cents: bounty.totalCents))
                    .font(.title2.bold())
            }

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

#endif
