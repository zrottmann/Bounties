import Foundation

// MARK: - Fee math

/// All pricing arithmetic for the Bounties marketplace.
///
/// The app charges a 1% platform fee on every funded bounty.
/// Hunters receive 99% of the total; the app retains 1%.
/// Rounding: integer truncation is used for the fee (floor); the
/// remainder stays with the hunter (conservative for the platform).
///
/// Step amounts must re-sum exactly to the holder-agreed total.
/// When the AI produces steps that don't divide evenly, the rounding
/// remainder is added to the LAST step so the invariant holds.
public enum FeeMath {

    /// The platform takes 1 % (as a fraction: 0.01).
    public static let feeRate: Double = 0.01

    /// Platform fee in cents for a given total, rounded DOWN (floor).
    /// Minimum fee is 1 cent when total > 0.
    public static func appFeeCents(totalCents: Int) -> Int {
        guard totalCents > 0 else { return 0 }
        let raw = Int((Double(totalCents) * feeRate).rounded(.down))
        return max(1, raw)
    }

    /// What the hunter receives: total minus the platform fee.
    public static func hunterPayoutCents(totalCents: Int) -> Int {
        guard totalCents > 0 else { return 0 }
        return totalCents - appFeeCents(totalCents: totalCents)
    }

    /// Adjust an AI-produced step list so that step amounts sum exactly to
    /// `targetCents`. Any rounding difference is placed on the last step.
    /// The step list must be non-empty; returns as-is if empty.
    public static func reconcile(steps: [BountyStep], to targetCents: Int) -> [BountyStep] {
        guard !steps.isEmpty else { return steps }
        var result = steps
        let currentSum = result.reduce(0) { $0 + $1.amountCents }
        let diff = targetCents - currentSum
        // Put the entire rounding delta on the last step.
        result[result.count - 1].amountCents += diff
        // Guard: last step must not go negative (degenerate AI output).
        if result[result.count - 1].amountCents < 0 {
            result[result.count - 1].amountCents = 0
        }
        return result
    }

    /// Formatted dollar string for display, e.g. 1099 → "$10.99".
    public static func formatted(cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}
