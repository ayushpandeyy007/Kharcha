import SwiftUI

struct MenuBarView: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.openWindow) private var openWindow
    @State private var added: Transaction?
    @State private var formID = UUID()

    var body: some View {
        let cal = Calendar.current
        let month = cal.dateInterval(of: .month, for: .now)!
        let expenses = store.transactions.filter { $0.kind == .expense && month.holds($0.date) }
        let spentMonth = expenses.reduce(0) { $0 + $1.value }
        let spentToday = expenses.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.value }

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                summary("Balance", Money.string(store.totalBalance))
                Spacer()
                summary("Spent in \(Date.now.formatted(.dateTime.month(.abbreviated)))", Money.string(spentMonth),
                        alignment: .center)
                Spacer()
                summary("Today", Money.string(spentToday), alignment: .trailing)
            }

            let owedToYou = store.outstanding(.lent)
            let youOwe = store.outstanding(.borrowed)
            if owedToYou > 0 || youOwe > 0 {
                Button { open(.loans) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                        if owedToYou > 0 { Text("Owed to you \(Money.string(owedToYou))") }
                        if owedToYou > 0 && youOwe > 0 { Text("·") }
                        if youOwe > 0 { Text("You owe \(Money.string(youOwe))") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Loans")
            }

            EntryForm(compact: true) { t in
                withAnimation { added = t }
            }
            .id(formID)

            if let added {
                Label("Added \(Money.string(added.amount)) · \(store.category(added.categoryID).name)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.good)
                    .transition(.opacity)
                    .task(id: added.id) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { self.added = nil }
                    }
            }

            if !store.transactions.isEmpty {
                Divider()
                VStack(spacing: 6) {
                    ForEach(store.transactions.prefix(3)) { t in
                        TransactionRow(transaction: t, category: store.category(t.categoryID), wallet: store.wallet(t.walletID), showsDate: true)
                            .font(.callout)
                    }
                }
            }

            Divider()
            HStack {
                Button("Open Kharcha") { open(.overview) }
                Button("Analytics") { open(.analytics) }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .help("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit Kharcha")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { formID = UUID() }   // fresh, focused form every time the panel opens
    }

    private func summary(_ title: String, _ value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }

    private func open(_ section: Section) {
        ui.section = section
        openWindow(id: "main")
        NSApp.activate()
    }
}
