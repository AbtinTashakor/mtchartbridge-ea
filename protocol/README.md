# Local Folder Protocol

MTChartBridge uses the MetaTrader common files folder as the only transport between the Chrome Extension and the MT5 Expert Advisor.

The protocol is file based:

- Commands are written by the extension.
- Commands are read and validated by the EA.
- Final trade volume is calculated inside MT5.
- Responses are written by the EA.

Phase 2 uses this local folder structure under `Terminal/Common/Files/MTChartBridge/`:

```text
inbox/
outbox/
processed/
failed/
```

The extension writes command payloads to `inbox/<command_id>.command.json.tmp`, then creates `inbox/<command_id>.command.ready`.

The EA only processes commands with a ready marker. It writes responses to `outbox/<command_id>.response.json.tmp`, then creates `outbox/<command_id>.response.ready`.

Accepted commands are moved to `processed/`. Invalid, missing, or unreadable commands are moved to `failed/` when possible.

Phase 2 only validates command structure and writes accepted or rejected responses. It does not execute trades and does not calculate final trade volume yet.

See `command.example.json` and `response.example.json` for the Phase 2 message shape.
