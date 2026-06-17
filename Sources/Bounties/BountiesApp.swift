#if os(iOS)
import SwiftUI
import BountiesKit

@main
struct BountiesApp: App {
    @State private var role: AppRole = .holder
    // Shared marketplace stub for v1 (same instance across all tabs).
    private let marketplace = StubMarketplaceService()
    private let ai = makeBountyAIService()

    var body: some Scene {
        WindowGroup {
            ContentView(role: $role, marketplace: marketplace, ai: ai)
        }
    }
}
#endif
