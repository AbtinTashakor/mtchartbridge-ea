# Phase 2 Command Intake Test

Phase 2 lets the MTChartBridge EA read local command files from the shared common-folder inbox and write local response files to the outbox.

No trade is executed in Phase 2. The EA does not import `CTrade`, does not send orders, and does not calculate risk or final volume yet.

## Common Folder Structure

All files are under the MetaTrader common files folder:

```text
Terminal/Common/Files/MTChartBridge/
  .mtchartbridge-folder
  status.json
  inbox/
  processing/
  outbox/
  processed/
  failed/
  logs/
```

The EA uses `FILE_COMMON` for all shared-folder reads and writes.

## Command Pattern

The future Chrome Extension will write a command payload first:

```text
MTChartBridge/inbox/<command_id>.command.json.tmp
```

After the payload write is complete, it will create the ready marker:

```text
MTChartBridge/inbox/<command_id>.command.ready
```

The EA only processes commands with a matching `.command.ready` marker.

## Response Pattern

For each processed command, the EA writes the response payload first:

```text
MTChartBridge/outbox/<command_id>.response.json.tmp
```

Then it creates the response ready marker:

```text
MTChartBridge/outbox/<command_id>.response.ready
```

Accepted commands are copied to `processed/` and removed from `inbox/`. Invalid, missing, or unreadable commands are copied to `failed/` and removed from `inbox/` when possible.

## Manual Test

1. Attach or restart `MTChartBridgeEA` in MT5.
2. Confirm `Terminal/Common/Files/MTChartBridge/status.json` is updating.
3. Create this file:

```text
Terminal/Common/Files/MTChartBridge/inbox/cmd-test-001.command.json.tmp
```

4. Put this JSON in the file:

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
  "comment": "MTChartBridge"
}
```

5. After the payload exists, create the ready marker:

```text
Terminal/Common/Files/MTChartBridge/inbox/cmd-test-001.command.ready
```

The ready marker can be empty.

## Expected Result

The EA should create:

```text
Terminal/Common/Files/MTChartBridge/outbox/cmd-test-001.response.json.tmp
Terminal/Common/Files/MTChartBridge/outbox/cmd-test-001.response.ready
```

The response JSON should have:

```json
{
  "status": "accepted",
  "code": "COMMAND_RECEIVED",
  "message": "Command received by EA. No trade was executed in Phase 2.",
  "ea_phase": "phase-2-command-intake"
}
```

The original command files should move from `inbox/` to:

```text
Terminal/Common/Files/MTChartBridge/processed/
```

If the command is invalid, the response status should be `rejected` and the command files should move to:

```text
Terminal/Common/Files/MTChartBridge/failed/
```

## Experts Logs

Open the MT5 Toolbox, then the Experts tab. Successful intake logs include:

- command ready file detected
- command file read
- response written
- command moved to `processed/`

Rejected commands log the error and move to `failed/` when possible.

## If Compilation Fails

Copy back the compiler error lines from MetaEditor, including the file name, line number, column, and message. Do not copy generated `.ex5` files or runtime common-folder files.
