#if os(iOS)
import Foundation
import Observation
import BountiesKit

@MainActor
@Observable
final class HunterFeedViewModel {
    private(set) var openBounties: [Bounty] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let marketplace: any MarketplaceService
    private let hunterID: String

    init(marketplace: any MarketplaceService = StubMarketplaceService(),
         hunterID: String = "local-hunter") {
        self.marketplace = marketplace
        self.hunterID = hunterID
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            openBounties = try await marketplace.listOpenBounties()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func accept(bounty: Bounty) async {
        do {
            let updated = try await marketplace.acceptBounty(id: bounty.id, hunterID: hunterID)
            // Replace in list.
            if let idx = openBounties.firstIndex(where: { $0.id == updated.id }) {
                openBounties.remove(at: idx)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
