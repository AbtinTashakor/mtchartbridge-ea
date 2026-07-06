# Phase 7 Live Execution Test

Phase 7 adds the first path that can open a real trade. It preserves the local-only architecture and still calculates final trade volume inside MT5.

Test Phase 7 on a demo account first. Do not run live-account testing until the demo checks are understood and intentionally accepted.

## What Changed

For `dry_run=true`, behavior remains no-trade:

- The EA validates the command, validates market state, calculates risk, and builds a request preview.
- If `EnableOrderCheck=true`, the EA runs `OrderCheck`.
- If `OrderCheck` passes, the accepted code is `ORDER_CHECK_PASSED_NO_TRADE`.
- If `EnableOrderCheck=false`, the accepted code is `EXECUTION_PREVIEW_READY_NO_TRADE`.
- `OrderSend` is never called and `order_send_attempted=false`.

For `dry_run=false`, the command is treated as a live execution request:

- `EnableLiveTrading` must be `true`.
- `AllowLiveOrderSend` must be `true`.
- `LiveTradingAcknowledgement` must exactly equal `I_UNDERSTAND_THIS_CAN_OPEN_REAL_TRADES`.
- `EnableOrderCheck` must be `true`.
- `MaxDeviationPoints` must be greater than or equal to `0`.
- Terminal, account, and MQL automated-trading permissions must allow trading.
- Protocol validation, market validation, MT5-side risk calculation, and request building must pass.
- `OrderCheck` must return `true` with a known success retcode before `OrderSend` is attempted.

`OrderCheck` is required before live `OrderSend` because it gives MT5/broker-side validation a chance to reject or price the exact request before the EA attempts live execution. Retcode `0` is treated as failed/ambiguous, not as a broker rejection, because it does not prove that MT5 produced a meaningful trade-server decision.

Duplicate protection in Phase 7 is session-level only. Restarting the EA clears the in-memory duplicate-command cache.

## Inputs

New Phase 7 inputs:

- `EnableLiveTrading`: default `false`.
- `AllowLiveOrderSend`: default `false`.
- `LiveTradingAcknowledgement`: default empty; must exactly equal `I_UNDERSTAND_THIS_CAN_OPEN_REAL_TRADES`.

Existing execution inputs:

- `EnableOrderCheck`: default `true`; required for live execution.
- `MaxDeviationPoints`: default `20`; negative values reject with `INVALID_DEVIATION_POINTS`.

## Response Fields

Phase 7 adds:

- `enable_live_trading`
- `allow_live_order_send`
- `live_trading_acknowledgement_valid`
- `order_send_attempted`
- `order_send_call_success`
- `order_send_retcode`
- `order_send_comment`
- `order_send_order`
- `order_send_deal`
- `order_send_volume`
- `order_send_price`
- `order_send_bid`
- `order_send_ask`
- `last_error`
- `last_error_description`

`order_send_attempted` must be `false` for dry runs, live-gate rejections, and OrderCheck failures/rejections.

## New Codes

- `LIVE_ORDER_SEND_ACCEPTED`
- `LIVE_TRADING_DISABLED`
- `LIVE_ORDER_SEND_DISABLED`
- `LIVE_ACKNOWLEDGEMENT_REQUIRED`
- `ORDER_CHECK_REQUIRED_FOR_LIVE`
- `ORDER_SEND_FAILED`
- `ORDER_SEND_REJECTED`

## Manual Test Setup

1. Open `mt5/Experts/MTChartBridge/MTChartBridgeEA.mq5` in MetaEditor.
2. Compile and confirm 0 errors.
3. Attach the EA to a demo-account chart first.
4. Confirm `Terminal/Common/Files/MTChartBridge/status.json` is updating and reports `ea_phase` as `phase-7-live-execution`.
5. For each test, write a command payload to `Terminal/Common/Files/MTChartBridge/inbox/<id>.command.json.tmp`.
6. Create the ready marker `Terminal/Common/Files/MTChartBridge/inbox/<id>.command.ready`.
7. Read `Terminal/Common/Files/MTChartBridge/outbox/<id>.response.json.tmp`.
8. Confirm accepted command files move to `processed/` and rejected command files move to `failed/`.

Use fresh command ids except for the duplicate test.

## Manual Test Cases

A. `dry_run=true` still does not trade:

- Set `EnableLiveTrading=true`.
- Set `AllowLiveOrderSend=true`.
- Set `LiveTradingAcknowledgement=I_UNDERSTAND_THIS_CAN_OPEN_REAL_TRADES`.
- Send a valid command with `dry_run=true`.
- Expected: no `OrderSend`, `order_send_attempted=false`, no trade opened.
- If `EnableOrderCheck=true` and OrderCheck passes: `accepted` / `ORDER_CHECK_PASSED_NO_TRADE`.

B. `dry_run=false` but `EnableLiveTrading=false`:

- Expected: `rejected` / `LIVE_TRADING_DISABLED`.
- Expected: `order_send_attempted=false`, no trade opened.

C. `dry_run=false` but `AllowLiveOrderSend=false`:

- Set `EnableLiveTrading=true`.
- Expected: `rejected` / `LIVE_ORDER_SEND_DISABLED`.
- Expected: `order_send_attempted=false`, no trade opened.

D. `dry_run=false` but acknowledgement missing or wrong:

- Set `EnableLiveTrading=true`.
- Set `AllowLiveOrderSend=true`.
- Leave `LiveTradingAcknowledgement` empty or set it incorrectly.
- Expected: `rejected` / `LIVE_ACKNOWLEDGEMENT_REQUIRED`.
- Expected: `order_send_attempted=false`, no trade opened.

E. `dry_run=false` but `EnableOrderCheck=false`:

- Set all live gates true.
- Set `EnableOrderCheck=false`.
- Expected: `rejected` / `ORDER_CHECK_REQUIRED_FOR_LIVE`.
- Expected: `order_send_attempted=false`, no trade opened.

F. Live execution on demo:

- Demo account only.
- Use `dry_run=false`.
- Set `EnableLiveTrading=true`.
- Set `AllowLiveOrderSend=true`.
- Set `LiveTradingAcknowledgement=I_UNDERSTAND_THIS_CAN_OPEN_REAL_TRADES`.
- Set `EnableOrderCheck=true`.
- Use a valid small-risk command.
- If OrderCheck passes and OrderSend succeeds, expected: `accepted` / `LIVE_ORDER_SEND_ACCEPTED`, `order_send_attempted=true`, response includes `order_send_retcode`, `order_send_comment`, `order_send_order`, and `order_send_deal`, and a small demo trade may open.
- If OrderCheck returns retcode `0`, expected: `rejected` / `ORDER_CHECK_FAILED`, `order_send_attempted=false`, no trade opened.
- If OrderCheck rejects, expected: `rejected` / `ORDER_CHECK_REJECTED`, `order_send_attempted=false`, no trade opened.
- If OrderSend rejects, expected: `rejected` / `ORDER_SEND_REJECTED` or `ORDER_SEND_FAILED`, `order_send_attempted=true`.

G. Ensure no duplicate OrderSend:

- Send the same command id again during the same EA session.
- Expected: duplicate handling with `DUPLICATE_COMMAND`.
- Expected: no second `OrderSend`.

## Static Safety Scan

Before commit, confirm:

- The only actual `OrderSend` call is in the Phase 7 live execution path after OrderCheck success.
- No `CTrade`.
- No `WebRequest`.
- No socket or `Socket`.
- No DLL imports.
- No new unsafe `#include`.
- No `#import`.
