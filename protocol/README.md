# Local Folder Protocol

MTChartBridge uses the MetaTrader common files folder as the only transport between the Chrome Extension and the MT5 Expert Advisor.

The protocol is file based:

- Commands are written by the extension.
- Commands are read and validated by the EA.
- Final trade volume is calculated by the EA inside MT5.
- Responses are written by the EA.
- No live order is sent in Phase 6.

Phase 6 uses this local folder structure under `Terminal/Common/Files/MTChartBridge/`:

```text
inbox/
outbox/
processed/
failed/
```

The extension writes command payloads to `inbox/<command_id>.command.json.tmp`, then creates `inbox/<command_id>.command.ready`.

The EA only processes commands with a ready marker. It writes responses to `outbox/<command_id>.response.json.tmp`, then creates `outbox/<command_id>.response.ready`.

Accepted commands are moved to `processed/`. Invalid, missing, unreadable, expired, or duplicate commands are moved to `failed/` when possible.

Phase 6 keeps Phase 3 protocol validation, command TTL checks, session-level duplicate-command detection, Phase 4 live market validation, and Phase 5 risk calculation. After risk calculation passes, it requires `dry_run=true`, builds an `MqlTradeRequest` preview, and optionally runs `OrderCheck`. It does not call `OrderSend` and does not execute trades.

Market-validation EA inputs:

- `RejectIfSpreadAbovePoints`: default `0`; values greater than `0` reject commands when current spread points are above the input.
- `AllowedSymbols`: default empty; when set, a comma-separated symbol allowlist matched case-insensitively after trimming spaces.

Risk EA inputs:

- `MaxRiskPercent`: default `2.0`; rejects commands whose `risk_percent` is above this value.
- `MaxVolume`: default `0.0`; when greater than `0`, caps calculated volume down to the largest valid `SYMBOL_VOLUME_STEP` not exceeding this value.

Execution-check EA inputs:

- `EnableOrderCheck`: default `true`; when enabled, the EA runs `OrderCheck` against the built request. When disabled, the EA returns a request preview without `order_check_*` fields.
- `MaxDeviationPoints`: default `20`; applied to the no-trade request preview. Negative values reject with `INVALID_DEVIATION_POINTS`.

## Command Fields

Required fields:

- `type`: must equal `trade.open`
- `id`: non-empty command id matching the filename
- `created_at`: UTC timestamp in `YYYY-MM-DDTHH:MM:SS.mmmZ` form
- `ttl_ms`: positive integer not exceeding the EA `MaxCommandTtlMs` input
- `symbol`: non-empty string
- `side`: `buy` or `sell`
- `risk_percent`: positive number
- `stop_loss`: non-zero number
- `dry_run`: boolean

Optional fields:

- `take_profit`
- `comment`
- `client_version`
- `source`

## Responses

All responses include `type`, `id`, `status`, `code`, `message`, `ea_phase`, `trace_id`, `timestamp_local`, `received_at_local`, and `processed_at_local`. When parsed from the command, responses also include `symbol`, `side`, `risk_percent`, `dry_run`, `source`, and `comment`.

Market validation responses also include available market context:

- `bid`
- `ask`
- `entry_price_reference`
- `spread_points`
- `stop_level_points`
- `point`
- `digits`
- `stop_loss`
- `take_profit`
- `allowed_symbols`
- `reject_if_spread_above_points`

Risk calculation responses include risk fields as they become available:

- `equity`
- `risk_percent`
- `max_risk_percent`
- `risk_amount`
- `calculation_method`: `OrderCalcProfit`
- `loss_per_lot`
- `raw_volume`
- `volume`
- `estimated_loss`
- `estimated_profit_at_sl`
- `volume_min`
- `volume_max`
- `volume_step`
- `max_volume`
- `volume_normalized_down`

Execution-check responses include request preview fields after the request is built:

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

When `EnableOrderCheck=true` and `OrderCheck` is reached, responses also include:

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

`ORDER_CHECK_PASSED_NO_TRADE` requires `OrderCheck` to return `true` and `order_check_retcode` to equal `TRADE_RETCODE_DONE`. `ORDER_CHECK_REJECTED` is only used when `OrderCheck` returns `true` with a meaningful non-zero non-success trade retcode. If `OrderCheck` returns `false`, or if the check result retcode remains `0` or unavailable, the EA returns `ORDER_CHECK_FAILED` with diagnostics instead of treating the result as a server rejection.

Responses do not include final live execution identifiers such as order, deal, ticket, position, execution price, or fill price fields.

Accepted commands return:

```json
{
  "status": "accepted",
  "code": "ORDER_CHECK_PASSED_NO_TRADE"
}
```

The accepted response message is:

```text
Command passed validation, risk calculation, and MT5 OrderCheck. No trade was executed in Phase 6.
```

When `EnableOrderCheck=false`, accepted commands return `EXECUTION_PREVIEW_READY_NO_TRADE` and omit `order_check_*` fields.

Market validation can reject commands with:

- `SYMBOL_NOT_ALLOWED`
- `SYMBOL_SELECT_FAILED`
- `SYMBOL_PRICE_UNAVAILABLE`
- `SYMBOL_TRADE_DISABLED`
- `TERMINAL_TRADE_DISABLED`
- `ACCOUNT_TRADE_DISABLED`
- `SPREAD_TOO_HIGH`
- `INVALID_STOP_LOSS`
- `INVALID_TAKE_PROFIT`
- `STOP_LOSS_TOO_CLOSE`
- `TAKE_PROFIT_TOO_CLOSE`

Risk calculation can reject commands with:

- `EQUITY_UNAVAILABLE`
- `RISK_PERCENT_TOO_HIGH`
- `ORDER_CALC_PROFIT_FAILED`
- `STOP_LOSS_LOSS_NOT_POSITIVE`
- `INVALID_CALCULATED_VOLUME`
- `SYMBOL_VOLUME_CONSTRAINTS_UNAVAILABLE`
- `RISK_TOO_SMALL_FOR_MIN_VOLUME`
- `ESTIMATED_LOSS_EXCEEDS_RISK`

Execution checking can reject commands with:

- `DRY_RUN_REQUIRED`
- `INVALID_DEVIATION_POINTS`
- `ORDER_REQUEST_BUILD_FAILED`
- `ORDER_FILLING_MODE_UNAVAILABLE`
- `ORDER_CHECK_FAILED`
- `ORDER_CHECK_REJECTED`

Expired commands return:

```json
{
  "status": "rejected",
  "code": "COMMAND_EXPIRED"
}
```

Duplicate commands within the same EA session return:

```json
{
  "status": "duplicate",
  "code": "DUPLICATE_COMMAND"
}
```

Phase 6 accepted codes:

- `ORDER_CHECK_PASSED_NO_TRADE`
- `EXECUTION_PREVIEW_READY_NO_TRADE`

See `command.example.json` and `response.example.json` for the Phase 6 message shape.
