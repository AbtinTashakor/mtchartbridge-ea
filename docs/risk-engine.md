# Risk Engine

The EA owns final trade volume calculation.

The extension may provide risk intent through `risk_percent`, but it must not provide final volume. The EA calculates and validates final volume inside MT5 using terminal, account, market, and symbol constraints.

## Rules

- Do not accept final volume directly from the extension.
- Validate symbol trade constraints in MT5.
- Use `OrderCalcProfit` to calculate hypothetical stop-loss loss.
- Normalize volume down to the symbol volume step.
- Enforce minimum volume by rejection rather than raising risk above the request.
- Enforce broker maximum volume and optional `MaxVolume` by capping down.
- Reject commands that cannot be sized safely.
- Keep dry-run handling available for validation without execution.

Phase 5 implements the first risk engine. It calculates volume and estimated stop-loss loss, writes those values to the response, and does not execute trades.
