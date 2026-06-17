#if os(iOS)
import Foundation
import BountiesKit

// MARK: - Live on-device AI implementation
//
// v0.1.0 (TestFlight): uses StubBountyAIService which gives a deterministic
// 3-step breakdown. The real FoundationModels path (using LanguageModelSession
// with structured generation) is the next increment — avoiding @Generable macros
// here keeps the xtool-generated Xcode project buildable without extra plugin config.
//
// v0.2.0 plan: import FoundationModels, use session.respond(to:generating:) with
// a plain Codable struct (no @Generable macro), parse the on-device model output.

/// Returns the best available BountyAIService for this device.
func makeBountyAIService() -> any BountyAIService {
    return StubBountyAIService()
}
#endif
