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
    /// Maximum price the holder will pay; offer surges from priceCents → maxPriceCents.
    var maxPriceCents: Int = 5000
    /// Hours over which the offer rises from priceCents to maxPriceCents.
    var surgeHours: Double = 2.0

    private(set) var phase: Phase = .idle
    private(set) var breakdown: BountyBreakdown?
    private(set) var postedBounty: Bounty?
    var errorMessage: String?
    /// Set to a `MarketplaceError.serviceUnavailable` to show the demand banner.
    var busyError: Error?

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
        // Seed priceCents from the AI market price, then apply to steps.
        // The holder can still adjust on the review screen.
        if result.suggestedMarketCents > 0 {
            priceCents    = result.suggestedMarketCents
            maxPriceCents = max(result.suggestedMarketCents,
                                Int(Double(result.suggestedMarketCents) * 2.0))
        }
        let reconciled = FeeMath.reconcile(steps: result.steps, to: priceCents)
        breakdown = BountyBreakdown(
            summary: result.summary,
            suggestedTotalCents: priceCents,
            steps: reconciled,
            suggestedMarketCents: result.suggestedMarketCents
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

    /// Called by the View when Apple Pay succeeds (or is unavailable / simulated).
    /// `applePayToken` is the base64 PKPaymentToken.paymentData from the sheet,
    /// or nil when Apple Pay is unavailable and we fall back to simulated funding.
    func fundingSucceeded(applePayToken: String?) async {
        guard let bd = breakdown else { return }
        // Pass photo as base64 so the backend can upload it to Appwrite Storage.
        let photoB64 = photoData.map { $0.base64EncodedString() }
        var bounty = Bounty(description: description, holderID: holderID,
                            photoReference: photoB64, steps: bd.steps,
                            basePriceCents: priceCents, maxPriceCents: maxPriceCents,
                            surgeHours: surgeHours, postedAt: .now)
        bounty.summary = bd.summary
        do {
            // 1. Post the bounty (creates it open/funded in state).
            let posted = try await marketplace.postBounty(bounty)
            // 2. If the marketplace is live and we have a server ID, call /fund.
            if marketplace.isLive, let sid = posted.serverID {
                if let live = marketplace as? BackendMarketplaceService {
                    try await live.fund(
                        bountyID: sid,
                        amountCents: priceCents,
                        applePayToken: applePayToken
                    )
                }
            }
            postedBounty = posted
            phase = .posted
        } catch let err as MarketplaceError where err.isBusy {
            busyError = err
            phase = .reviewing  // stay on review screen; banner appears
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
        maxPriceCents = 5000
        surgeHours = 2.0
        phase = .idle
        breakdown = nil
        postedBounty = nil
        errorMessage = nil
        busyError = nil
        usedFallback = false
    }
}
#endif
