# SINASC daily design — Gate G2

**Status: QUALIFIED.**

Generated: 2026-09-04T15:01:08-0300

This artifact implements only the frozen G2 counterfactual diagnostics:
the pre-law temporal placebo, placebo birthdays 15/17/19, annual age-16
jumps, and leave-one-primary-year-out stability. The outcome is recorded
married status among singleton live births with valid SINASC status codes.
It does not estimate the full primary age-16 pre-versus-post coefficient,
DELAY90, a secondary outcome, a sensitivity specification, or any G3 result.

## Decision

| Criterion | Threshold | Observed | Status |
|---|---|---:|---|
| G0_G1_preconditions | unchanged G0_OVERALL=PASS and G1_OVERALL=PASS | PASS | **PASS** |
| temporal_placebo_age16 | PASS if IC90 inside +/-0.25 pp; FAIL if IC95 excludes zero and abs(point)>=0.25 pp | estimate -0.279941 pp; IC90 [-0.724842, 0.164959] | **QUALIFIED** |
| placebo_age_family | PASS if all IC90 inside +/-0.25 pp; FAIL under either frozen Holm rejection clause | 0/3 equivalent; 0 Holm rejections | **QUALIFIED** |
| annual_jump_diagnostics | all 11 required annual age-16 jumps identified; diagnostic only | 11/11 identified | **DIAGNOSTIC_COMPLETE** |
| leave_one_out_diagnostics | all 9 omitted-pre x omitted-post combinations identified; diagnostic only | 9/9 identified | **DIAGNOSTIC_COMPLETE** |
| G2_OVERALL | both binding components pass and required diagnostics identify | QUALIFIED | **QUALIFIED** |

G2 is qualified rather than passed. The counterfactual evidence is inconclusive, and an unconditional causal-core decision is prohibited.

## Binding placebo results

| Test | Age | Estimate pp | IC90% | IC95% | Raw p | Holm p | Equivalent | Family status |
|---|---:|---:|---:|---:|---:|---:|---|---|
| temporal_placebo | 16 | -0.27994 | [-0.72484, 0.16496] | [-0.81016, 0.25027] | 0.300571 | NA | FALSE | **QUALIFIED** |
| age_placebo | 15 | -0.02728 | [-0.45344, 0.39888] | [-0.53514, 0.48059] | 0.916128 |       1 | FALSE | **QUALIFIED** |
| age_placebo | 17 | 0.05369 | [-0.56876, 0.67614] | [-0.68810, 0.79548] | 0.88714 |       1 | FALSE | **QUALIFIED** |
| age_placebo | 19 | -0.06392 | [-0.79872, 0.67088] | [-0.93960, 0.81177] | 0.886196 |       1 | FALSE | **QUALIFIED** |

The equivalence margin is +/-0.25 percentage points. The temporal placebo
uses 2013-2014 as reference and 2016-2018 as pseudo-post. Holm adjustment
covers all three age placebos. PASS requires affirmative equivalence under
prospective amendment A003; lack of rejection alone is not a pass.

## Annual age-16 jump diagnostics

| Year | Period | Jump pp | IC95% | p-value | N | Married events |
|---:|---|---:|---:|---:|---:|---:|
| 2013 | historical_pre | 0.46127 | [-0.16682, 1.08937] | 0.149544 | 33,008 | 759 |
| 2014 | historical_pre | 0.42630 | [-0.21968, 1.07227] | 0.195198 | 32,893 | 616 |
| 2016 | primary_pre | 0.03056 | [-0.48255, 0.54366] | 0.906838 | 28,677 | 369 |
| 2017 | primary_pre | 0.25546 | [-0.33330, 0.84422] | 0.394077 | 26,639 | 310 |
| 2018 | primary_pre | 0.20181 | [-0.35681, 0.76044] | 0.477889 | 25,005 | 266 |
| 2019 | transition | 0.43554 | [-0.10838, 0.97946] |  0.1162 | 22,429 | 224 |
| 2020 | pandemic | 0.07749 | [-0.50414, 0.65911] | 0.793474 | 20,279 | 176 |
| 2021 | pandemic | -0.07817 | [-0.72217, 0.56583] | 0.811479 | 20,156 | 216 |
| 2022 | mature_post | 0.95146 | [0.25341, 1.64951] | 0.00768828 | 16,444 | 144 |
| 2023 | mature_post | 0.11286 | [-0.46796, 0.69367] | 0.702609 | 15,465 | 136 |
| 2024 | mature_post | 0.40374 | [-0.21115, 1.01863] | 0.197452 | 13,908 | 117 |

These are separate within-year right-minus-left jumps. They are displayed to
expose instability and are not post-minus-pre policy-effect estimates.

## Leave-one-year-out diagnostics

| Omitted pre | Omitted post | Estimate pp | IC95% | p-value |
|---:|---:|---:|---:|---:|
| 2016 | 2022 | 0.00353 | [-0.56541, 0.57248] | 0.990282 |
| 2016 | 2023 | 0.47023 | [-0.14014, 1.08060] | 0.130955 |
| 2016 | 2024 | 0.31307 | [-0.29738, 0.92351] | 0.314581 |
| 2017 | 2022 | 0.12508 | [-0.43472, 0.68489] | 0.661235 |
| 2017 | 2023 | 0.59392 | [0.00075, 1.18708] | 0.04971 |
| 2017 | 2024 | 0.43747 | [-0.15288, 1.02782] | 0.14627 |
| 2018 | 2022 | 0.10455 | [-0.45742, 0.66652] | 0.715223 |
| 2018 | 2023 | 0.57120 | [-0.03241, 1.17481] | 0.0636189 |
| 2018 | 2024 | 0.41219 | [-0.19941, 1.02379] | 0.186371 |

All nine combinations omit one primary pre year and one mature-post year.
Their coefficients are mandatory stability diagnostics and cannot override
the binding temporal or age-placebo verdicts.

## Sample and calendar audit

The build streamed 11 annual ZIPs and retained 806,437 cutoff-specific h=90 records.
It excluded 1,312 nonexistent placebo anniversaries; all were explained by February 29 births.
All 12 primary age-16 year-by-side cells reproduced the validated G0 birth and married-event counts.
Married-event cells with 1-9 events are suppressed in the public sample-count
audit. No municipality-by-day cells or person-level derivatives are written.

## Artifacts

- `outputs/audit/SINASC_DAILY_G2_SCHEMA_AUDIT.csv`
- `outputs/audit/SINASC_DAILY_G2_SAMPLE_COUNTS.csv`
- `outputs/audit/SINASC_DAILY_G2_LEAP_EXCLUSIONS.csv`
- `outputs/audit/SINASC_DAILY_G2_MODEL_REGISTRY.csv`
- `outputs/tables/SINASC_DAILY_PLACEBOS.csv`
- `outputs/tables/SINASC_DAILY_G2_ANNUAL_JUMPS.csv`
- `outputs/tables/SINASC_DAILY_G2_LEAVE_ONE_OUT.csv`
- `outputs/audit/SINASC_DAILY_G2_GATE_STATUS.csv`
- `outputs/analysis/SINASC_DAILY_GATE_G2.md`
- `outputs/figures/FIGURE_SINASC_DAILY_G2_ANNUAL_JUMPS.pdf`
- `outputs/figures/FIGURE_SINASC_DAILY_G2_ANNUAL_JUMPS.png`

The classification details follow prospective amendment A003, recorded before
the first G2 coefficient. No G3 model was run.
