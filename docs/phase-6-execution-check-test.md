# Phase 6 Execution Check Test

Phase 6 adds a no-trade execution safety layer after Phase 5 risk calculation.

The EA still calculates final volume inside MT5. After that calculation succeeds, Phase 6 requires `dry_run=true`, builds a market-order `MqlTradeRequest`, and either runs `OrderCheck` or returns the request preview when `EnableOrderCheck=false`.

No trade is executed in Phase 6. The EA uses `OrderCheck`, but it does not call `OrderSend`, does not import `CTrade`, does not open positions, and does not place pending orders. Live execution comes in a later phase.

## Inputs

- `EnableOrderCheck`: default `true`. When enabled, the EA runs `OrderCheck` against the built request and returns the check result.
- `MaxDeviationPoints`: default `20`. Used as the request `deviation`; negative values reject with `INVALID_DEVIATION_POINTS`.

Existing inputs remain available:

- `PollingIntervalMs`
- `EnableDebugLogs`
- `ProductName`
- `MagicNumber`
- `EnforceCommandTtl`
- `MaxCommandTtlMs`
- `ProcessedCommandCacheSize`
- `RejectIfSpreadAbovePoints`
- `AllowedSymbols`
- `MaxRiskPercent`
- `MaxVolume`

## Request Preview

For a buy command, the EA builds a `TRADE_ACTION_DEAL` request with `ORDER_TYPE_BUY`, the calculated normalized volume, current Ask, command `stop_loss`, optional non-zero `take_profit`, `MaxDeviationPoints`, `MagicNumber`, `ORDER_TIME_GTC`, and a broker-compatible filling mode.

For a sell command, the EA builds the same market request shape with `ORDER_TYPE_SELL` and current Bid.

The request is only checked or previewed. It is not sent.

## Responses

Accepted OrderCheck responses use:

```json
{
  "status": "accepted",
  "code": "ORDER_CHECK_PASSED_NO_TRADE",
  "ea_phase": "phase-6-execution-check",
  "message": "Command passed validation, risk calculation, and MT5 OrderCheck. No trade was executed in Phase 6."
}
```

When `EnableOrderCheck=false`, accepted responses use `EXECUTION_PREVIEW_READY_NO_TRADE`.

Rejected responses use:

```json
{
  "status": "rejected",
  "ea_phase": "phase-6-execution-check"
}
```

Standard response fields remain present: `type`, `id`, `status`, `code`, `message`, `ea_phase`, `symbol`, `side`, `dry_run`, `source` when parsed, `trace_id`, `timestamp_local`, `received_at_local`, and `processed_at_local`.

Phase 4 market fields and Phase 5 risk fields continue to be included when available.

Phase 6 adds:

- `enable_order_check`
- `max_deviation_points`
- `request_action`
- `request_type`
- `request_symbol`
- `request_volume`
- `request_price`
- `request_sl`
- `request_tp`
- `request_deviation`
- `request_magic`
- `request_type_time`
- `request_type_filling`
- `order_check_call_success`
- `order_check_retcode`
- `order_check_comment`
- `order_check_balance`
- `order_check_equity`
- `order_check_profit`
- `order_check_margin`
- `order_check_margin_free`
- `order_check_margin_level`
- `last_error`
- `last_error_description`

When `EnableOrderCheck=false`, `order_check_*` fields are omitted.

`ORDER_CHECK_PASSED_NO_TRADE` requires `OrderCheck` to return `true` and `order_check_retcode` to equal `TRADE_RETCODE_DONE`. `ORDER_CHECK_REJECTED` requires a meaningful non-zero non-success trade retcode. If `OrderCheck` returns `false`, or if `order_check_retcode` remains `0` or unavailable, the command is rejected with `ORDER_CHECK_FAILED` because the check did not produce a valid success or rejection retcode.

Responses must not include `order`, `deal`, `ticket`, `position`, `execution_price`, or `fill_price` fields.

## Error Codes

Phase 6 keeps earlier protocol, market-validation, and risk-calculation error codes and adds:

- `ORDER_CHECK_PASSED_NO_TRADE`
- `EXECUTION_PREVIEW_READY_NO_TRADE`
- `DRY_RUN_REQUIRED`
- `INVALID_DEVIATION_POINTS`
- `ORDER_REQUEST_BUILD_FAILED`
- `ORDER_FILLING_MODE_UNAVAILABLE`
- `ORDER_CHECK_FAILED`
- `ORDER_CHECK_REJECTED`

## Manual Test Setup

1. Open `mt5/Experts/MTChartBridge/MTChartBridgeEA.mq5` in MetaEditor.
2. Compile and confirm 0 errors.
3. Attach the EA to a chart in MT5.
4. Confirm `Terminal/Common/Files/MTChartBridge/status.json` is updating and reports `ea_phase` as `phase-6-execution-check`.
5. For each test, write a command payload to `Terminal/Common/Files/MTChartBridge/inbox/<id>.command.json.tmp`.
6. Create the ready marker `Terminal/Common/Files/MTChartBridge/inbox/<id>.command.ready`.
7. Read `Terminal/Common/Files/MTChartBridge/outbox/<id>.response.json.tmp`.
8. Confirm accepted command files move to `processed/` and rejected command files move to `failed/`.

Use fresh command ids for each test because duplicate ids are rejected within the EA session.

## Manual Test Cases

A. Valid buy OrderCheck:

- Set `EnableOrderCheck=true`.
- Use a valid `buy` command with `dry_run=true`.
- Set `stop_loss` below current Ask and `take_profit` above current Ask.
- Expected `status`: `accepted`, or `rejected` with `ORDER_CHECK_REJECTED` if the broker/server rejects the checked request.
- Expected accepted `code`: `ORDER_CHECK_PASSED_NO_TRADE`
- If rejected as `ORDER_CHECK_REJECTED`, `order_check_retcode` must be non-zero and explain the rejection with `order_check_comment`.
- If `order_check_retcode` is `0`, expected `code` is `ORDER_CHECK_FAILED`, not `ORDER_CHECK_REJECTED`.
- Response includes `request_*` fields and `order_check_*` fields.
- No trade is executed.

B. Valid sell OrderCheck:

- Set `EnableOrderCheck=true`.
- Use a valid `sell` command with `dry_run=true`.
- Set `stop_loss` above current Bid and `take_profit` below current Bid.
- Expected `status`: `accepted`, or `rejected` with `ORDER_CHECK_REJECTED` if the broker/server rejects the checked request.
- Expected accepted `code`: `ORDER_CHECK_PASSED_NO_TRADE`
- If rejected as `ORDER_CHECK_REJECTED`, `order_check_retcode` must be non-zero and explain the rejection with `order_check_comment`.
- If `order_check_retcode` is `0`, expected `code` is `ORDER_CHECK_FAILED`, not `ORDER_CHECK_REJECTED`.
- Response includes `request_*` fields and `order_check_*` fields.
- No trade is executed.

C. `dry_run=false` rejection:

- Use an otherwise valid command with `dry_run=false`.
- Expected `status`: `rejected`
- Expected `code`: `DRY_RUN_REQUIRED`
- OrderCheck is not needed.
- No trade is executed.

D. `EnableOrderCheck=false` preview:

- Set `EnableOrderCheck=false`.
- Use a valid command with `dry_run=true`.
- Expected `status`: `accepted`
- Expected `code`: `EXECUTION_PREVIEW_READY_NO_TRADE`
- Response includes `request_*` fields.
- Response does not need `order_check_*` fields.
- No trade is executed.

E. Invalid `MaxDeviationPoints`:

- Set `MaxDeviationPoints=-1`.
- Use a valid command with `dry_run=true`.
- Expected `status`: `rejected`
- Expected `code`: `INVALID_DEVIATION_POINTS`
- No trade is executed.

F. Ensure no live execution:

- Static scan must show no `OrderSend`.
- Static scan must show no `CTrade` import.
- MT5 Trade tab must remain unchanged.
- Responses must not include `order`, `deal`, `ticket`, `position`, `execution_price`, or `fill_price` fields.
