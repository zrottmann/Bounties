#if os(iOS)
import Foundation
import BountiesKit

// MARK: - On-device AI service
//
// xtool-generated Xcode projects do not wire Swift macro plugins, so @Generable
// does not compile. Instead we use LanguageModelSession with a structured JSON
// prompt and parse the plain-text response ourselves.
//
// FoundationModels is only available on iOS 26+, so the whole implementation is
// wrapped in #if canImport(FoundationModels). On older OS the factory function
// returns the deterministic StubBountyAIService.
//
// Tier 1: Full LanguageModelSession with detailed instructions → JSON.
// Tier 2: Simpler prompt with fewer steps on context-window errors.
// Tier 3: StubBountyAIService — deterministic, always succeeds.

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
final class FoundationModelsBountyAI: BountyAIService, Sendable {

    func breakdown(description: String, photoContext: String?) async -> BountyBreakdown {
        // Model unavailable (iOS < 26, device lacks Apple Intelligence, quota/temp error).
        guard case .available = SystemLanguageModel.default.availability else {
            var result = await StubBountyAIService().breakdown(description: description,
                                                               photoContext: photoContext)
            result.summary = "AI suggestions unavailable right now — we've set up a default breakdown you can adjust below."
            return result
        }
        if let result = await tier1(description: description, photoContext: photoContext) {
            return result
        }
        if let result = await tier2(description: description) {
            return result
        }
        // All AI tiers failed — use stub but surface a friendly note.
        var result = await StubBountyAIService().breakdown(description: description,
                                                           photoContext: photoContext)
        result.summary = "AI suggestions unavailable right now — we've set up a default breakdown you can adjust below."
        return result
    }

    private func tier1(description: String, photoContext: String?) async -> BountyBreakdown? {
        let instructions = """
        You are a household-chore pricing assistant for the BountyHunter app. \
        When given a job description you ALWAYS respond with valid JSON and nothing else \
        (no markdown fences, no backticks, no explanation). Use this exact shape:
        {"summary":"<one sentence>","suggestedTotalCents":<integer>,"steps":[{"title":"<string>","amountCents":<integer>}]}
        Rules: 2–6 steps. Step amountCents must sum exactly to suggestedTotalCents. \
        Price range is $5–$300 (500–30000 cents). Keep step titles action-oriented and short.
        """
        let prompt = photoContext.map { "Job: \(description)\nPhoto context: \($0)" }
                     ?? "Job: \(description)"
        do {
            let session = LanguageModelSession(instructions: Instructions(instructions))
            let response = try await session.respond(to: Prompt(prompt))
            return parseBreakdown(from: response.content)
        } catch {
            return nil
        }
    }

    private func tier2(description: String) async -> BountyBreakdown? {
        let instructions = """
        Reply with ONLY JSON, no markdown. Shape: \
        {"summary":"short sentence","suggestedTotalCents":2500,"steps":[{"title":"Step","amountCents":1250},{"title":"Step 2","amountCents":1250}]}
        2–3 steps only. Amounts must sum to suggestedTotalCents.
        """
        do {
            let session = LanguageModelSession(instructions: Instructions(instructions))
            let response = try await session.respond(
                to: Prompt("Chore: \(description.prefix(200))"))
            return parseBreakdown(from: response.content)
        } catch {
            return nil
        }
    }

    private func parseBreakdown(from text: String) -> BountyBreakdown? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let jsonStr = String(text[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let summary = obj["summary"] as? String,
              let totalCents = obj["suggestedTotalCents"] as? Int,
              let rawSteps = obj["steps"] as? [[String: Any]],
              !rawSteps.isEmpty, totalCents > 0 else { return nil }
        let steps: [BountyStep] = rawSteps.compactMap { raw in
            guard let title = raw["title"] as? String,
                  let cents = raw["amountCents"] as? Int, cents > 0 else { return nil }
            return BountyStep(title: title, amountCents: cents)
        }
        guard !steps.isEmpty else { return nil }
        let reconciled = FeeMath.reconcile(steps: steps, to: totalCents)
        return BountyBreakdown(summary: summary, suggestedTotalCents: totalCents,
                               steps: reconciled)
    }
}
#endif // canImport(FoundationModels)

// MARK: - Factory

/// Returns the best available AI service for this device.
func makeBountyAIService() -> any BountyAIService {
#if canImport(FoundationModels)
    if #available(iOS 26, *),
       case .available = SystemLanguageModel.default.availability {
        return FoundationModelsBountyAI()
    }
#endif
    return StubBountyAIService()
}
#endif // os(iOS)
