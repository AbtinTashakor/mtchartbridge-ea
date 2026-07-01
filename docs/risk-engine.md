# Risk Engine

The EA owns final trade volume calculation.

The extension may provide risk intent, such as a fixed-lot request or risk configuration, but the EA must calculate and validate the final volume inside MT5 using terminal, account, and symbol constraints.

## Rules

- Do not accept final volume directly from the extension.
- Validate symbol trade constraints in MT5.
- Normalize volume to the symbol volume step.
- Enforce minimum and maximum volume.
- Reject commands that cannot be sized safely.
- Keep dry-run handling available for validation without execution.

Phase 1 documents the boundary. Implementation details may evolve in later phase commits.
