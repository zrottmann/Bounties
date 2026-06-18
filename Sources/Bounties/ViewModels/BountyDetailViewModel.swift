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
    /// Set to a `MarketplaceError.serviceUnavailable` when the backend is busy.
    var busyError: Error?

    let role: AppRole
    private let marketplace: any MarketplaceService
    private let accountID: String

    init(bounty: Bounty, marketplace: any MarketplaceService, role: AppRole) {
        self.bounty = bounty
        self.marketplace = marketplace
        self.role = role
        self.accountID = BackendMarketplaceService.loadOrCreateAccountID()
    }

    // MARK: - Hunter: submit step evidence

    func submitEvidence(at stepIdx: Int, base64Photo: String) async {
        guard stepIdx < bounty.steps.count else { return }
        let serverID = bounty.serverID ?? bounty.id.uuidString
        isBusy = true
        defer { isBusy = false }
        do {
            bounty = try await marketplace.submitEvidence(serverBountyID: serverID,
                                                         stepIdx: stepIdx,
                                                         base64Photo: base64Photo)
        } catch let err as MarketplaceError where err.isBusy {
            busyError = err
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Holder: approve step

    func approveStep(at stepIdx: Int) async {
        guard stepIdx < bounty.steps.count else { return }
        let step = bounty.steps[stepIdx]
        let serverID = bounty.serverID ?? bounty.id.uuidString
        isBusy = true
        defer { isBusy = false }
        do {
            let updated = try await marketplace.approveStep(serverBountyID: serverID,
                                                           stepIdx: stepIdx,
                                                           accountID: accountID)
            ledger.recordApproval(bountyID: bounty.id, stepID: step.id,
                                  amountCents: step.amountCents)
            bounty = updated
        } catch let err as MarketplaceError where err.isBusy {
            busyError = err
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Display helpers

    var canApproveSteps: Bool  { role == .holder || role == .reviewer }
    var canSubmitEvidence: Bool { role == .hunter }

    var totalEarnedDisplay: String {
        FeeMath.formatted(cents: ledger.earnedCents(for: bounty.id))
    }
}
#endif
