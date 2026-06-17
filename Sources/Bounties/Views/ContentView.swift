#if os(iOS)
import SwiftUI
import BountiesKit

struct ContentView: View {
    @Binding var role: AppRole
    let marketplace: any MarketplaceService
    let ai: any BountyAIService

    var body: some View {
        TabView {
            if role == .holder {
                PostBountyView(
                    vm: PostBountyViewModel(ai: ai, marketplace: marketplace)
                )
                .tabItem { Label("Post", systemImage: "plus.circle.fill") }
            } else {
                HunterFeedView(
                    vm: HunterFeedViewModel(marketplace: marketplace),
                    marketplace: marketplace
                )
                .tabItem { Label("Find Bounties", systemImage: "magnifyingglass") }
            }

            SettingsView(role: $role)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
#endif
