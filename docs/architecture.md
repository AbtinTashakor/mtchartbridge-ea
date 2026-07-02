# Architecture

MTChartBridge EA uses a local-only bridge architecture:

```text
Chrome Extension <-> Local Shared Folder <-> MT5 Expert Advisor
```

The Chrome Extension and MT5 do not communicate over the internet, sockets, WebRequest, DLLs, native bridges, or cloud relays. The shared folder is selected by the user and acts as the handoff point for command and response files.

## Components

- Chrome Extension: creates command files from user actions.
- Local Shared Folder: stores command and response files.
- MT5 Expert Advisor: reads commands, validates them, and writes responses. Final volume remains the EA's responsibility and must be calculated in MT5 in a later phase.

## Non-Goals

- No signal generation.
- No automated strategy engine.
- No cloud service.
- No installer.
- No native bridge.
