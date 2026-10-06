<p align="center">
  <img src="docs/icon.png" width="128" alt="Kharcha icon">
</p>

<h1 align="center">Kharcha</h1>

<p align="center">
  A simple, native budget tracker for macOS, with analytics, wallets and loans.<br>
  Pure Swift + SwiftUI · no dependencies · no account · your data stays on your Mac
</p>

---

## Features

- **Track spending and income** in a few keystrokes: amount, category, wallet, optional note. The amount field adds up quick sums like `120+80`, and notes you've used before pick their category automatically.
- **Menu bar quick-add**: log an expense without opening the window, and see your balance, this month's spending and today's at a glance.
- **Wallets**: Bank account, Cash in hand, eSewa, Khalti, or any you add. Each balance updates as you add entries, and **Move Money** handles ATM withdrawals and top-ups without counting them as spending.
- **Loans**: money you lent or borrowed, with partial repayments, due dates and overdue warnings.
- **Analytics** for this month, last month, 3 months or this year:
  - Spending by category (ring + ranked bars)
  - Daily spending heatmap
  - 12-month income vs. spending trend
  - Insights, including a month-end forecast that ignores one-off bills like rent
- **Overview**: total balance, this month at a glance, spending pace vs. last month, top categories, recent entries.
- **Export**: transactions (including transfers) and loans as CSV for Excel/Numbers/Sheets, or a full JSON backup.
- Nepali Rupee formatting with lakh grouping (Rs 12,34,567). The currency symbol can be changed in Settings.
- Light and dark mode, keyboard shortcuts throughout, undo for deletes.

## Install

### Download

1. Download `Kharcha-x.y.zip` from the [latest release](../../releases/latest), unzip it, and move **Kharcha.app** to **Applications**.
2. The app isn't notarized by Apple, so macOS blocks the first launch. To allow it, either:
   - Open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**, or
   - Run this in Terminal:
     ```bash
     xattr -dr com.apple.quarantine /Applications/Kharcha.app
     ```

### Build from source

Requires macOS 14+ and Xcode or its command-line tools (Swift 5.9+).

```bash
git clone https://github.com/ayushpandeyy007/Kharcha.git
cd Kharcha
./build.sh install    # builds, copies to /Applications, launches
```

Other options: `./build.sh` only builds into `build/`, and `./build.sh release` also creates a zip for distribution.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘N / ⇧⌘N | New expense / new income |
| ⌘L | New loan |
| ⌘T | Move money between wallets |
| ⌘1 – ⌘5 | Overview, Transactions, Wallets, Loans, Analytics |
| ⇧⌘E | Export transactions as CSV |
| ⌫ / ⌘Z | Delete selected / undo |

## Your data

Everything is stored locally in one JSON file at `~/Library/Application Support/Kharcha/data.json`. A backup copy (`data.backup.json`) is refreshed on every launch. Nothing is sent anywhere.

Settings → General has **Show in Finder** and the export buttons.

## Project layout

| File | Purpose |
| --- | --- |
| `Sources/Models.swift` | Transactions, categories, loans, wallets, transfers, file format |
| `Sources/Store.swift` | Loading, saving, migration, wallet balances |
| `Sources/Analytics.swift` | Periods, totals, forecast and insights |
| `Sources/Charts.swift` | Pace, trend, category ring and heatmap charts |
| `Sources/*View.swift` | Overview, Transactions, Wallets, Loans, Analytics, Settings, menu bar |
| `Sources/EntryForm.swift` | Add/edit form shared by the window and the menu bar |
| `Sources/Export.swift` | CSV and backup export |
| `scripts/make_icon.swift` | Renders the app icon |
| `scripts/demo-data/` | Generates sample data for trying out the charts (`KHARCHA_DATA_DIR=<dir>` points the app at it) |
| `build.sh` | Compiles a universal, ad-hoc signed `.app` bundle |

## License

[MIT](LICENSE)
