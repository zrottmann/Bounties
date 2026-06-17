#if os(iOS)
import Foundation
import Observation
import BountiesKit

@MainActor
@Observable
final class BountyDetailViewModel {
    private(set) var bounty: Bounty
    private(set) var ledger = BountyLedger()
    private(set) var isBusy = false
    var errorMessage: String?

    private let marketplace: any MarketplaceService
    private let role: AppRole

    init(bounty: Bounty, marketplace: any MarketplaceService, role: AppRole) {
        self.bounty = bounty
        self.marketplace = marketplace
        self.role = role
    }

    // MARK: - Hunter: submit step evidence

    func submitEvidence(for step: BountyStep, reference: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            bounty = try await marketplace.submitEvidence(
                bountyID: bounty.id, stepID: step.id, reference: reference)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Holder: approve step

    func approveStep(_ step: BountyStep) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let updated = try await marketplace.approveStep(bountyID: bounty.id, stepID: step.id)
            // Record in ledger.
            ledger.recordApproval(bountyID: bounty.id, stepID: step.id,
                                  amountCents: step.amountCents)
            bounty = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Display helpers

    var canApproveSteps: Bool { role == .holder }
    var canSubmitEvidence: Bool { role == .hunter }

    var totalEarnedDisplay: String {
        FeeMath.formatted(cents: ledger.earnedCents(for: bounty.id))
    }
}
#endif
