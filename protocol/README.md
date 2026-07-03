# Local Folder Protocol

MTChartBridge uses the MetaTrader common files folder as the only transport between the Chrome Extension and the MT5 Expert Advisor.

The protocol is file based:

- Commands are written by the extension.
- Commands are read and validated by the EA.
- Final trade volume is calculated by the EA inside MT5.
- Responses are written by the EA.

Phase 5 uses this local folder structure under `Terminal/Common/Files/MTChartBridge/`:

```text
inbox/
outbox/
processed/
failed/
```

The extension writes command payloads to `inbox/<command_id>.command.json.tmp`, then creates `inbox/<command_id>.command.ready`.

The EA only processes commands with a ready marker. It writes responses to `outbox/<command_id>.response.json.tmp`, then creates `outbox/<command_id>.response.ready`.

Accepted commands are moved to `processed/`. Invalid, missing, unreadable, expired, or duplicate commands are moved to `failed/` when possible.

Phase 5 keeps Phase 3 protocol validation, command TTL checks, session-level duplicate-command detection, and Phase 4 live market validation. After market validation passes, it calculates risk amount and final volume inside MT5. It does not execute trades.

Market-validation EA inputs:

- `RejectIfSpreadAbovePoints`: default `0`; values greater than `0` reject commands when current spread points are above the input.
- `AllowedSymbols`: default empty; when set, a comma-separated symbol allowlist matched case-insensitively after trimming spaces.

Risk EA inputs:

- `MaxRiskPercent`: default `2.0`; rejects commands whose `risk_percent` is above this value.
- `MaxVolume`: default `0.0`; when greater than `0`, caps calculated volume down to the largest valid `SYMBOL_VOLUME_STEP` not exceeding this value.

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

Accepted commands return:

```json
{
  "status": "accepted",
  "code": "RISK_CALCULATED"
}
```

The accepted response message is:

```text
Command passed validation and risk calculation. No trade was executed in Phase 5.
```

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

See `command.example.json` and `response.example.json` for the Phase 5 message shape.
