# Phase 8 Persistent Idempotency Test

Phase 8 adds persistent command-state files and an append-only execution audit log while preserving the local-only bridge architecture and the Phase 7 live execution gates.

Session-only duplicate protection is not enough once `OrderSend` exists. If MT5 or the EA restarts after a command is processed, the in-memory duplicate cache is lost. Phase 8 makes `state/commands/<command_id>.state.json` authoritative so a command id that was already claimed, finalized, or left in a live-send pending state cannot reach market validation, risk calculation, `OrderCheck`, or `OrderSend` again.

## Runtime Folders

The EA creates these additional folders under `Terminal/Common/Files/MTChartBridge/`:

```text
state/
  commands/
audit/
```

`state/commands/` stores one JSON state file per validated, filename-safe command id. New commands are written as `state="claimed"`, final responses update the file to `state="final"`, and the live path writes `state="order_send_pending"` immediately before `OrderSend`.

`audit/events.jsonl` stores append-only JSON lines for lifecycle events including command detection, claim, persistent duplicate detection, rejection, acceptance, OrderCheck, OrderSend, response writing, and archive movement.

## Crash and Restart Safety

`order_send_pending` blocks reprocessing because the EA may have crashed after preparing or attempting live execution. On restart, that state is treated as indeterminate and returns `COMMAND_EXECUTION_STATE_INDETERMINATE`; the EA does not call `OrderSend` again.

Persistent state read/write ambiguity fails closed. If `EnablePersistentIdempotency=true` and the EA cannot safely read or write command state before live execution, the command is rejected and cannot continue into `OrderSend`.

Audit writes are also fail-safe before live execution. If an audit append fails before a possible live send, the command is rejected with `AUDIT_WRITE_FAILED`. If audit append fails after live execution was already attempted, the response preserves the `OrderSend` result and includes `audit_write_failed=true` when possible.

## Inputs

- `EnablePersistentIdempotency=true`: enables persistent state files and restart-safe duplicate blocking.
- `EnableAuditLog=true`: enables append-only audit events.

For production, keep both inputs enabled. When `EnablePersistentIdempotency=false`, duplicate protection is session-level only and `status.json` includes a warning. When `EnableAuditLog=false`, commands still process but audit events are skipped.

## Response Fields

Phase 8 responses include `persistent_idempotency_enabled` and `audit_log_enabled`. When relevant they also include `persistent_duplicate`, `command_state_path`, `previous_state`, `previous_status`, `previous_code`, `previous_order_send_attempted`, `command_claimed_at_local`, `command_finalized_at_local`, `audit_write_failed`, and `state_write_failed`.

## Error Codes

- `PERSISTENT_DUPLICATE_COMMAND`
- `COMMAND_ALREADY_CLAIMED`
- `COMMAND_EXECUTION_STATE_INDETERMINATE`
- `COMMAND_STATE_WRITE_FAILED`
- `COMMAND_STATE_READ_FAILED`
- `AUDIT_WRITE_FAILED`

## Manual Test Cases

A. Dry-run command then duplicate after EA restart

1. Send a valid `dry_run=true` command.
2. Let it finish and confirm a final state file exists under `state/commands/`.
3. Restart or re-attach the EA.
4. Send the same command id again.
5. Expected: `status="duplicate"`, `code="PERSISTENT_DUPLICATE_COMMAND"`, no market/risk/execution rerun, and no `OrderSend`.

B. Live-gate rejection then duplicate after EA restart

1. Send `dry_run=false` while `EnableLiveTrading=false`.
2. Expected first response: `status="rejected"`, `code="LIVE_TRADING_DISABLED"`.
3. Restart or re-attach the EA.
4. Send the same command id again.
5. Expected: persistent duplicate response and no `OrderSend`.

C. Claimed/incomplete state blocks reprocessing

1. Manually create `state/commands/<fake_id>.state.json` with `state="claimed"`.
2. Send a command with the matching id.
3. Expected: `status="rejected"`, `code="COMMAND_ALREADY_CLAIMED"`, `persistent_duplicate=true`, and no `OrderSend`.

D. `order_send_pending` state blocks reprocessing

1. Manually create `state/commands/<fake_id>.state.json` with `state="order_send_pending"` and `order_send_attempted=true`.
2. Send a command with the matching id.
3. Expected: `status="rejected"`, `code="COMMAND_EXECUTION_STATE_INDETERMINATE"`, `persistent_duplicate=true`, `previous_order_send_attempted=true`, and no `OrderSend`.

E. Audit log gets lifecycle events

1. Send any valid command.
2. Confirm `audit/events.jsonl` includes `command_detected`, `command_claimed`, `response_written`, and `command_archived`.
3. For the OrderCheck path, confirm `order_check_started` and `order_check_finished`.
4. For a controlled demo live send, confirm `order_send_pending` and `order_send_finished`.

F. Persistent idempotency disabled

1. Set `EnablePersistentIdempotency=false`.
2. Confirm `status.json` includes `persistent_idempotency_enabled=false` and the persistent-idempotency warning.
3. Confirm session-level duplicate behavior still works.
4. Do not use this mode for live testing.

G. Audit disabled

1. Set `EnableAuditLog=false`.
2. Confirm `status.json` includes `audit_log_enabled=false`.
3. Confirm commands still process.
4. Confirm no new audit lines are required.
