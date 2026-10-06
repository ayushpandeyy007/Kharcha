import SwiftUI

/// Total across all wallets, with a jump to the Wallets screen.
struct BalanceTile: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui

    var body: some View {
        StatTile(title: "Total balance", value: Money.string(store.totalBalance)) {
            Button(store.wallets.count == 1 ? "1 wallet ›" : "\(store.wallets.count) wallets ›") { ui.section = .wallets }
                .buttonStyle(.link)
                .font(.caption)
                .help("See and update each wallet")
        }
    }
}
