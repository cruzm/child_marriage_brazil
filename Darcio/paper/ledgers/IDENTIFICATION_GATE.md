# Identification Gate — trend sensitivity for Paper 1

**Date:** 2026-09-02  
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
