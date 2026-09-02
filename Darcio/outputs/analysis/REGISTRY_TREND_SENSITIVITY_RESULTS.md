# Registry trend sensitivity — results

**Run:** 2026-09-02T13:47:45-0300  
**Protocol:** frozen post-result protocol v1.0.0; original specification lock unchanged.  
**Gate:** `failed`.

## Main result

The frozen selection rule chooses `global_linear` (fail). Its 2019Q2--Q4 forecast deviation is +2.0% (95% model-specific forecast interval [-17.6%, +23.4%], p=0.853).
The fixed pre-period-weighted ensemble gives +3.0%. The all-model point envelope is [-33.7%, +12.8%]. No candidate passes the qualified calibration tier, so no calibrated-model envelope is reported.

This is a specification envelope, not a confidence set, identified set, or causal bound. Rolling-origin performance can expose poor extrapolation; it cannot prove the untreated 2019 path.

## Candidate models

- `global_linear`: pre-window RMSE 0.131; tier **fail**; target +2.0% (95% forecast interval [-17.6%, +23.4%], p=0.853); ensemble weight 0.358.
- `local_linear_12`: pre-window RMSE 0.156; tier **fail**; target +1.1% (95% forecast interval [-14.4%, +18.8%], p=0.888); ensemble weight 0.251.
- `local_linear_16`: pre-window RMSE 0.157; tier **fail**; target +10.1% (95% forecast interval [-10.8%, +37.0%], p=0.420); ensemble weight 0.247.
- `global_quadratic`: pre-window RMSE 0.243; tier **fail**; target +12.8% (95% forecast interval [-13.6%, +48.3%], p=0.409); ensemble weight 0.104.
- `seasonal_level`: pre-window RMSE 0.391; tier **fail**; target -33.7% (95% forecast interval [-54.7%, -0.3%], p=0.036); ensemble weight 0.040.

## Binding interpretation

- The locked regional PPML remains the primary estimate.
- The extension was designed after the original outcomes and diagnostics were known.
- Model selection and ensemble weights use only pre-2019 rolling forecasts.
- Every candidate and every common placebo window is retained in the exported CSVs.
- Model-specific bootstrap intervals describe forecast uncertainty under each functional form; they do not solve the single-national-event identification problem.

