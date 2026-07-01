# Local Folder Protocol

MTChartBridge uses the MetaTrader common files folder as the only transport between the Chrome Extension and the MT5 Expert Advisor.

The protocol is file based:

- Commands are written by the extension.
- Commands are read and validated by the EA.
- Final trade volume is calculated inside MT5.
- Responses are written by the EA.

Phase 3 uses this local folder structure under `Terminal/Common/Files/MTChartBridge/`:

```text
inbox/
outbox/
processed/
failed/
```

The extension writes command payloads to `inbox/<command_id>.command.json.tmp`, then creates `inbox/<command_id>.command.ready`.

The EA only processes commands with a ready marker. It writes responses to `outbox/<command_id>.response.json.tmp`, then creates `outbox/<command_id>.response.ready`.

Accepted commands are moved to `processed/`. Invalid, missing, unreadable, expired, or duplicate commands are moved to `failed/` when possible.

Phase 3 hardens protocol validation, checks command TTL, and keeps a session-level duplicate-command cache. It does not execute trades and does not calculate final trade volume yet.

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

Accepted commands return:

```json
{
  "status": "accepted",
  "code": "COMMAND_RECEIVED"
}
```

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

See `command.example.json` and `response.example.json` for the Phase 3 message shape.
