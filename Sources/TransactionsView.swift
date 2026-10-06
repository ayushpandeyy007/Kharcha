import SwiftUI

struct TransactionsView: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.undoManager) private var undoManager

    @State private var month: Date? = Calendar.current.monthStart(.now)   // nil = all time
    @State private var kindFilter: Kind?
    @State private var categoryFilter: UUID?
    @State private var walletFilter: UUID?
    @State private var search = ""
    @State private var selection = Set<UUID>()

    private var filtered: [Transaction] {
        let cal = Calendar.current
        let interval = month.flatMap { cal.dateInterval(of: .month, for: $0) }
        let query = search.trimmingCharacters(in: .whitespaces)
        return store.transactions.filter { t in
            if let interval, !interval.holds(t.date) { return false }
            if let kindFilter, t.kind != kindFilter { return false }
            if let categoryFilter, t.categoryID != categoryFilter { return false }
            if let walletFilter, t.walletID != walletFilter { return false }
            if !query.isEmpty {
                return t.note.localizedCaseInsensitiveContains(query)
                    || store.category(t.categoryID).name.localizedCaseInsensitiveContains(query)
            }
            return true
        }
    }

    var body: some View {
        let items = filtered
        let days = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
        VStack(spacing: 0) {
            filterBar(items)
            Divider()
            if store.transactions.isEmpty {
                EmptyStateView()
            } else if items.isEmpty {
                ContentUnavailableView("No matching transactions", systemImage: "magnifyingglass",
                                       description: Text("Try another month or clear the filters."))
            } else {
                List(selection: $selection) {
                    ForEach(days, id: \.key) { day, entries in
                        SwiftUI.Section {
                            ForEach(entries) { t in
                                TransactionRow(transaction: t, category: store.category(t.categoryID), wallet: store.wallet(t.walletID))
                                    .tag(t.id)
                            }
                        } header: {
                            HStack {
                                Text(day.dayTitle())
                                Spacer()
                                let spent = entries.filter { $0.kind == .expense }.reduce(0) { $0 + $1.value }
                                if spent > 0 { Text(Money.string(spent)).monospacedDigit() }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if ids.count == 1, let t = store.transactions.first(where: { ids.contains($0.id) }) {
                        Button("Edit…") { ui.editor = EditorTarget(transaction: t) }
                        Button("Add Again Today") { duplicate(t) }
                        Divider()
                    }
                    Button(ids.count > 1 ? "Delete \(ids.count) Transactions" : "Delete", role: .destructive) { delete(ids) }
                } primaryAction: { ids in
                    if ids.count == 1, let t = store.transactions.first(where: { ids.contains($0.id) }) {
                        ui.editor = EditorTarget(transaction: t)
                    }
                }
                .onDeleteCommand { delete(selection) }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search notes or categories")
    }

    private func filterBar(_ items: [Transaction]) -> some View {
        let cal = Calendar.current
        let spent = items.filter { $0.kind == .expense }.reduce(0) { $0 + $1.value }
        let earned = items.filter { $0.kind == .income }.reduce(0) { $0 + $1.value }
        return HStack(spacing: 12) {
            HStack(spacing: 2) {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(month == nil)
                Menu {
                    Button("This Month") { month = cal.monthStart(.now) }
                    Button("All Time") { month = nil }
                } label: {
                    Text(month?.formatted(.dateTime.month(.wide).year()) ?? "All Time")
                        .frame(minWidth: 110)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(month == nil || month! >= cal.monthStart(.now))
            }
            .buttonStyle(.borderless)

            Picker("Type", selection: $kindFilter) {
                Text("All").tag(Kind?.none)
                Text("Expenses").tag(Kind?.some(.expense))
                Text("Income").tag(Kind?.some(.income))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .onChange(of: kindFilter) { _, k in
                if let k, let c = categoryFilter, store.category(c).kind != k { categoryFilter = nil }
            }

            Picker("Category", selection: $categoryFilter) {
                Text("All Categories").tag(UUID?.none)
                ForEach(Kind.allCases) { kind in
                    if kindFilter == nil || kindFilter == kind {
                        Divider()
                        ForEach(store.categories(of: kind)) { c in
                            Label(c.name + (kind == .income ? " (income)" : ""), systemImage: c.icon).tag(UUID?.some(c.id))
                        }
                    }
                }
            }
            .labelsHidden()
            .fixedSize()

            Picker("Wallet", selection: $walletFilter) {
                Text("All Wallets").tag(UUID?.none)
                Divider()
                ForEach(store.wallets) { w in
                    Label(w.name, systemImage: w.kind.icon).tag(UUID?.some(w.id))
                }
            }
            .labelsHidden()
            .fixedSize()

            Spacer()

            Text("\(items.count) · Spent \(Money.string(spent))\(earned > 0 ? " · In \(Money.string(earned))" : "")")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func shiftMonth(_ delta: Int) {
        guard let m = month else { return }
        month = Calendar.current.date(byAdding: .month, value: delta, to: m)
    }

    private func duplicate(_ t: Transaction) {
        var copy = t
        copy.id = UUID()
        copy.date = .now
        store.add(copy)
    }

    private func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let removed = store.delete(ids)
        selection.subtract(ids)
        let store = store
        undoManager?.registerUndo(withTarget: store) { target in
            MainActor.assumeIsolated { target.restore(removed) }
        }
        undoManager?.setActionName(removed.count > 1 ? "Delete Transactions" : "Delete Transaction")
    }
}
