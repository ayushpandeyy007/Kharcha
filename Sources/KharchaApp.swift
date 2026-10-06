import SwiftUI

@main
struct KharchaApp: App {
    @State private var store = Store()
    @State private var ui = UIState()
    @AppStorage("menuBarShowsTotal") private var menuBarShowsTotal = false

    var body: some Scene {
        Window("Kharcha", id: "main") {
            ContentView()
                .environment(store)
                .environment(ui)
                .frame(minWidth: 880, minHeight: 580)
        }
        .defaultSize(width: 1140, height: 780)
        .commands { AppCommands(ui: ui, store: store) }

        MenuBarExtra {
            MenuBarView()
                .environment(store)
                .environment(ui)
        } label: {
            MenuBarLabel(store: store, showsTotal: menuBarShowsTotal)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

private struct AppCommands: Commands {
    let ui: UIState
    let store: Store

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            OpenWindowButton(title: "New Expense", key: "n", modifiers: .command) { ui.editor = EditorTarget(kind: .expense) }
            OpenWindowButton(title: "New Income", key: "n", modifiers: [.command, .shift]) { ui.editor = EditorTarget(kind: .income) }
            OpenWindowButton(title: "New Loan", key: "l", modifiers: .command) {
                ui.section = .loans
                ui.loanSheet = .new(.lent)
            }
            OpenWindowButton(title: "Move Money…", key: "t", modifiers: .command) {
                ui.section = .wallets
                ui.walletSheet = .transfer
            }
        }
        CommandGroup(replacing: .importExport) {
            Menu("Export") {
                Button("Transactions as CSV…") { Exporter.exportTransactions(store) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Loans as CSV…") { Exporter.exportLoans(store) }
                Divider()
                Button("Full Backup…") { Exporter.exportBackup(store) }
            }
        }
        CommandMenu("Go") {
            ForEach(Array(Section.allCases.enumerated()), id: \.element) { i, section in
                OpenWindowButton(title: section.title, key: KeyEquivalent(Character("\(i + 1)")), modifiers: .command) {
                    ui.section = section
                }
            }
        }
    }
}

/// Brings the main window forward (reopening it if closed) before acting.
private struct OpenWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    let title: String
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let action: () -> Void

    var body: some View {
        Button(title) {
            openWindow(id: "main")
            NSApp.activate()
            action()
        }
        .keyboardShortcut(key, modifiers: modifiers)
    }
}

private struct MenuBarLabel: View {
    let store: Store
    let showsTotal: Bool

    var body: some View {
        if showsTotal {
            let month = Calendar.current.dateInterval(of: .month, for: .now)!
            let spent = store.transactions
                .filter { $0.kind == .expense && month.holds($0.date) }
                .reduce(0) { $0 + $1.value }
            Text("\(Image(systemName: "banknote")) \(Money.compact(spent))")
        } else {
            Image(systemName: "banknote")
        }
    }
}
