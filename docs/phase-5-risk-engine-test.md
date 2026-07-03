# Phase 5 Risk Engine Test

Phase 5 adds risk and volume calculation after Phase 4 market validation succeeds.

No trade is executed in Phase 5. The EA does not import `CTrade`, does not call `OrderSend`, does not open positions, and does not place pending orders. It only calculates risk and volume and writes the result to the local response file.

The extension must not send final volume. The EA calculates final volume inside MT5 from account equity, command `risk_percent`, the current market reference price, command `stop_loss`, and broker symbol volume constraints.

## Inputs

- `MaxRiskPercent`: default `2.0`. Commands with `risk_percent` above this value are rejected with `RISK_PERCENT_TOO_HIGH`.
- `MaxVolume`: default `0.0`. A value of `0.0` applies no custom cap. A value greater than `0.0` caps the calculated volume down to the largest valid step not exceeding `MaxVolume`.

Existing inputs remain available:

- `PollingIntervalMs`
- `EnableDebugLogs`
- `ProductName`
- `MagicNumber`
- `EnforceCommandTtl`
- `MaxCommandTtlMs`
- `ProcessedCommandCacheSize`
- `RejectIfSpreadAbovePoints`
- `AllowedSymbols`

## Risk Calculation

The EA reads account equity with `AccountInfoDouble(ACCOUNT_EQUITY)`.

The risk amount is:

```text
risk_amount = equity * risk_percent / 100.0
```

The entry reference price is always the live Phase 4 market reference:

- Buy: current Ask
- Sell: current Bid

The command entry price is not used. Phase 5 only prepares market-order risk calculation.

The EA uses `OrderCalcProfit` for a hypothetical 1.0 lot position closed at `stop_loss`. This lets MT5 account for symbol-specific tick value, contract size, profit currency, and broker settings. If MT5 cannot calculate the loss, Phase 5 rejects the command instead of using an unreliable fallback formula.

Raw volume is:

```text
raw_volume = risk_amount / loss_per_lot
```

The EA then rounds volume down to the nearest `SYMBOL_VOLUME_STEP`. It never rounds up because increasing volume could exceed the requested risk.

If the rounded-down volume is below `SYMBOL_VOLUME_MIN`, the EA rejects with `RISK_TOO_SMALL_FOR_MIN_VOLUME`. It does not automatically raise the volume to the minimum because that could risk more than the user requested.

If the rounded volume exceeds `SYMBOL_VOLUME_MAX`, it is capped down to the largest valid step not exceeding the broker maximum. If `MaxVolume` is greater than `0.0`, the same down-only cap is applied to `MaxVolume`.

After final volume is determined, the EA calls `OrderCalcProfit` again with the normalized volume to estimate the stop-loss result. If `estimated_loss` is greater than `risk_amount` beyond a tiny floating-point tolerance, the command is rejected with `ESTIMATED_LOSS_EXCEEDS_RISK`.

## Accepted Response

Accepted Phase 5 responses use:

```json
{
  "status": "accepted",
  "code": "RISK_CALCULATED",
  "ea_phase": "phase-5-risk-engine",
  "message": "Command passed validation and risk calculation. No trade was executed in Phase 5."
}
```

Accepted responses continue to include the standard response fields and available Phase 4 market context fields.

Risk fields are included as available:

- `equity`
- `risk_percent`
- `max_risk_percent`
- `risk_amount`
- `calculation_method`: `OrderCalcProfit`
- `loss_per_lot`
- `raw_volume`
- `volume`
- `estimated_loss`
- `estimated_profit_at_sl`
- `volume_min`
- `volume_max`
- `volume_step`
- `max_volume`
- `volume_normalized_down`

No final order, deal, position, or ticket fields are included in Phase 5 responses.

## Error Codes

Phase 5 keeps earlier protocol and market-validation error codes and adds:

- `RISK_CALCULATED`
- `EQUITY_UNAVAILABLE`
- `RISK_PERCENT_TOO_HIGH`
- `ORDER_CALC_PROFIT_FAILED`
- `STOP_LOSS_LOSS_NOT_POSITIVE`
- `INVALID_CALCULATED_VOLUME`
- `SYMBOL_VOLUME_CONSTRAINTS_UNAVAILABLE`
- `RISK_TOO_SMALL_FOR_MIN_VOLUME`
- `ESTIMATED_LOSS_EXCEEDS_RISK`

`INVALID_RISK_PERCENT` remains the rejection code for missing, non-numeric, or non-positive `risk_percent`.

## Manual Test Setup

1. Open `mt5/Experts/MTChartBridge/MTChartBridgeEA.mq5` in MetaEditor.
2. Compile and confirm 0 errors.
3. Attach the EA to a chart in MT5.
4. Confirm `Terminal/Common/Files/MTChartBridge/status.json` is updating and reports `ea_phase` as `phase-5-risk-engine`.
5. For each test, write a command payload to `Terminal/Common/Files/MTChartBridge/inbox/<id>.command.json.tmp`.
6. Create the ready marker `Terminal/Common/Files/MTChartBridge/inbox/<id>.command.ready`.
7. Read `Terminal/Common/Files/MTChartBridge/outbox/<id>.response.json.tmp`.
8. Confirm accepted command files move to `processed/` and rejected command files move to `failed/`.

Use fresh command ids for each test because duplicate ids are rejected within the EA session.

## Manual Test Cases

A. Valid buy risk calculation:

- Use a valid `buy` command.
- Set `risk_percent` to `1.0`.
- Set `stop_loss` below current Ask and `take_profit` above current Ask.
- Expected `status`: `accepted`
- Expected `code`: `RISK_CALCULATED`
- Response must include `volume` and `estimated_loss`.
- MT5 must not open a trade.

B. Valid sell risk calculation:

- Use a valid `sell` command.
- Set `risk_percent` to `1.0`.
- Set `stop_loss` above current Bid and `take_profit` below current Bid.
- Expected `status`: `accepted`
- Expected `code`: `RISK_CALCULATED`
- Response must include `volume` and `estimated_loss`.
- MT5 must not open a trade.

C. Risk percent too high:

- Set `MaxRiskPercent = 2.0`.
- Send `risk_percent = 5.0`.
- Expected `status`: `rejected`
- Expected `code`: `RISK_PERCENT_TOO_HIGH`

D. Risk too small for min volume:

- Send a very tiny `risk_percent`, such as `0.0001`.
- Expected `code`: `RISK_TOO_SMALL_FOR_MIN_VOLUME` if the rounded-down volume is below the broker minimum.
- If the broker symbol constraints make this hard to trigger, document the observed `volume_min`, `volume_step`, `risk_amount`, and response code.

E. MaxVolume cap:

- Set `MaxVolume` to a low value that is still greater than or equal to `SYMBOL_VOLUME_MIN`.
- Send a command that would normally calculate a larger volume.
- Expected `status`: `accepted`
- Expected `code`: `RISK_CALCULATED`
- Expected `volume` to be less than or equal to `MaxVolume`.
- Expected `estimated_loss` to be less than or equal to `risk_amount`.

F. Ensure no trade execution:

- Confirm the MT5 Trade tab remains unchanged.
- Confirm the response has no order, deal, position, or ticket fields.
- Confirm Experts logs say no trade was executed.
- Confirm the source contains no `CTrade` import and no `OrderSend` call.
