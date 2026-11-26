# MT5 Signal Dashboard — Direction & Strength

A MetaTrader 5 Expert Advisor that shows a live **buy/sell signal dashboard** across the Deriv Volatility indices and gold/bitcoin, with **direction** (BUY / WAIT / SELL), **trend strength** (0–100% gauge bar + ADX), and configurable **alerts**.

Covered symbols (defaults):

| Alias   | Broker symbol                |
|---------|------------------------------|
| V10     | Volatility 10 Index          |
| V25     | Volatility 25 Index          |
| V50     | Volatility 50 Index          |
| V75     | Volatility 75 Index          |
| V10s    | Volatility 10 (1s) Index     |
| V75s    | Volatility 75 (1s) Index     |
| V150s   | Volatility 150 (1s) Index    |
| V250s   | Volatility 250 (1s) Index    |
| XAUUSD  | XAUUSD                       |
| BTCUSD  | BTCUSD                       |

The full symbol list is an input — edit `InpSymbolsCSV` to add/remove anything (aliases or exact broker names; unknown names are matched case-insensitively and by prefix).

## Installation

1. Copy `Volatility_Signal_Dashboard.mq5` into your terminal's data folder: `MQL5/Experts/` (MetaEditor: **File → Open Data Folder**).
2. Open it in MetaEditor and press **F7** (Compile).
3. In MT5, drag the EA onto **any one chart** (e.g. an empty EURUSD chart — it monitors all listed symbols from a single chart and does not trade).
4. Make sure the symbols appear in **Market Watch** (the EA auto-selects and searches for them).
5. Enable **Tools → Options → Expert Advisors → Allow Expert Advisor settings / automated trading** as required for alerts to fire.

## Signal logic (5-vote confluence)

Each symbol is scored on its signal timeframe (default M1, evaluated on the last **closed** bar to avoid repainting):

| # | Vote  | Bullish when | Bearish when |
|---|-------|--------------|--------------|
| 1 | EMA trend | Fast EMA (8) above Slow EMA (21) | below |
| 2 | Price vs fast EMA | Close above EMA(8) | below |
| 3 | RSI(14) | RSI ≥ 55 | RSI ≤ 45 |
| 4 | MACD(12,26,9) | Main above signal | below |
| 5 | ADX/DMI(14) | +DI above −DI | below |

- **BUY** when `bull votes − bear votes ≥ signal threshold` (default 3 of 5) **and ADX ≥ 20** (trend filter, adjustable).
- **SELL** on the mirror condition.
- **WAIT** otherwise.
- **Strength** = share of bullish (for BUY) or bearish (for SELL) votes out of 5, rendered as a 10-cell gauge bar.

## Alerts

Fires when a symbol flips from WAIT (or the opposite side) into a new BUY/SELL signal, with a per-symbol cooldown (default 30 min):

- Chart popup (`Alert`) — on by default
- **Push notification** — on by default; requires your MetaQuotes ID in **Tools → Options → Notifications**
- Email — optional; requires terminal email settings
- Sound — `alert.wav` by default

## Dashboard panel

- One row per symbol: name, signal, strength gauge, ADX, live price.
- Header summary: `BUY n | SELL n | WAIT n | updated hh:mm:ss`.
- Colors: lime = BUY, red = SELL, silver = WAIT.
- **Click the panel title** to minimize/expand.

## Inputs at a glance

| Group | Key inputs |
|-------|-----------|
| Symbols | `InpSymbolsCSV`, `InpTF` (signal timeframe, default M1) |
| Signals | EMA 8/21, RSI 14 with 55/45 levels, MACD 12/26/9, ADX 14, `InpMinADX = 20`, `InpSignalThreshold = 3`, `InpUseClosedBar = true` |
| Alerts | popup / push / email / sound toggles, cooldown minutes |
| Panel | corner, offsets, font size, colors, refresh seconds |

## Notes & disclaimer

- This tool **does not place trades**; it is monitoring/alerting only.
- Broker symbol names differ; on Deriv MT5 the defaults above match exactly. On other brokers the resolver searches for partial matches.
- No indicator guarantees profits — validate signals on a demo account first. Use at your own risk.
