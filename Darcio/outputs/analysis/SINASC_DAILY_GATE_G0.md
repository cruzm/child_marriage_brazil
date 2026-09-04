# SINASC daily design — Gate G0

**Status: PASS.**

Generated: 2026-09-04T14:05:24-0300

This artifact implements only the frozen data gate. It contains no regression,
discontinuity estimate, density test, continuity test, placebo, coefficient,
standard error, p-value, confidence interval, or causal-effect estimate.

## Decision

| Criterion | Threshold | Observed | Worst cell | Status |
|---|---:|---:|---|---|
| official_annual_total_reconciliation | 6/6 exact; unavailable anchor implies QUALIFIED | 6/6 exact | none | **PASS** |
| exact_date_valid_share_each_primary_year | >= 0.980 | minimum 0.988593 | 2016 | **PASS** |
| completed_age_agreement_among_valid_dates | >= 0.990 | minimum 0.999761 | 2017 | **PASS** |
| valid_status_share_each_era_side | >= 0.950 | minimum 0.986355 | pre:below | **PASS** |
| births_each_era_side_at_h90 | >= 10000 | minimum 21420 | post:below | **PASS** |
| married_events_each_era_side_at_h90 | >= 100 | minimum 125 | post:below | **PASS** |
| G0_OVERALL | all mandatory criteria pass; missing independent anchor yields QUALIFIED | PASS | not_applicable | **PASS** |

## Annual reconciliation and date integrity

| Year | Era | Raw rows | Official anchor | Difference | Exact match | Exact-date valid | Age agrees |
|---:|---|---:|---:|---:|---|---:|---:|
| 2016 | pre | 2,857,800 | 2,857,800 | 0 | yes | 98.859% | 99.982% |
| 2017 | pre | 2,923,535 | 2,923,535 | 0 | yes | 98.914% | 99.976% |
| 2018 | pre | 2,944,932 | 2,944,932 | 0 | yes | 98.991% | 99.982% |
| 2022 | post | 2,561,922 | 2,561,922 | 0 | yes | 98.908% | 99.993% |
| 2023 | post | 2,537,576 | 2,537,576 | 0 | yes | 99.099% | 99.991% |
| 2024 | post | 2,389,325 | 2,389,325 | 0 | yes | 99.117% | 99.988% |

Every designated annual gate anchor is independent of the cached archive and
corresponds to a comparable final/current extraction. Conflicting preliminary
vintages are preserved in `SINASC_DAILY_G0_ANCHOR_RECONCILIATION.csv` and are
not silently substituted for the designated anchor. Monthly raw profiles are
exported without outcome fields; no independent monthly anchor was designated.

## Frozen h=90 feasibility cells

| Era | Side | Valid-status share | Births | Married events |
|---|---|---:|---:|---:|
| post | above | 99.006% | 24,397 | 272 |
| post | below | 99.116% | 21,420 | 125 |
| pre | above | 98.914% | 43,093 | 633 |
| pre | below | 98.636% | 37,228 | 312 |

These are mandated event counts, not outcome rates or contrasts. The script does
not subtract, divide, model, or compare married-event counts across cutoff sides.

## Operational definitions

The filter order and denominators follow prospective amendment A001, recorded
before this first G0 run. Dates must be strict eight-digit `ddmmyyyy`; age is
constructed calendar-wise; and `x=0` is assigned above the cutoff. Band audits
retain positive triangular-kernel support (`abs(x)<h`). Cells containing 1--9
outcome events are suppressed from public outputs.

## Artifacts

- `outputs/audit/SINASC_DAILY_GATE_STATUS.csv`
- `outputs/audit/SINASC_DAILY_G0_ANNUAL.csv`
- `outputs/audit/SINASC_DAILY_G0_MONTHLY_PROFILE.csv`
- `outputs/audit/SINASC_DAILY_G0_DATE_QUALITY_BY_STATUS.csv`
- `outputs/audit/SINASC_DAILY_G0_SIDE_QUALITY.csv`
- `outputs/audit/SINASC_DAILY_G0_ERA_SIDE_QUALITY.csv`
- `outputs/audit/SINASC_DAILY_G0_BAND_COUNTS.csv`
- `outputs/audit/SINASC_DAILY_G0_ANCHOR_RECONCILIATION.csv`
- `outputs/logs/27_sinasc_daily_gate_g0.log`

No later gate was run. Under the frozen protocol, a `FAIL` stops all outcome
estimation; a `QUALIFIED` status prohibits an unconditional causal-core decision.
