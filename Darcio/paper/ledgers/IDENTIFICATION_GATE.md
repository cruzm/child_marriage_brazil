# Identification Gate — trend sensitivity for Paper 1

**Date:** 2026-09-04
**Decision:** do not report a standard `HonestDiD` result from the current regional
event study. The frozen post-result rolling-origin extension was executed and its
calibration gate **failed**: no candidate counterfactual is validated.

## Question

Can Rambachan--Roth sensitivity intervals convert the Registry trend dependence into a
credible causal sensitivity analysis?

## Audit result

The package requires an ordered vector of event-study coefficients and its covariance
matrix. The repository has event-study points, but none of the available covariance
constructions is adequate for a primary `HonestDiD` result:

1. **Regional PPML covariance.** The dynamic PPML uses five regions. `fixest` warns that
   the region-cluster covariance is not positive semidefinite and repairs it numerically.
   In a read-only probe, the covariance rank remained four whether the vector contained
   7, 11, 15, or 26 event coefficients. Feeding that matrix to `HonestDiD` would turn a
   diagnostic with five clusters into formal-looking inference.
2. **Period clustering.** Treatment occurs once nationally and each saturated dynamic
   coefficient is active in one period. Period-cluster uncertainty for those individual
   coefficients is degenerate. This problem is already documented in Specification
   Amendment 1.
3. **National time-series bootstrap.** The moving-block forecast bootstrap respects the
   national timing better, but its exported objects are forecast deviations rather than
   a conventional normalized event-study coefficient vector, and the full covariance
   matrix is not retained. Supplying a reconstructed bootstrap covariance to
   `HonestDiD` would be a methodological adaptation, not an off-the-shelf application.

The package being installed is not enough. The inferential object must be credible.

## Binding interpretation

- Do not add an `HonestDiD` figure or breakdown value to the manuscript from the five-
  region event study.
- Do not describe the current `[-23.9%, +29.3%]` SINASC range as an honest bound; it is
  a range across two specifications.
- The locked Registry interval remains conditional on age-specific linear trends.
- The no-trend estimate, placebo in 2015Q2, pre-window sensitivity, and MDE must remain
  in the main paper.
- Do not claim that the Registry design rules out a Mexico-sized decline. That decline
  lies outside the locked-model interval but inside the seasonal-level model's 95%
  forecast interval, and all five models fail the common calibration gate.
- The all-model point range `[-33.7%, +12.8%]` is a **specification envelope** only. It
  is not a confidence set, identified set, causal bound, or replacement for the
  model-specific intervals.

## Executed admissible extension

The project froze a **post-result sensitivity protocol** before computing any of the
extension estimates. It is not described as ex ante because the main Registry results
were already known. The protocol and implementation:

1. use the national age-15 minus pooled-age-17--19 log-rate gap;
2. select or weight counterfactual trend models using pre-2019 rolling-origin forecasts
   only, with a three-quarter horizon matching 2019Q2--Q4;
3. fix a small candidate set before estimation (seasonal level, global linear trend,
   quadratic trend, and local linear trends using 12 and 16 pre-quarters);
4. report every candidate, pre-period forecast loss, all feasible three-quarter placebo
   windows, and the post estimate;
5. use a four-quarter moving-block bootstrap for model-specific forecast uncertainty;
6. label the cross-model envelope a **specification envelope**, not a confidence set;
7. retain the locked PPML estimate as primary regardless of the extension's result.

All seven requirements were implemented. The locked protocol hashes are:

- YAML: `04cdab04f79981b2d101d18d85dec6083938d8009acc1f9862d09c65aa6beb46`;
- prose: `268192691f7cd90f4165f059d814d2cfdfaea8b095d9c71e5ea28907f0812881`.

The global-linear model ranks first (rolling RMSE `0.131`) and gives `+2.0%`, with a
model-specific forecast interval `[-17.6%, +23.4%]`. The inverse-RMSE-squared ensemble
gives `+3.0%`. The seasonal-level model ranks last (RMSE `0.391`) and gives `-33.7%`,
with interval `[-54.7%, -0.3%]`. Every model is classified `fail`; the best model misses
the qualified tier because its worst rolling error is `0.233`, above `log(1.25) = 0.223`.
All 13 implementation acceptance tests pass.

## Gate outcome

Because no candidate has acceptable pre-period forecast and placebo performance, the
identification gate remains open. The paper is positioned as a transparent measurement,
model-dependence, and design-failure paper, not as a design-wide causal estimate of the
reform. A better functional form chosen from the same 24 pre-quarters is not enough to
close this gate.

## Exact-age SINASC identification gate

The post-result daily protocol was frozen on 4 September 2026 after the Registry,
PNADC, and grouped-age SINASC results were known, but before any outcome contrast by
daily distance from an age cutoff was computed. It uses only observed official SINASC
records. The primary estimand is the 2022--2024 minus 2016--2018 change in the
right-minus-left discontinuity in recorded married status at the mother's sixteenth
birthday, among singleton live births within 90 days.

- **G0 PASS:** all six primary annual files reconcile exactly to independent official
  totals; exact-date, age-agreement, status-validity, observation-count, and married-
  event thresholds pass.
- **G1 PASS:** no frozen density, predetermined-composition, or status-missingness hard
  failure occurs. Thirty-day equal-side counts trigger the heaping diagnostic, so the
  frozen donut estimates remain visible.
- **G2 QUALIFIED:** the pre-law temporal placebo is `-0.280` p.p. with 90% interval
  `[-0.725,+0.165]`; placebo ages 15, 17, and 19 do not reject after Holm adjustment,
  but none affirmatively establishes equivalence within `+/-0.25` p.p.
- **G3 INCONCLUSIVE:** the primary estimate is `+0.342` p.p. (SE `0.246`; 95% CI
  `[-0.140,+0.824]`; `p=0.164`) with MDE80 `0.688` p.p. The delay-sensitive estimate
  is `+0.323` p.p. (95% CI `[-0.318,+0.964]`; Holm `p=0.328`). All 13 frozen
  sensitivity estimates are positive (`+0.148` to `+0.356` p.p.) but cannot override
  the primary classification or qualified counterfactual gate.

The binding decision is `DO_NOT_ADVANCE_AS_CAUSAL_CORE`. Exact birthdays improve the
running variable and local comparison, but status is measured at childbirth rather than
marriage, the sample conditions on a live birth, and the design still requires the
non-law age-16 discontinuity to remain stable across eras. The paper may report the
positive local signal only together with its interval, power, placebos, result chronology,
and mechanical gate verdict.

## Higher-return data alternative

Exact event and birth dates and residence-compatible civil-registration microdata would
improve the design more than another transformation of the same 27-quarter comparison.
The official IBGE `RC.2` questionnaire collects all three objects, and an official
confidentiality manual identifies the Sala de Acesso a Dados Restritos (SAR) as the route
for external researchers to use non-public Civil Registry microdata. Retention and
year-by-year completeness of the required fields still require confirmation from IBGE.

A second route is administrative records of requests and decisions below age 16. A
nationwide public-DataJud probe found TPU class 143, but it is not estimation-ready:
94.1% of 3,574 public records had filing dates after the 2026-09-02 snapshot, only three
courts had a plausible 2019 record, the class combines age and parental consent, and the
public API excludes secret cases. Because full DataJud receives public and secret cases,
a secrecy-inclusive aggregate request to the CNJ remains a useful mechanism extension,
not a substitute for the restricted Registry redesign. See
`ADMINISTRATIVE_DATA_FEASIBILITY_2026-09-02.md`.

## Registry/SAR R0 local-readiness result

The exact-date route completed its local R0 on 4 September 2026. Its bounded
status is `LOCAL_READY_EXTERNAL_PENDING`; causal identification remains
`NOT_EVALUATED`. The R0 does not alter the open identification verdict above, and its
software-test data and recovery coefficient are excluded from every manuscript claim,
table, and figure.

The local package contributes four planning facts:

1. public registration-age counts imply a base 80%-power decline MDE of 19.09%
   at 90 days and a stress MDE of 25.88% at 180 days; both are provisional
   because the source records age and year at registration, not exact age and
   date at celebration;
2. the selected national quarterly PNADC denominator contains all 288 cells for
   ages 15/16 and combined/female/male populations; all 18 frozen precision and
   annual-comparison criteria pass;
3. a synthetic PPML dry run recovers a known IRR of 0.60 within 0.020 log point
   and marks every row as synthetic; this verifies code, not a policy effect;
4. the technical inquiry and attachment set are ready but explicitly unsent.

IBGE confirmation of annual field retention, SEADE coverage, edit/imputation
flags, import/export rules, and an internal deduplication key remains binding.
Inside the SAR, exact-date validity, residence coverage, reconciliation,
exact-window power, counterfactual placebos, and inference must pass before the
paper can use the redesign as a causal core. The protocol and results are in
`REGISTRY_SAR_R0_PROTOCOL.md` and
`outputs/analysis/REGISTRY_SAR_R0_RESULTS.md`.
