#if os(iOS)
import SwiftUI
import BountiesKit

struct ContentView: View {
    @Binding var role: AppRole
    let marketplace: any MarketplaceService
    let ai: any BountyAIService
    let location: LocationService

    private var accountID: String { BackendMarketplaceService.loadOrCreateAccountID() }

    var body: some View {
        TabView {
            switch role {
            case .holder:
                PostBountyView(
                    vm: PostBountyViewModel(ai: ai, marketplace: marketplace,
                                            holderID: accountID)
                )
                .tabItem { Label("Post", systemImage: "plus.circle.fill") }

            case .hunter:
                HunterFeedView(
                    vm: HunterFeedViewModel(marketplace: marketplace,
                                            hunterID: accountID),
                    marketplace: marketplace,
                    location: location
                )
                .tabItem { Label("Find Bounties", systemImage: "magnifyingglass") }

            case .reviewer:
                ReviewerFeedView(marketplace: marketplace, location: location)
                    .tabItem { Label("Review", systemImage: "checkmark.shield.fill") }
            }

            SettingsView(role: $role)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
#endif
