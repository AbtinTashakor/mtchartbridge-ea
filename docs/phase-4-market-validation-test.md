# Phase 4 Market Validation Test

Phase 4 adds real MT5 market and symbol validation for `trade.open` commands after Phase 3 protocol validation succeeds.

No trade is executed in Phase 4. The EA does not import `CTrade`, does not call `OrderSend`, does not calculate risk-based volume, and does not calculate final trade volume yet.

## New Inputs

- `RejectIfSpreadAbovePoints`: default `0`. When greater than `0`, the EA rejects commands whose current `SYMBOL_SPREAD` is greater than this value.
- `AllowedSymbols`: default empty. When empty, all symbols are allowed. When set, it is a comma-separated allowlist matched case-insensitively after trimming spaces, for example `EURUSD,GBPUSD,XAUUSD`.

## Market Checks

After command protocol validation passes, the EA checks:

- `AllowedSymbols` allowlist.
- Symbol availability and selection with `SymbolSelect(symbol, true)` when needed.
- `SYMBOL_BID` and `SYMBOL_ASK`; both must be positive.
- Reference entry price: Ask for buy commands, Bid for sell commands.
- `SYMBOL_TRADE_MODE`; disabled symbols are rejected.
- Terminal, account, and EA automated-trading permission with `TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)`, `AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)`, and `MQLInfoInteger(MQL_TRADE_ALLOWED)`.
- Current spread in points, optionally rejected by `RejectIfSpreadAbovePoints`.
- Stop loss side: buy SL must be below Ask, sell SL must be above Bid.
- Optional take profit side when present and non-zero: buy TP must be above Ask, sell TP must be below Bid.
- Broker stop level using `SYMBOL_TRADE_STOPS_LEVEL` and `SYMBOL_POINT` for SL and active TP distance from the reference price.

Margin validation, risk amount calculation, final volume calculation, and order execution are intentionally out of scope.

## Error Codes

Phase 4 keeps the Phase 3 protocol error codes and adds:

- `SYMBOL_NOT_ALLOWED`
- `SYMBOL_SELECT_FAILED`
- `SYMBOL_PRICE_UNAVAILABLE`
- `SYMBOL_TRADE_DISABLED`
- `TERMINAL_TRADE_DISABLED`
- `ACCOUNT_TRADE_DISABLED`
- `SPREAD_TOO_HIGH`
- `INVALID_TAKE_PROFIT`
- `STOP_LOSS_TOO_CLOSE`
- `TAKE_PROFIT_TOO_CLOSE`
- `MARKET_VALIDATION_PASSED`

Accepted commands return:

```json
{
  "status": "accepted",
  "code": "MARKET_VALIDATION_PASSED",
  "message": "Command passed protocol and market validation. No trade was executed in Phase 4.",
  "ea_phase": "phase-4-market-validation"
}
```

Market validation responses include available market fields such as `bid`, `ask`, `entry_price_reference`, `spread_points`, `stop_level_points`, `point`, `digits`, `stop_loss`, `take_profit`, `allowed_symbols`, and `reject_if_spread_above_points`.

Accepted responses must archive the command payload and ready marker to `processed/`. Rejected market-validation responses must archive the command payload and ready marker to `failed/`.

## Manual Test Setup

1. Open `mt5/Experts/MTChartBridge/MTChartBridgeEA.mq5` in MetaEditor.
2. Compile and confirm 0 errors.
3. Attach the EA to a chart in MT5.
4. Confirm `Terminal/Common/Files/MTChartBridge/status.json` is updating.
5. For each test, write a command payload to `Terminal/Common/Files/MTChartBridge/inbox/<id>.command.json.tmp`.
6. Create the ready marker `Terminal/Common/Files/MTChartBridge/inbox/<id>.command.ready`.
7. Read `Terminal/Common/Files/MTChartBridge/outbox/<id>.response.json.tmp`.
8. Confirm the command files move to `processed/` when accepted and `failed/` when rejected.

Use fresh command ids for each test because duplicate ids are rejected within the EA session.

## Manual Test Cases

A. Valid buy command:

- `side`: `buy`
- `stop_loss`: below current Ask
- `take_profit`: above current Ask
- Expected `status`: `accepted`
- Expected `code`: `MARKET_VALIDATION_PASSED`
- Expected archive folder: `processed/`

B. Valid sell command:

- `side`: `sell`
- `stop_loss`: above current Bid
- `take_profit`: below current Bid
- Expected `status`: `accepted`
- Expected `code`: `MARKET_VALIDATION_PASSED`
- Expected archive folder: `processed/`

C. Invalid buy SL:

- Send a buy command with SL above Ask.
- Expected `code`: `INVALID_STOP_LOSS`
- Expected archive folder: `failed/`

D. Invalid sell SL:

- Send a sell command with SL below Bid.
- Expected `code`: `INVALID_STOP_LOSS`
- Expected archive folder: `failed/`

E. Invalid buy TP:

- Send a buy command with TP below Ask.
- Expected `code`: `INVALID_TAKE_PROFIT`
- Expected archive folder: `failed/`

F. Invalid sell TP:

- Send a sell command with TP above Bid.
- Expected `code`: `INVALID_TAKE_PROFIT`
- Expected archive folder: `failed/`

G. Symbol allowlist rejection:

- Set `AllowedSymbols = "GBPUSD"`.
- Send an `EURUSD` command.
- Expected `code`: `SYMBOL_NOT_ALLOWED`

H. Spread rejection:

- Set `RejectIfSpreadAbovePoints` to a very low value, such as `1`.
- Send a command on a symbol with spread above 1 point.
- Expected `code`: `SPREAD_TOO_HIGH`

I. Bad symbol:

- Set `symbol` to `NOT_A_REAL_SYMBOL`.
- Expected `code`: `SYMBOL_SELECT_FAILED` or `SYMBOL_PRICE_UNAVAILABLE`

## Safety Checks

- Confirm no position opens in MT5.
- Confirm the Experts log says no trade was executed.
- Confirm the source contains no `CTrade` import and no `OrderSend` call.
- Confirm generated `.ex5` files and runtime files remain untracked.
