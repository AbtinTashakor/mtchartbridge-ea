# Local Folder Protocol

MTChartBridge uses the MetaTrader common files folder as the only transport between the Chrome Extension and the MT5 Expert Advisor.

The protocol is file based:

- Commands are written by the extension.
- Commands are read and validated by the EA.
- Final trade volume is the EA's responsibility and must be calculated inside MT5 in a later phase.
- Responses are written by the EA.

Phase 4 uses this local folder structure under `Terminal/Common/Files/MTChartBridge/`:

```text
inbox/
outbox/
processed/
failed/
```

The extension writes command payloads to `inbox/<command_id>.command.json.tmp`, then creates `inbox/<command_id>.command.ready`.

The EA only processes commands with a ready marker. It writes responses to `outbox/<command_id>.response.json.tmp`, then creates `outbox/<command_id>.response.ready`.

Accepted commands are moved to `processed/`. Invalid, missing, unreadable, expired, or duplicate commands are moved to `failed/` when possible.

Phase 4 keeps Phase 3 protocol validation, command TTL checks, and session-level duplicate-command detection. After protocol validation passes, it validates live MT5 market state for the command symbol. It does not execute trades and does not calculate final trade volume yet.

New Phase 4 EA inputs:

- `RejectIfSpreadAbovePoints`: default `0`; values greater than `0` reject commands when current spread points are above the input.
- `AllowedSymbols`: default empty; when set, a comma-separated symbol allowlist matched case-insensitively after trimming spaces.

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

All responses include `type`, `id`, `status`, `code`, `message`, `ea_phase`, `trace_id`, `timestamp_local`, `received_at_local`, and `processed_at_local`. When parsed from the command, responses also include `symbol`, `side`, `dry_run`, `source`, and `comment`.

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

Accepted commands return:

```json
{
  "status": "accepted",
  "code": "MARKET_VALIDATION_PASSED"
}
```

The accepted response message is:

```text
Command passed protocol and market validation. No trade was executed in Phase 4.
```

Phase 4 market validation can reject commands with:

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

See `command.example.json` and `response.example.json` for the Phase 4 message shape.
