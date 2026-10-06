import AppKit
import UniformTypeIdentifiers

/// Spreadsheet-friendly CSV files and a full JSON backup, saved wherever the user picks.
@MainActor
enum Exporter {
    static func exportTransactions(_ store: Store) {
        save(transactionsCSV(store), name: "Kharcha Transactions \(day(.now)).csv", type: .commaSeparatedText)
    }

    static func exportLoans(_ store: Store) {
        save(loansCSV(store), name: "Kharcha Loans \(day(.now)).csv", type: .commaSeparatedText)
    }

    static func exportBackup(_ store: Store) {
        do {
            save(try store.backupData(), name: "Kharcha Backup \(day(.now)).json", type: .json)
        } catch {
            fail(error)
        }
    }

    /// Income, expenses and transfers between wallets, oldest first (the way spreadsheets read).
    static func transactionsCSV(_ store: Store) -> Data {
        func name(_ id: UUID?) -> String { store.wallet(id)?.name ?? "" }
        var entries: [(date: Date, row: [String])] = store.transactions.map { t in
            (t.date, [day(t.date), t.kind.title, store.category(t.categoryID).name, t.note, number(t.amount), name(t.walletID)])
        }
        entries += store.transfers.map { x in
            (x.date, [day(x.date), "Transfer", "", x.note, number(x.amount), "\(name(x.fromWalletID)) → \(name(x.toWalletID))"])
        }
        let rows = [["Date", "Type", "Category", "Note", "Amount", "Wallet"]] + entries.sorted { $0.date < $1.date }.map(\.row)
        return csv(rows)
    }

    static func loansCSV(_ store: Store) -> Data {
        var rows = [["Person", "Direction", "Date", "Due Date", "Amount", "Repaid", "Remaining", "Status", "Note", "Wallet", "Repayments"]]
        for loan in store.loans.reversed() {
            rows.append([
                loan.person,
                loan.direction == .lent ? "Lent" : "Borrowed",
                day(loan.date),
                loan.dueDate.map(day) ?? "",
                number(loan.amount),
                number(loan.repaid),
                number(loan.remaining),
                loan.isSettled ? "Settled" : loan.isOverdue() ? "Overdue" : "Active",
                loan.note,
                store.wallet(loan.walletID)?.name ?? "",
                loan.repayments.map { "\(day($0.date)): \(number($0.amount))" }.joined(separator: "; "),
            ])
        }
        return csv(rows)
    }

    // MARK: Helpers

    private static func csv(_ rows: [[String]]) -> Data {
        let text = rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        // The byte-order mark makes Excel read Nepali (Devanagari) text correctly.
        return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Plain number, no symbol or grouping, so spreadsheets treat it as a number.
    private static func number(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    private static func save(_ data: Data, name: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            fail(error)
        }
    }

    private static func fail(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Couldn't export"
        alert.runModal()
    }
}
