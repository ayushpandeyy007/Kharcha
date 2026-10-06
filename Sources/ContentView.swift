import SwiftUI

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @AppStorage(Money.symbolKey) private var symbol = "Rs"

    var body: some View {
        @Bindable var ui = ui
        NavigationSplitView {
            List(selection: Binding(get: { ui.section }, set: { if let s = $0 { ui.section = s } })) {
                ForEach(Section.allCases) { section in
                    Label(section.title, systemImage: section.icon).tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) { SidebarSummary().padding(12) }
        } detail: {
            Group {
                switch ui.section {
                case .overview: OverviewView()
                case .transactions: TransactionsView()
                case .wallets: WalletsView()
                case .loans: LoansView()
                case .analytics: AnalyticsView()
                }
            }
            .id(symbol)   // re-render amounts when the currency symbol changes
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.page)
            .navigationTitle(ui.section.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if ui.section == .wallets {
                        Button { ui.walletSheet = .new } label: { Label("Add Wallet", systemImage: "plus") }
                            .help("Add a wallet")
                    } else if ui.section == .loans {
                        Button { ui.loanSheet = .new(.lent) } label: { Label("Add Loan", systemImage: "plus") }
                            .help("Add a loan (⌘L)")
                    } else {
                        Button { ui.editor = EditorTarget() } label: { Label("Add Transaction", systemImage: "plus") }
                            .help("Add a transaction (⌘N)")
                    }
                }
            }
        }
        .sheet(item: $ui.editor) { target in
            EntryForm(original: target.transaction, kind: target.kind) { _ in ui.editor = nil }
                .padding(20)
                .frame(width: 480)
        }
        .sheet(item: $ui.loanSheet) { sheet in
            Group {
                switch sheet {
                case .new(let direction): LoanForm(direction: direction) { _ in ui.loanSheet = nil }
                case .detail(let id): LoanDetail(loanID: id) { ui.loanSheet = nil }
                }
            }
            .padding(20)
            .frame(width: 500)
        }
        .sheet(item: $ui.walletSheet) { sheet in
            Group {
                switch sheet {
                case .new: WalletForm { ui.walletSheet = nil }
                case .edit(let id): WalletForm(original: store.wallet(id)) { ui.walletSheet = nil }
                case .transfer: TransferForm { ui.walletSheet = nil }
                }
            }
            .padding(20)
            .frame(width: 500)
        }
        .alert("Data file problem", isPresented: .constant(store.loadProblem != nil && !problemAcknowledged)) {
            Button("OK") { problemAcknowledged = true }
        } message: {
            Text(store.loadProblem ?? "")
        }
    }

    @State private var problemAcknowledged = false
}

private struct SidebarSummary: View {
    @Environment(Store.self) private var store

    var body: some View {
        let month = Calendar.current.dateInterval(of: .month, for: .now)!
        let spent = store.transactions.filter { $0.kind == .expense && month.holds($0.date) }.reduce(0) { $0 + $1.value }
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total balance").font(.caption).foregroundStyle(.secondary)
                Text(Money.string(store.totalBalance)).font(.callout.weight(.semibold)).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Spent in \(Date.now.formatted(.dateTime.month(.wide)))").font(.caption).foregroundStyle(.secondary)
                Text(Money.string(spent)).font(.callout.weight(.semibold)).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateView: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        ContentUnavailableView {
            Label("Nothing tracked yet", systemImage: "banknote")
        } description: {
            Text("Add your first expense or income. Charts and insights fill in as you go.\nTip: you can also add from the menu bar.")
        } actions: {
            Button("Add Transaction") { ui.editor = EditorTarget() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}
