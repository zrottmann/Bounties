#if os(iOS)
import SwiftUI
import BountiesKit

struct HunterFeedView: View {
    @State var vm: HunterFeedViewModel
    let marketplace: any MarketplaceService
    let location: LocationService

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading bounties…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.openBounties.isEmpty {
                    ContentUnavailableView(
                        "No Open Bounties",
                        systemImage: "checkmark.seal",
                        description: Text("Check back soon — new jobs are posted here.")
                    )
                } else {
                    List(vm.openBounties) { bounty in
                        NavigationLink(destination: BountyDetailView(
                            vm: BountyDetailViewModel(bounty: bounty,
                                                      marketplace: marketplace,
                                                      role: .hunter),
                            marketplace: marketplace
                        )) {
                            BountyRow(bounty: bounty)
                        }
                    }
                }
            }
            .navigationTitle("Open Bounties")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { Task { await vm.load(coordinate: location.coordinate) } }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if location.isAvailable {
                        Label("Location on", systemImage: "location.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    } else {
                        Button {
                            location.requestLocation()
                        } label: {
                            Label("Enable location", systemImage: "location.slash")
                        }
                        .font(.caption)
                    }
                }
            }
            .task {
                location.requestLocation()
                await vm.load(coordinate: location.coordinate)
            }
        }
        .busyBannerForError($vm.busyError) {
            Task { await vm.load(coordinate: location.coordinate) }
        }
    }
}

private struct BountyRow: View {
    let bounty: Bounty
    // Re-render every second so the live-rising offer ticks upward in real time.
    @State private var now: Date = .now
    @State private var ticker: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bounty.description).lineLimit(2)
            HStack(spacing: 6) {
                // displayOfferCents is computed from elapsed time + now, so
                // ticking the local `now` state drives live re-renders.
                let offer = SurgePricing.currentOfferCents(
                    basePriceCents: bounty.basePriceCents,
                    maxPriceCents: bounty.maxPriceCents,
                    surgeHours: bounty.surgeHours,
                    postedAt: bounty.postedAt,
                    now: now
                )
                Text(FeeMath.formatted(cents: bounty.lockedPriceCents ?? offer))
                    .font(.headline)
                    .foregroundColor(.accentColor)
                if bounty.lockedPriceCents == nil,
                   SurgePricing.isSurging(surgeHours: bounty.surgeHours,
                                          postedAt: bounty.postedAt, now: now) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                Spacer()
                if let km = bounty.distanceKm {
                    Text(String(format: "%.1f km", km))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("\(bounty.steps.count) steps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if bounty.lockedPriceCents == nil,
               SurgePricing.isSurging(surgeHours: bounty.surgeHours,
                                       postedAt: bounty.postedAt, now: now) {
                Text(SurgePricing.countdownLabel(surgeHours: bounty.surgeHours,
                                                 postedAt: bounty.postedAt, now: now))
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                now = .now
            }
        }
        .onDisappear { ticker?.invalidate() }
    }
}
#endif
