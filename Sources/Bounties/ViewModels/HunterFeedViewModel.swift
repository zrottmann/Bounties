#if os(iOS)
import Foundation
import CoreLocation
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

    func load(coordinate: CLLocationCoordinate2D? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            openBounties = try await marketplace.listOpenBounties(
                lat: coordinate.map { $0.latitude },
                lng: coordinate.map { $0.longitude }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func accept(bounty: Bounty) async {
        let serverID = bounty.serverID ?? bounty.id.uuidString
        do {
            _ = try await marketplace.acceptBounty(serverID: serverID, hunterID: hunterID)
            // Remove from open feed.
            openBounties.removeAll { $0.serverID == serverID || $0.id == bounty.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
