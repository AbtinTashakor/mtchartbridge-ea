# Phase 3 Protocol Hardening Test

Phase 3 hardens local command validation and adds the session-level foundation for idempotency.

No trade is executed in Phase 3. The EA does not import `CTrade`, does not send orders, does not validate broker trading conditions, and does not calculate risk or final volume yet.

## Required Command Fields

- `type`: must equal `trade.open`
- `id`: non-empty and must match the command filename
- `created_at`: UTC timestamp in `YYYY-MM-DDTHH:MM:SS.mmmZ` format
- `ttl_ms`: positive integer and no greater than `MaxCommandTtlMs`
- `symbol`: non-empty string
- `side`: `buy` or `sell`
- `risk_percent`: positive number
- `stop_loss`: non-zero number
- `dry_run`: boolean

## Optional Command Fields

- `take_profit`
- `comment`
- `client_version`
- `source`

When present and parsed, `source` is included in responses. `comment` is escaped before it is echoed in a response.

## TTL Behavior

The EA inputs are:

```mql5
input bool EnforceCommandTtl = true;
input int MaxCommandTtlMs = 30000;
```

`ttl_ms` is always validated as a positive integer that does not exceed `MaxCommandTtlMs`.

When `EnforceCommandTtl` is `true`, the EA parses `created_at` as UTC in `YYYY-MM-DDTHH:MM:SS.mmmZ` form. Milliseconds are ignored and seconds precision is used. The parsed timestamp is compared with `TimeGMT()`. If the command age is greater than `ttl_ms`, the command is rejected with:

```json
{
  "status": "rejected",
  "code": "COMMAND_EXPIRED"
}
```

If `EnforceCommandTtl` is `false`, the EA still validates `ttl_ms` shape and maximum value, but it does not reject commands because of age.

## Duplicate Command Behavior

The EA input is:

```mql5
input int ProcessedCommandCacheSize = 200;
```

The EA keeps an in-memory cache of recent command IDs and their final `status` and `code`. This is session-level idempotency only. Persistent idempotency across EA restarts is a future improvement.

If the same command ID appears again during the same EA session, the EA does not process trade logic for that command. It writes:

```json
{
  "status": "duplicate",
  "code": "DUPLICATE_COMMAND",
  "message": "Command was already processed by this EA session."
}
```

Duplicate command files are moved to `failed/`.

## Response Fields

All responses include:

- `type`: `trade.response`
- `id`
- `status`
- `code`
- `message`
- `ea_phase`: `phase-3-protocol-hardening`
- `trace_id`
- `timestamp_local`
- `received_at_local`
- `processed_at_local`

When parsed from the command, responses also include:

- `symbol`
- `side`
- `dry_run`
- `source`
- `comment`

## Error Codes

- `COMMAND_RECEIVED`
- `INVALID_COMMAND`
- `INVALID_TYPE`
- `ID_MISMATCH`
- `MISSING_REQUIRED_FIELD`
- `INVALID_TTL`
- `COMMAND_EXPIRED`
- `INVALID_SIDE`
- `INVALID_RISK_PERCENT`
- `INVALID_STOP_LOSS`
- `DUPLICATE_COMMAND`
- `COMMAND_FILE_MISSING`
- `COMMAND_FILE_READ_FAILED`
- `RESPONSE_WRITE_FAILED`
- `ARCHIVE_FAILED`

`RESPONSE_WRITE_FAILED` and `ARCHIVE_FAILED` are logged because the EA may not be able to write a response when those failures occur.

## Manual Test Setup

1. Attach or restart `MTChartBridgeEA` in MT5.
2. Confirm `Terminal/Common/Files/MTChartBridge/status.json` is updating.
3. Use the `Terminal/Common/Files/MTChartBridge/inbox/` folder for test commands.
4. Write the payload file first:

```text
MTChartBridge/inbox/<command_id>.command.json.tmp
```

5. Create the ready marker after the payload exists:

```text
MTChartBridge/inbox/<command_id>.command.ready
```

The ready marker can be empty.

## A. Valid Command

Payload file:

```text
MTChartBridge/inbox/cmd-test-001.command.json.tmp
```

Payload JSON:

```json
{
  "type": "trade.open",
  "id": "cmd-test-001",
  "created_at": "2026-07-01T12:30:00.000Z",
  "ttl_ms": 5000,
  "symbol": "EURUSD",
  "side": "buy",
  "risk_percent": 1.0,
  "stop_loss": 1.08000,
  "take_profit": 1.09000,
  "dry_run": true,
  "comment": "MTChartBridge",
  "client_version": "0.1.0",
  "source": "chrome-extension"
}
```

Replace `created_at` with the current UTC time before creating the ready marker when `EnforceCommandTtl = true`.

Create:

```text
MTChartBridge/inbox/cmd-test-001.command.ready
```

Expected response:

```json
{
  "status": "accepted",
  "code": "COMMAND_RECEIVED"
}
```

Expected archive folder: `processed/`.

## B. Missing Required Field

Use a new command ID, then remove `risk_percent` or `stop_loss`.

Expected response:

```json
{
  "status": "rejected",
  "code": "MISSING_REQUIRED_FIELD"
}
```

If `stop_loss` is present but zero, expected code is `INVALID_STOP_LOSS`.

Expected archive folder: `failed/`.

## C. Invalid Side

Use a new command ID and set:

```json
{
  "side": "long"
}
```

Expected response:

```json
{
  "status": "rejected",
  "code": "INVALID_SIDE"
}
```

Expected archive folder: `failed/`.

## D. ID Mismatch

Payload file:

```text
MTChartBridge/inbox/cmd-test-004.command.json.tmp
```

Set the JSON id:

```json
{
  "id": "cmd-other"
}
```

Create:

```text
MTChartBridge/inbox/cmd-test-004.command.ready
```

Expected response:

```json
{
  "status": "rejected",
  "code": "ID_MISMATCH"
}
```

Expected archive folder: `failed/`.

## E. Expired Command

Use a `created_at` value old enough to exceed `ttl_ms`, with `EnforceCommandTtl = true`.

Example:

```json
{
  "created_at": "2020-01-01T00:00:00.000Z",
  "ttl_ms": 5000
}
```

Expected response:

```json
{
  "status": "rejected",
  "code": "COMMAND_EXPIRED"
}
```

Expected archive folder: `failed/`.

## F. Duplicate Command

1. Submit a valid command such as `cmd-test-006`.
2. Confirm the first response is accepted.
3. Submit another command with the same command ID during the same EA session.

Expected second response:

```json
{
  "status": "duplicate",
  "code": "DUPLICATE_COMMAND"
}
```

Expected archive folder for the duplicate files: `failed/`.

## Experts Logs

Open the MT5 Toolbox, then the Experts tab. Useful logs include:

- command ready file detected
- command file read
- protocol validation passed
- protocol validation rejected with code
- expired command detected
- duplicate command detected
- response written
- command moved to `processed/` or `failed/`
- response write or archive errors

Debug-only details respect `EnableDebugLogs`.
