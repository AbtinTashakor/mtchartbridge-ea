# Phase 1 EA Core Test

Phase 1 focuses on the local-only MT5 Expert Advisor core.

## Test Goals

- EA source is present at `mt5/Experts/MTChartBridge/MTChartBridgeEA.mq5`.
- Generated `.ex5` files are ignored.
- Runtime logs and local protocol folders are ignored.
- The project documents the local folder bridge architecture.
- Protocol examples exist for command and response files.
- Risk ownership is documented: final volume is calculated inside MT5.

## Manual Checks

1. Confirm the repository contains no generated `.ex5` files in Git.
2. Compile the EA locally in MetaEditor.
3. Attach the EA to an MT5 chart.
4. Configure a test local shared folder.
5. Send a dry-run command through the local folder flow.
6. Confirm the EA writes a response without relying on internet access, DLLs, sockets, or WebRequest.
