# Identification Gate — trend sensitivity for Paper 1

**Date:** 2026-09-02  
**Decision:** do not report a standard `HonestDiD` result from the current regional
event study.

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

## Next admissible extension

If the project adds trend sensitivity, freeze a **post-result sensitivity protocol**
before computing any new estimates. It cannot be described as ex ante because the main
results are already known. The extension should:

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

If no candidate has acceptable pre-period forecast and placebo performance, Gate 2
remains open. The paper should then be positioned as a transparent measurement and
design-failure paper, not as a causal estimate of the reform.

## Higher-return data alternative

Exact event and birth dates, residence-compatible civil-registration microdata, or
administrative records of requests and refusals below age 16 would improve the design
more than another transformation of the same 27-quarter comparison. Availability is not
verified.
