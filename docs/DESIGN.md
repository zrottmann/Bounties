# Bounties — MVP Design

Uber for household chores. Holders post jobs (rake leaves, pull weeds, move furniture, run errands), fund them with Apple Pay, and hunters complete them step-by-step with photo evidence. Money releases step-by-step against evidence.

## Architecture

```
C:\Bounties
├── Package.swift
├── Info.plist
├── PrivacyInfo.xcprivacy
├── xtool.yml
├── Sources/
│   ├── BountiesKit/          # Pure logic — no UIKit, no PassKit
│   │   ├── Models.swift      # Bounty, BountyStep, BountyStatus, BountyLedger
│   │   ├── FeeMath.swift     # 1% fee, 99% payout, step reconciliation
│   │   ├── BountyAIService.swift  # Protocol + StubBountyAIService
│   │   └── MarketplaceService.swift  # Protocol + StubMarketplaceService
│   └── Bounties/             # iOS app target (#if os(iOS))
│       ├── BountiesApp.swift
│       ├── AppRole.swift
│       ├── FoundationModelsBountyAI.swift  # on-device AI (iOS 26+)
│       ├── ViewModels/
│       │   ├── PostBountyViewModel.swift
│       │   ├── HunterFeedViewModel.swift
│       │   └── BountyDetailViewModel.swift
│       └── Views/
│           ├── ContentView.swift
│           ├── PostBountyView.swift
│           ├── HunterFeedView.swift
│           ├── BountyDetailView.swift
│           └── SettingsView.swift
└── Tests/
    └── BountiesKitTests/
        └── BountiesKitTests.swift
```

## Core MVP Flow

1. **Holder posts a bounty:** photo + description + price. On-device FoundationModels (iOS 26) breaks the job into steps with individual sub-prices that sum to the total. Holder reviews and agrees.

2. **Payment:** Apple Pay via `PKPaymentAuthorizationController`. 1% platform fee retained; 99% goes to the hunter. Fee breakdown shown clearly. Real hunter bank payouts are out of scope for v1 — tracked in `BountyLedger`.

3. **Hunter feed:** list of open funded bounties. Hunter accepts one, completes steps, uploads a photo as evidence per step.

4. **Step-by-step approval:** holder approves each step's evidence, releasing that portion. Per-step granularity is the whole point — money releases incrementally against verified evidence.

## Fee Math

- App fee: `floor(total * 0.01)`, minimum 1 cent when total > 0.
- Hunter payout: `total - appFee` (so fee + payout = total always).
- Step amounts must re-sum to total after AI output. `FeeMath.reconcile(steps:to:)` puts any rounding remainder on the last step.

## AI Integration

`FoundationModelsBountyAI` (iOS 26+) uses `@Generable AIBreakdown` to get structured output — summary, suggested price, and steps. Three-tier resilience mirroring AiHandy:
1. Full model with rich prompt.
2. Compact fallback prompt.
3. `StubBountyAIService` — always produces a result.

## v0.1.0 TestFlight Stubs

- **Apple Pay:** `PKPaymentAuthorizationController` is stubbed — the funding screen shows "Fund Bounty (Coming Soon)" and simulates immediate success. This avoids needing a merchant ID entitlement (`merchant.com.zrottmann.bounties`) in the provisioning profile. Re-enable by: registering the merchant ID in the Apple Developer portal, adding `com.apple.developer.in-app-payments` entitlement with that merchant ID to the App ID, regenerating the profile, and restoring the real `ApplePayButton` implementation with `import PassKit`.
- **FoundationModels AI:** `makeBountyAIService()` returns `StubBountyAIService` which gives a deterministic 3-step breakdown. The real on-device AI path using `LanguageModelSession` is the v0.2.0 increment.

## Next Increments (prioritised)

1. **GitHub repo + CI:** `git remote add origin`, create repo, wire Codemagic xtool pipeline (copy from Stash/Cardly). Upload IPA to TestFlight.
2. **Real Appwrite marketplace backend:** replace `StubMarketplaceService` with live endpoints — post bounty, list open, accept, submit evidence, approve step. Store bounty photo + evidence photos in Appwrite Storage.
3. **Hunter bank payouts:** integrate Stripe Connect. When a step is approved, queue an ACH transfer of `hunterPayoutCents(stepAmount)` to the hunter's connected bank account.
4. **Location / geofencing:** use CoreLocation to surface only bounties within a configurable radius. Sort feed by distance.
5. **In-app messaging:** per-bounty thread so holder and hunter can clarify details (Appwrite Realtime or a simple polling endpoint).
6. **Reviewer / dispute panel:** a third-party reviewer role that can inspect evidence and override approval/rejection. Triggered by either party.
7. **Push notifications:** Appwrite push via APNs — hunter notified on new nearby bounty; holder notified when evidence submitted; both notified on step approval.
8. **App Store submission:** create ASC record (UI only — API can't), set app privacy nutrition label via fastlane, submit for review.
