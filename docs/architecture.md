# Architecture

MTChartBridge EA uses a local-only bridge architecture:

```text
Chrome Extension <-> Local Shared Folder <-> MT5 Expert Advisor
```

The Chrome Extension and MT5 do not communicate over the internet, sockets, WebRequest, DLLs, native bridges, or cloud relays. The shared folder is selected by the user and acts as the handoff point for command and response files.

## Components

- Chrome Extension: creates command files from user actions.
- Local Shared Folder: stores command and response files.
- MT5 Expert Advisor: reads commands, claims each command id in persistent local state, validates commands, calculates final risk-based volume inside MT5, builds an execution request, optionally previews/checks dry-run commands, and writes responses. Phase 7 can call raw `OrderSend` only when `dry_run=false` and every explicit live execution gate passes. Phase 8 blocks any previously claimed or finalized command id before market validation, risk calculation, `OrderCheck`, or `OrderSend`.

## Non-Goals

- No signal generation.
- No automated strategy engine.
- No cloud service.
- No installer.
- No native bridge.

## Live Execution Gate

Phase 7 preserves the local-only folder architecture and does not add WebRequest, sockets, DLLs, a native bridge, cloud relay, signal generation, or extension-side volume calculation.

Live execution is disabled by default. A command can reach `OrderSend` only after protocol validation, market validation, MT5-side risk calculation, request building, live input gates, terminal/account/MQL trading permission checks, and a successful `OrderCheck` retcode. `dry_run=true` commands never call `OrderSend`.

## Persistent Idempotency and Audit Log

Phase 8 adds local runtime folders under `Terminal/Common/Files/MTChartBridge/`:

```text
state/
  commands/
audit/
```

`state/commands/<command_id>.state.json` is the authoritative duplicate guard when `EnablePersistentIdempotency=true`. New commands are claimed before validation reaches market data, risk calculation, `OrderCheck`, or live send logic. Final responses update the same state file to `state="final"`. Immediately before a live `OrderSend`, the EA writes `state="order_send_pending"` with `order_send_attempted=true`; if the EA restarts with that state present, it rejects the duplicate as indeterminate and does not send again.

`audit/events.jsonl` is append-only when `EnableAuditLog=true`. It records lifecycle events such as command detection, claim, duplicate detection, OrderCheck, OrderSend, response writing, and archive movement. Audit or state ambiguity before live execution fails closed and prevents `OrderSend`.
