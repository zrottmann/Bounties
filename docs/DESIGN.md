# BountyHunter — Design

Uber for household chores. Holders post jobs (rake leaves, pull weeds, move furniture, run errands), fund them with Apple Pay, and hunters complete them step-by-step with photo evidence. Money releases step-by-step against verified evidence.

## Architecture

```
C:\Bounties
├── Package.swift
├── Info.plist
├── PrivacyInfo.xcprivacy
├── xtool.yml
├── Sources/
│   ├── BountiesKit/          # Pure logic — no UIKit, no PassKit
│   │   ├── Models.swift      # Bounty, BountyStep, BountyStatus, BountyLedger, BountyMessage, BountyDispute
│   │   ├── FeeMath.swift     # 1% fee, 99% payout, step reconciliation
│   │   ├── BountyAIService.swift  # Protocol + StubBountyAIService
│   │   └── MarketplaceService.swift  # Protocol + StubMarketplaceService (actor)
│   └── Bounties/             # iOS app target (#if os(iOS))
│       ├── BountiesApp.swift
│       ├── AppRole.swift     # Holder / Hunter / Reviewer
│       ├── ApplePayFunding.swift  # PKPaymentAuthorizationController; auto-falls back when unavailable
│       ├── FoundationModelsBountyAI.swift  # on-device AI (iOS 26+, 3-tier)
│       ├── BackendMarketplaceService.swift  # live Appwrite Executions API client
│       ├── LocationService.swift  # CLLocationManager @MainActor @Observable
│       ├── PushRegistration.swift  # UNUserNotificationCenter + APNs token → /register-push
│       ├── ViewModels/
│       │   ├── PostBountyViewModel.swift
│       │   ├── HunterFeedViewModel.swift
│       │   └── BountyDetailViewModel.swift
│       └── Views/
│           ├── ContentView.swift
│           ├── PostBountyView.swift
│           ├── HunterFeedView.swift
│           ├── BountyDetailView.swift
│           ├── MessageThreadView.swift
│           ├── DisputeView.swift
│           ├── ReviewerFeedView.swift
│           └── SettingsView.swift
└── Tests/
    └── BountiesKitTests/
        └── BountiesKitTests.swift   # 20+ tests, all green
```

**Backend:** `C:\bounties-api` — standalone Appwrite Function (`bounties-api`), deployed at `https://bounties-api.appwrite.network`. Contract: `C:\bounties-api\docs\ENDPOINTS.md`.

## What Is REAL (build 4)

| Feature | Status |
|---|---|
| On-device AI breakdown | REAL — `FoundationModelsBountyAI` (LanguageModelSession, no @Generable, 3-tier fallback) |
| Backend marketplace | REAL — `BackendMarketplaceService` → `bounties-api` (post, list, accept, evidence, approve, messages, dispute, push) |
| Apple Pay sheet | REAL — `PKPaymentAuthorizationController` with `merchant.com.zrottmann.bounties`. Falls back silently to simulated when Apple Pay unavailable (simulator, device without entitlement) |
| `/fund` backend call | REAL — after Apple Pay success, POST `/fund` sends the PKPaymentToken to the backend; backend records funding. Stripe charge happens when `STRIPE_SECRET_KEY` is set |
| CoreLocation distance feed | REAL — when-in-use auth, lat/lng passed to `/list-open`, nearest-first sort |
| Per-bounty messaging | REAL — `MessageThreadView` backed by `/messages` GET+POST |
| Dispute panel | REAL — holder/hunter open via `/dispute`, reviewer role resolves |
| Push registration | REAL — UNUserNotificationCenter + APNs device token sent to `/register-push` |
| Reviewer role | REAL — third tab with `ReviewerFeedView` + `DisputeView` |

## What Remains Owner-Gated (money still safe)

| Feature | Blocked on |
|---|---|
| Real Stripe charge | Owner must set `STRIPE_SECRET_KEY` as a function variable on `bounties-api` (then redeploy). Without it, `/fund` records funding in state only — no charge |
| Hunter bank payouts | Stripe Connect setup. Ledger rows are written with `payoutCents` pending; nothing moves until Stripe Connect ACH is wired |
| APNs push delivery | Owner must upload an APNs key in ASC (Push Notifications section for app 6781448557). Token registration already works; Apple just can't deliver notifications without the cert |

## Apple Pay Setup (done)

- Merchant ID `merchant.com.zrottmann.bounties` (ASC id `5T6W5PRK48`) created via ASC API 2026-06-18.
- Apple Pay capability enabled on bundle ID `com.zrottmann.bounties` (ASC id `4R8KHRFGLF`) via `POST /v1/bundleIdCapabilities` with `capabilityType: APPLE_PAY`.
- Codemagic ASC integration regenerates the provisioning profile automatically at build time, picking up the new capability.
- The iOS entitlement `com.apple.developer.in-app-payments` with merchant value `merchant.com.zrottmann.bounties` is injected by Codemagic signing.

## Core MVP Flow

1. **Holder posts a bounty:** photo + description + price. On-device FoundationModels (iOS 26+) breaks the job into steps with individual sub-prices that sum to the total. Holder reviews and agrees.

2. **Apple Pay funding:** `ApplePayFundButton` presents the real Apple Pay sheet on provisioned devices. On success, `PostBountyViewModel` calls `BackendMarketplaceService.fund()` which POSTs to `/fund` with the token and amount. Backend calls Stripe (when `STRIPE_SECRET_KEY` set) or records simulated funding.

3. **Hunter feed:** list of open funded bounties, sorted nearest-first when location is enabled. Hunter accepts one, completes steps, uploads photo evidence per step.

4. **Step-by-step approval:** holder approves each step's evidence, releasing that portion (ledger row written). When all steps approved, bounty becomes `completed`.

5. **Messaging & disputes:** holder and hunter can message per-bounty; either party can open a dispute on any step; reviewer role can resolve.

## Fee Math

- App fee: `floor(total * 0.01)`, minimum 1 cent when total > 0.
- Hunter payout: `total - appFee` (so fee + payout = total always).
- Step amounts must re-sum to total after AI output. `FeeMath.reconcile(steps:to:)` puts any rounding remainder on the last step.
- Platform fee is configurable via `BOUNTIES_PLATFORM_FEE_BPS` function variable (default 100 = 1%).

## AI Integration

`FoundationModelsBountyAI` uses `LanguageModelSession` with a structured JSON prompt (no `@Generable` macros — avoids macro compilation issues on CI). Three-tier resilience:
1. Full model with rich JSON instructions.
2. Simpler prompt.
3. `StubBountyAIService` — always produces a deterministic 3-step result.

Wrapped in `#if canImport(FoundationModels)` so the macOS CI host compiles cleanly (the framework is iOS 26+ only).
