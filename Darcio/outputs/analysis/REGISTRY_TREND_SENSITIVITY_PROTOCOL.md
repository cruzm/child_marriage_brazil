# Registry trend sensitivity — frozen post-result protocol v1.0.0

**Frozen:** 2026-09-02T13:38:30-03:00, before running this extension.  
**Status:** explicitly post-result. The locked Registry estimates, diagnostics, existing
linear-seasonal forecast, and SINASC results were already known. This protocol does not
modify the original specification lock and cannot be described as ex ante.

## Question and estimand

The exercise asks whether counterfactual trend models selected using only pre-2019
rolling-origin forecasts give a similar short-run Registry conclusion. The outcome is
the national log rate at age 15 minus the log pooled rate at ages 17--19. The target is
the mean actual-minus-forecast gap in 2019Q2--Q4. The pre-period is 2013Q1--2018Q4;
2019Q1 remains omitted.

The extension reports forecast deviations. It does not prove parallel trends. Any range
across models is a **specification envelope**, not a confidence set, identified set, or
honest bound. The locked regional PPML remains primary.

## Frozen models

Every model includes calendar-quarter seasonality. The five candidates are:

1. seasonal level, fit on all available training observations;
2. global linear trend, fit on all available training observations;
3. global quadratic trend, fit on all available training observations;
4. local linear trend, fit on the last 12 quarters;
5. local linear trend, fit on the last 16 quarters.

The period index is absolute and starts at one in 2013Q1. No model is added, removed, or
altered after seeing the extension estimates.

## Rolling-origin comparison

The forecast horizon matches the target: three quarters. A common 16-quarter warm-up
allows all five models to be compared on the six common windows beginning in 2017Q1,
2017Q2, 2017Q3, 2017Q4, 2018Q1, and 2018Q2. Each model is fit only through the quarter
before the window and is not updated inside it.

Models are ranked by the root mean squared value of the six window-mean forecast errors.
Ties are broken alphabetically. A fixed-weight ensemble uses inverse squared RMSE weights
estimated only from these pre-2019 errors.

## Calibration rule fixed before estimation

A model is **strong** if the absolute mean error is at most `log(1.05)` and all six
window errors are within `+/-log(1.15)`. It is **qualified** if the absolute mean error is
at most `log(1.10)`, at least five of six windows are within `+/-log(1.20)`, and none is
outside `+/-log(1.25)`. Otherwise it fails.

The gate is strong if at least one model is strong; qualified-with-reservations if none
is strong but at least one is qualified; and failed otherwise. Within the best available
tier, the lowest-RMSE model is selected. If all candidates fail, the lowest-RMSE model is
shown only as a failed diagnostic.

These thresholds are transparent policy-scale criteria, not data-free primitives. They
were chosen after the original results and pre-period path were visible, which is why the
exercise remains post-result even though each rolling forecast is out of sample within
the pre-period.

## Uncertainty and reporting

For each model, 1,999 circular moving-block bootstrap draws resample centered pre-period
residuals in blocks of four quarters, refit the model, and reconstruct the target forecast
error. Seed: 13811. Model-specific intervals invert the bootstrap forecast-error
distribution. The weighted ensemble receives only a point estimate because a defensible
cross-model covariance procedure was not frozen.

The output reports every candidate, all six placebo windows, the fixed-weight ensemble,
the all-model envelope, and—if any model qualifies—the calibrated-model envelope. None
may be called a causal bound.

The machine-readable lock is `config/registry_trend_sensitivity_lock.yml`. Its SHA-256
and this document's SHA-256 are recorded separately before the extension runs.

