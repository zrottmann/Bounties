#if os(iOS)
import SwiftUI
import BountiesKit

@main
struct BountiesApp: App {
    @State private var role: AppRole = .holder

    // Live backend. Falls back to stub if the app is compiled without network
    // access (e.g. during CI snapshot tests).
    private let marketplace = BackendMarketplaceService()
    private let ai = makeBountyAIService()

    // Location service shared across all tabs.
    @State private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            ContentView(role: $role, marketplace: marketplace, ai: ai,
                        location: location)
                .task {
                    // Register for push notifications on launch.
                    let accountID = BackendMarketplaceService.loadOrCreateAccountID()
                    await PushRegistration.requestAndRegister(marketplace: marketplace,
                                                              accountID: accountID)
                }
        }
    }
}
#endif
