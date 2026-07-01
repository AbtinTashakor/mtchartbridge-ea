# Local Folder Protocol

The local folder protocol is the only communication path for Phase 1.

## Folder Flow

```text
inbox -> processing -> processed
                  \-> failed
outbox
```

Suggested folder responsibilities:

- `inbox/`: commands written by the extension.
- `processing/`: commands claimed by the EA while being handled.
- `outbox/`: responses written by the EA.
- `processed/`: successfully handled commands.
- `failed/`: rejected or failed commands.

Runtime folders are user-local data and must not be committed.

## Command Handling

The EA should validate command shape, symbol, action, dry-run mode, trade settings, and risk settings before any trade action is attempted.

The extension must not send final volume. Final trade volume is calculated inside MT5 by the EA.
