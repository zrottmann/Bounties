import Foundation

// MARK: - AI output

/// The structured breakdown produced by the AI for a posted job.
public struct BountyBreakdown: Sendable, Equatable {
    /// One-sentence summary of the job.
    public var summary: String
    /// Fair market price suggestion in cents — the AI's estimate of the job's
    /// value based on comparable tasks. Used as the suggested base price in
    /// surge pricing; the holder may adjust it.
    public var suggestedTotalCents: Int
    /// Step-by-step breakdown. Amounts sum to `suggestedTotalCents` after
    /// `FeeMath.reconcile(steps:to:)` is applied.
    public var steps: [BountyStep]
    /// Explicit AI market-based starting price. When the AI returns a separate
    /// `marketPriceCents` field this differs from `suggestedTotalCents`; otherwise
    /// they are the same (backward-compatible).
    public var suggestedMarketCents: Int

    public init(summary: String, suggestedTotalCents: Int, steps: [BountyStep],
                suggestedMarketCents: Int? = nil) {
        self.summary = summary
        self.suggestedTotalCents = suggestedTotalCents
        self.steps = steps
        self.suggestedMarketCents = suggestedMarketCents ?? suggestedTotalCents
    }
}

// MARK: - Protocol

/// The AI seam: summarise the job, suggest a price, and produce steps.
/// The on-device FoundationModels implementation lives in the iOS app target;
/// the stub below works on any host (CI, macOS, unit tests) with no model.
public protocol BountyAIService: Sendable {
    /// Analyse the job description (and optional photo context) and return a
    /// structured breakdown. Never throws to a dead-end — callers always get
    /// a result, possibly from the stub fallback.
    func breakdown(description: String, photoContext: String?) async -> BountyBreakdown
}

// MARK: - Stub (deterministic, no model required)

/// A deterministic fake that always returns a sensible 3-step breakdown.
/// Used in unit tests and in the app when FoundationModels is unavailable.
public struct StubBountyAIService: BountyAIService {
    public init() {}

    public func breakdown(description: String, photoContext: String?) async -> BountyBreakdown {
        // Short simulated latency so loading states are exercisable.
        try? await Task.sleep(nanoseconds: 300_000_000)

        let total = 2500 // $25.00 flat stub price
        let steps = FeeMath.reconcile(steps: [
            BountyStep(title: "Prepare and gather supplies", amountCents: 800),
            BountyStep(title: "Complete the main task",      amountCents: 1200),
            BountyStep(title: "Clean up and confirm done",   amountCents: 500),
        ], to: total)

        return BountyBreakdown(
            summary: "Complete the requested household task and tidy up afterwards.",
            suggestedTotalCents: total,
            steps: steps
        )
    }
}
