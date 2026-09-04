# SINASC daily age-16 design — Gate G3 results

**G3 classification: `INCONCLUSIVE`.**
**Paper-path decision: `DO_NOT_ADVANCE_AS_CAUSAL_CORE`.**

Generated: 2026-09-04T15:31:09-0300

The frozen data do not distinguish zero from policy-relevant local changes.
The primary post-minus-pre change in the age-16 married-status jump is 0.34196 percentage points (SE 0.24573; 95% CI [-0.13992, 0.82384]; p=0.164179).
Its MDE80 is 0.68803 pp. The estimate equals 37.60% of the triangular-weighted pre-law below-cutoff married share (0.90946%).

G2 remains `QUALIFIED`. Therefore this post-result daily design does not meet the frozen conditions for an unconditional causal core.
The estimates remain local to mothers of singleton live births near age 16 and measure recorded conjugal status at childbirth, not marriage incidence.

## Primary and delay-sensitive estimands

| Estimand | Estimate pp | SE | 90% CI | 95% CI | Raw p | Holm p | Holm interval |
|---|---:|---:|---:|---:|---:|---:|---:|
| TAU | 0.34196 | 0.24573 | [-0.06240, 0.74631] | [-0.13992, 0.82384] | 0.164179 | 0.328358 | [-0.20919, 0.89311] |
| DELAY90 | 0.32308 | 0.32688 | [-0.21481, 0.86098] | [-0.31794, 0.96411] | 0.323072 | 0.328358 | [-0.31794, 0.96411] |

The slope-kink change phi is -0.0004194 pp per day. The joint Wald test of TAU=phi=0 gives F(2,126115)=0.96937 (p=0.379325).
DELAY90 equals TAU + 45*phi. Holm adjustment applies only to the auxiliary immediate-or-delayed family; the single primary TAU keeps its unadjusted inference.

## Secondary outcomes

| Outcome | Estimate pp | 95% CI | Raw p | Holm p |
|---|---:|---:|---:|---:|
| UNIAO_ESTAVEL | -0.62758 | [-2.57821, 1.32305] | 0.528152 |       1 |
| ANY_UNION | -0.28562 | [-2.25121, 1.67996] |  0.7757 |       1 |

Holm adjustment covers exactly UNIAO_ESTAVEL and ANY_UNION. These recorded labels do not establish behavioral substitution and do not alter the G3 class.

## Frozen sensitivity set

All 13 stacked specifications identify. Their estimates range from 0.14792 to 0.35559 pp; the complete table and coefficient plot retain bandwidth, covariance, precision, functional-form, donut, and sample checks.
G1 heaping trigger: `TRUE`; donut estimates are displayed and cannot rescue a gate.

## rdrobust 3.0.0 cross-check at h=90, b=180

| Era/comparison | Bias-corrected jump pp | Robust 95% CI | Robust p |
|---|---:|---:|---:|
| pre | 0.18443 | [-0.17082, 0.53969] | 0.308902 |
| post | 0.50951 | [0.09777, 0.92126] | 0.0152927 |
| post minus pre | 0.32508 | no separate-fit inference | NA |

The pre and post fits use disjoint era samples. Their subtraction is a point comparison only; the stacked model supplies inference for TAU because separate rdrobust fits do not retain cross-era municipal covariance.

## Audit and interpretation

The script streamed six annual ZIPs and retained 126,138 primary h=90 observations.
All 48 year-by-bandwidth-by-side primary cells reproduce G0. No person-level derivative or municipality-by-day cell is written. Weekly figure bins with 1-9 married events are suppressed.
The protocol was frozen after earlier paper results but before any daily age-distance outcome contrast. A004 fixed implementation details before this first G3 run.

## Artifacts

- `outputs/audit/SINASC_DAILY_G3_SCHEMA_AUDIT.csv`
- `outputs/audit/SINASC_DAILY_G3_SAMPLE_RECONCILIATION.csv`
- `outputs/audit/SINASC_DAILY_G3_SAMPLE_AUDIT.csv`
- `outputs/audit/SINASC_DAILY_G3_SOFTWARE.csv`
- `outputs/audit/SINASC_DAILY_G3_MODEL_REGISTRY.csv`
- `outputs/audit/SINASC_DAILY_G3_GATE_STATUS.csv`
- `outputs/tables/SINASC_DAILY_PRIMARY.csv`
- `outputs/tables/SINASC_DAILY_SECONDARY.csv`
- `outputs/tables/SINASC_DAILY_SENSITIVITY.csv`
- `outputs/tables/SINASC_DAILY_RDROBUST.csv`
- `outputs/analysis/SINASC_DAILY_RESULTS.md`
- `outputs/figures/FIGURE_14_SINASC_DAILY_RD.pdf`
- `outputs/figures/FIGURE_14_SINASC_DAILY_RD.png`
- `outputs/figures/FIGURE_SINASC_DAILY_G3_SENSITIVITY.pdf`
- `outputs/figures/FIGURE_SINASC_DAILY_G3_SENSITIVITY.png`
