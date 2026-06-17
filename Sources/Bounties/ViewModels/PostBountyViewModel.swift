#if os(iOS)
import Foundation
import Observation
import BountiesKit

@MainActor
@Observable
final class PostBountyViewModel {
    enum Phase: Equatable {
        case idle
        case analyzing  // AI is working
        case reviewing  // holder is reviewing the AI breakdown
        case funding    // Apple Pay in flight
        case posted     // bounty is live
    }

    var description: String = ""
    var photoData: Data?        // raw JPEG from picker/camera
    var priceCents: Int = 2500  // holder's agreed total ($25 default)

    private(set) var phase: Phase = .idle
    private(set) var breakdown: BountyBreakdown?
    private(set) var postedBounty: Bounty?
    var errorMessage: String?

    private(set) var usedFallback = false

    // Injected services.
    private let ai: BountyAIService
    private let marketplace: any MarketplaceService
    private let holderID: String

    init(ai: BountyAIService = StubBountyAIService(),
         marketplace: any MarketplaceService = StubMarketplaceService(),
         holderID: String = "local-holder") {
        self.ai = ai
        self.marketplace = marketplace
        self.holderID = holderID
    }

    // MARK: - Step 1: Analyse with AI

    func analyze() async {
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !desc.isEmpty else {
            errorMessage = "Describe what you need done — a sentence is enough."
            return
        }
        errorMessage = nil
        phase = .analyzing
        let result = await ai.breakdown(description: desc, photoContext: nil)
        // Apply the holder's set price to the AI steps.
        let reconciled = FeeMath.reconcile(steps: result.steps, to: priceCents)
        breakdown = BountyBreakdown(
            summary: result.summary,
            suggestedTotalCents: priceCents,
            steps: reconciled
        )
        phase = .reviewing
    }

    // MARK: - Derived display helpers

    var appFeeCents: Int { FeeMath.appFeeCents(totalCents: priceCents) }
    var hunterPayoutCents: Int { FeeMath.hunterPayoutCents(totalCents: priceCents) }

    // MARK: - Step 2: Holder confirms → Apple Pay

    /// Called when the holder taps "Fund Bounty" after reviewing the breakdown.
    /// The caller (View) drives the actual PKPaymentAuthorizationController;
    /// this VM just advances the phase and records the result.
    func beginFunding() {
        guard breakdown != nil else { return }
        phase = .funding
    }

    /// Called by the View when Apple Pay succeeds (paymentToken is the PKPayment token
    /// data — stored for the future backend; ignored in stub mode).
    func fundingSucceeded(paymentToken: Data?) async {
        guard let bd = breakdown else { return }
        var bounty = Bounty(description: description, holderID: holderID,
                            photoReference: nil, steps: bd.steps)
        bounty.summary = bd.summary
        do {
            postedBounty = try await marketplace.postBounty(bounty)
            phase = .posted
        } catch {
            errorMessage = error.localizedDescription
            phase = .reviewing
        }
    }

    func fundingCancelled() {
        phase = .reviewing
    }

    func reset() {
        description = ""
        photoData = nil
        priceCents = 2500
        phase = .idle
        breakdown = nil
        postedBounty = nil
        errorMessage = nil
        usedFallback = false
    }
}
#endif
