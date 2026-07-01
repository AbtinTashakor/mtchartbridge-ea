# AGENTS.md

Rules for contributors and coding agents working on MTChartBridge EA:

- Preserve the local-only architecture.
- No cloud relay.
- No WebRequest.
- No sockets.
- No DLLs.
- No native bridge.
- No installer.
- No signal generation.
- EA must calculate final trade volume inside MT5.
- Do not accept final volume from the extension.
- Do not commit generated `.ex5` files or runtime files.
- Use small phase-based commits.
- Update docs when behavior or protocol changes.
- Add this trailer when Codex materially contributes:
  `Co-authored-by: OpenAI Codex <codex@openai.com>`
