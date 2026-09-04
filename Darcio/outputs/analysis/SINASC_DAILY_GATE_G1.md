# SINASC daily design — Gate G1

**Status: PASS.**

Generated: 2026-09-04T14:30:01-0300

This artifact implements only density/heaping, predetermined-covariate
continuity, non-hard composition, and status-missingness diagnostics. It does
not construct or estimate the married-status outcome, a policy effect, G2
placebos, or any G3 estimand.

## Decision

| Criterion | Threshold | Observed | Status |
|---|---|---:|---|
| G0_precondition | G0_OVERALL=PASS and output hashes unchanged | PASS | **PASS** |
| density_by_primary_era | hard fail if robust p<0.05 AND abs(log density ratio)>abs(log(1.05)) | 2 identified; 0 hard failures | **PASS** |
| predetermined_covariate_continuity | hard fail if Holm p<0.05 AND abs standardized magnitude>=0.10 | 10/10 identified; 0 hard failures | **PASS** |
| status_missingness_continuity | hard fail if p<0.05 AND abs coefficient>=0.50 pp | coefficient 0.261611 pp; p=0.31653 | **PASS** |
| composition_family | diagnostic only; Holm within 14 prespecified indicators | 14/14 identified; 0 Holm p<0.05 | **DIAGNOSTIC_ONLY** |
| G1_OVERALL | no hard failure and no required non-identification | PASS | **PASS** |

## Density test

| Era | Robust p-value | Right/left density ratio | Log ratio | Rejects 5% | Exceeds 5% | Hard failure |
|---|---:|---:|---:|---|---|---|
| pre | 0.848064 | 0.99443 | -0.00558 | FALSE | FALSE | FALSE |
| post | 0.394593 | 0.96293 | -0.03777 | FALSE | FALSE | FALSE |

The frozen magnitude threshold is `abs(log(1.05)) = 0.048790`. A hard
failure requires both robust p<0.05 and a larger absolute log ratio in either
era. Exact equal-day counts below are diagnostics and cannot reverse that rule.

## Equal-day count diagnostics

| Era | Days per side | Below | Above | Above/below | Exact binomial p |
|---|---:|---:|---:|---:|---:|
| pre | 7 | 3,161 | 3,244 | 1.02626 | 0.305552 |
| pre | 14 | 6,336 | 6,547 | 1.03330 | 0.064285 |
| pre | 30 | 13,297 | 14,127 | 1.06242 | 0.000001 |
| post | 7 | 1,887 | 1,861 | 0.98622 | 0.683017 |
| post | 14 | 3,640 | 3,746 | 1.02912 | 0.221797 |
| post | 30 | 7,557 | 8,027 | 1.06219 | 0.000172 |

## Hard predetermined continuity family

| Covariate | Above x post (pp) | Holm p | Abs. standardized | Hard failure |
|---|---:|---:|---:|---|
| race_white | 0.46503 | 1.000000 | 0.01147 | FALSE |
| race_black | 0.56731 | 1.000000 | 0.02524 | FALSE |
| race_yellow | -0.11215 | 1.000000 | 0.02026 | FALSE |
| race_brown | -1.28241 | 1.000000 | 0.02771 | FALSE |
| race_indigenous | 0.39077 | 1.000000 | 0.02568 | FALSE |
| birthplace_north | 0.40377 | 1.000000 | 0.01041 | FALSE |
| birthplace_northeast | -1.25043 | 1.000000 | 0.02578 | FALSE |
| birthplace_southeast | 1.59384 | 1.000000 | 0.03588 | FALSE |
| birthplace_south | -0.22921 | 1.000000 | 0.00792 | FALSE |
| birthplace_center_west | -0.52965 | 1.000000 | 0.02085 | FALSE |

Holm adjustment covers all ten valid race/color and maternal-birthplace-region
indicators. A hard failure requires both adjusted p<0.05 and absolute
standardized magnitude at least 0.10. Unknown-category tests and all 14
schooling, primiparity, and residence indicators remain diagnostic only in the
full continuity CSV.

## Status missingness

The post-minus-pre change in the age-16 missing-status discontinuity is 0.261611 pp (p=0.316530).
Hard-failure threshold: p<0.05 and absolute magnitude at least 0.50 pp. Result: `FALSE`.

## Artifacts

- `outputs/audit/SINASC_DAILY_G1_SCHEMA_AUDIT.csv`
- `outputs/audit/SINASC_DAILY_G1_SAMPLE_RECONCILIATION.csv`
- `outputs/audit/SINASC_DAILY_G1_DAILY_COUNTS.csv`
- `outputs/audit/SINASC_DAILY_G1_WEEKLY_COUNTS.csv`
- `outputs/audit/SINASC_DAILY_G1_EQUAL_DAY_COUNTS.csv`
- `outputs/audit/SINASC_DAILY_G1_DENSITY.csv`
- `outputs/audit/SINASC_DAILY_G1_DENSITY_BINOMIAL.csv`
- `outputs/audit/SINASC_DAILY_G1_CONTINUITY.csv`
- `outputs/audit/SINASC_DAILY_G1_STATUS_MISSINGNESS.csv`
- `outputs/audit/SINASC_DAILY_G1_GATE_STATUS.csv`
- `outputs/analysis/SINASC_DAILY_GATE_G1.md`
- `outputs/figures/FIGURE_SINASC_DAILY_G1_DENSITY.pdf`
- `outputs/figures/FIGURE_SINASC_DAILY_G1_DENSITY.png`

The filter order and estimator details follow prospective amendment A002,
recorded before the first G1 statistic. G2 and G3 were not run. A G1 hard
failure restricts this design to descriptive use under the frozen protocol.
