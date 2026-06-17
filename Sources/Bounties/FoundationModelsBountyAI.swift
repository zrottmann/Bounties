#if os(iOS)
import Foundation
import FoundationModels
import BountiesKit

// MARK: - Generable schemas

/// The on-device model produces this struct for each step.
@available(iOS 26, *)
@Generable
struct AIStep: Sendable {
    @Guide(description: "Short imperative title for this task step, e.g. 'Rake leaves into piles'")
    var title: String
    @Guide(description: "Fair price for this step in US dollars (integer, e.g. 8 for $8)")
    var amountDollars: Int
}

/// Top-level structured output from the on-device model.
@available(iOS 26, *)
@Generable
struct AIBreakdown: Sendable {
    @Guide(description: "One sentence summarising the job for the hunter")
    var summary: String
    @Guide(description: "Fair total price in US dollars for completing the whole job")
    var suggestedTotalDollars: Int
    @Guide(description: "The job broken into the smallest sensible steps. Each step must have a positive price. Step prices must sum to suggestedTotalDollars.")
    var steps: [AIStep]
}

// MARK: - Live implementation

/// On-device FoundationModels implementation of `BountyAIService`.
/// Mirrors AiHandy's resilient scope+quote pattern:
///   1. Full model attempt with the rich schema.
///   2. Compact fallback attempt (simplified prompt, same schema).
///   3. No-model heuristic stub — always produces a result.
@available(iOS 26, *)
struct FoundationModelsBountyAI: BountyAIService {
    func breakdown(description: String, photoContext: String?) async -> BountyBreakdown {
        let stub = StubBountyAIService()
        // Gate: model available?
        guard case .available = SystemLanguageModel.default.availability else {
            return await stub.breakdown(description: description, photoContext: photoContext)
        }
        // Try full model, then compact fallback, then the deterministic stub.
        // This mirrors AiHandy's resilient pattern — never dead-ends.
        if let result = await attempt(description: description, compact: false) {
            return result
        }
        if let result = await attempt(description: description, compact: true) {
            return result
        }
        return await stub.breakdown(description: description, photoContext: photoContext)
    }

    private func attempt(description: String, compact: Bool) async -> BountyBreakdown? {
        let session = LanguageModelSession()
        let prompt: String
        if compact {
            prompt = "List 2-3 steps for: \(description). Give a fair price per step."
        } else {
            prompt = """
            A homeowner needs help with: "\(description)"
            Break this job into the SMALLEST sensible steps (2-5 steps).
            For each step: write a short imperative title and a fair US dollar price.
            Step prices must sum exactly to the suggested total.
            Keep it practical and fair for both sides.
            """
        }
        do {
            let result = try await session.respond(
                to: prompt,
                generating: AIBreakdown.self,
                includeSchemaInPrompt: false
            )
            let bd = result.content
            // Validate: at least one step, positive total.
            guard !bd.steps.isEmpty, bd.suggestedTotalDollars > 0 else { return nil }
            let steps = bd.steps.map {
                BountyStep(title: $0.title, amountCents: $0.amountDollars * 100)
            }
            let targetCents = bd.suggestedTotalDollars * 100
            let reconciled = FeeMath.reconcile(steps: steps, to: targetCents)
            return BountyBreakdown(summary: bd.summary,
                                   suggestedTotalCents: targetCents,
                                   steps: reconciled)
        } catch {
            return nil
        }
    }
}

// MARK: - Availability shim

/// Returns the best available BountyAIService for this device.
func makeBountyAIService() -> any BountyAIService {
    if #available(iOS 26, *) {
        return FoundationModelsBountyAI()
    } else {
        return StubBountyAIService()
    }
}
#endif
