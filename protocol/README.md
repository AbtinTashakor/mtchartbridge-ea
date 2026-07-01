# Local Folder Protocol

MTChartBridge uses a user-selected local folder as the only transport between the Chrome Extension and the MT5 Expert Advisor.

The protocol is file based:

- Commands are written by the extension.
- Commands are read and validated by the EA.
- Final trade volume is calculated inside MT5.
- Responses are written by the EA.

See `command.example.json` and `response.example.json` for the Phase 1 message shape.
