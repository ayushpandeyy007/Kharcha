import SwiftUI

enum Section: String, CaseIterable, Identifiable {
    case overview, transactions, wallets, loans, analytics

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .transactions: "list.bullet.rectangle"
        case .wallets: "wallet.pass"
        case .loans: "person.2"
        case .analytics: "chart.xyaxis.line"
        }
    }
}

struct EditorTarget: Identifiable {
    let id = UUID()
    var transaction: Transaction?
    var kind: Kind = .expense
}

enum WalletSheet: Identifiable {
    case new
    case edit(UUID)
    case transfer

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let id): id.uuidString
        case .transfer: "transfer"
        }
    }
}

enum LoanSheet: Identifiable {
    case new(Loan.Direction)
    case detail(UUID)

    var id: String {
        switch self {
        case .new(let direction): "new-\(direction.rawValue)"
        case .detail(let id): id.uuidString
        }
    }
}

@MainActor @Observable
final class UIState {
    var section = Section(rawValue: UserDefaults.standard.string(forKey: "section") ?? "") ?? .overview {
        didSet { UserDefaults.standard.set(section.rawValue, forKey: "section") }
    }
    var editor: EditorTarget?
    var loanSheet: LoanSheet?
    var walletSheet: WalletSheet?
}
