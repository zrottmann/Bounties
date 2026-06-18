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
    }
}

private struct BountyRow: View {
    let bounty: Bounty

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bounty.description).lineLimit(2)
            HStack {
                Text(FeeMath.formatted(cents: bounty.totalCents))
                    .font(.headline)
                    .foregroundColor(.accentColor)
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
        }
        .padding(.vertical, 4)
    }
}
#endif
