# Specification amendments

Specification lock: version 1.0.0, frozen 2026-09-02T00:56:08-03:00 before any post-reform effect estimate.

## Amendment 1 — dynamic event-study trend and uncertainty

- Timestamp: 2026-09-02T01:06:00-03:00
- Stage detected: first identification/collinearity check in Gate D; attempted output was discarded and was not used to select a sign, magnitude, window, control group, or conclusion.
- Affected specification: `registry_event_study` only. The locked short-run PPML summary model is unchanged.
- Prior rule: quarterly age-15 interactions plus the same full set of age-specific linear trends as the parsimonious model; period-cluster pointwise standard errors and temporal simultaneous intervals.
- Technical problem: with one age-15 indicator for every observed quarter except the baseline, the age-15 linear trend is exactly spanned by those indicators. It cannot be jointly identified. Moreover, a coefficient active in a single quarter has only one treated time cluster, so a period-cluster pointwise variance is degenerate and cannot support honest dynamic inference.
- Replacement fixed before re-estimation:
  1. retain the saturated quarterly PPML point estimates, the locked fixed effects, seasonality, and control-age trends; omit the collinear age-15 linear slope because it is absorbed by the event indicators;
  2. label PPML event-study standard errors based on only five regions as diagnostic and do not use them for the main dynamic conclusion;
  3. base dynamic uncertainty on the Brazil age-15-versus-primary-control log-rate gap: fit the locked linear trend and quarter seasonality on 2013T1–2018T4, construct quarterly forecast gaps, and use a moving-block residual bootstrap with block length four, 999 replications, seed 13811;
  4. use the bootstrap distribution of the maximum absolute standardized gap for simultaneous 95% bands; retain the joint lead diagnostics and show raw rates.
- Estimand consequence: none for the treatment contrast or timing. The amendment changes only a nonidentified nuisance slope and replaces an invalid single-period cluster variance with pre-period time-series uncertainty.
- Expected sign/significance consequence recorded before re-estimation: unknown.

## Amendment 2 — dynamic age-15 seasonality

- Timestamp: 2026-09-02T01:09:00-03:00
- Stage detected: Gate-D event-study rank test after Amendment 1; the candidate event-study output failed its acceptance test and was not accepted.
- Affected specification: saturated quarterly Registry PPML event study only. The short-run summary model, raw-rate series, and forecast-bootstrap event study are unchanged.
- Prior amended rule: saturated age-15 quarterly indicators with the locked `age x calendar-quarter` seasonal fixed effects.
- Technical problem: the saturated age-15 quarterly indicators also exactly span the three independent age-15 seasonal contrasts. The estimator therefore removed event times 19–21 as arbitrary columns to resolve a rank deficiency. No observations were separated or dropped; the model used all 940 input cells.
- Replacement fixed before re-estimation: in the saturated PPML event study, keep common seasonality through region × period effects and keep explicit quarter-season interactions for control ages 17 and 18 relative to age 19. Omit separate age-15 seasonal indicators because their variation is absorbed by the full set of age-15 event coefficients. Require all event indicators other than the locked baseline to remain in the fitted model.
- Estimand consequence: none. This chooses a full-rank basis for the same saturated age-15 dynamic path.
- Expected sign/significance consequence recorded before re-estimation: unknown.

## Amendment 3 — PNADC saturated dynamic basis

- Timestamp: 2026-09-02T01:18:00-03:00
- Stage detected: before estimating the PNADC event study, by applying the exact rank result established in Registry Amendments 1–2 to the same age-15-by-quarter basis.
- Affected specification: PNADC full-dynamic event study only. The locked short-run cell model, outcomes, weights, controls, geography, and equivalence margin are unchanged.
- Technical problem: quarterly age-15 indicators spanning all periods except the baseline exactly contain the age-15 linear trend and its three independent seasonal contrasts. Joint inclusion cannot have full column rank. A time-cluster pointwise standard error is also unsupported for a regressor active in a single quarter.
- Replacement fixed before PNADC dynamic estimation:
  1. show saturated quarterly age-15 point estimates using control-age trends and control-age seasonality, with age-15 trend/season absorbed by event coefficients;
  2. base the dynamic uncertainty on a Brazil age-15-minus-primary-controls prevalence gap fitted in 2013T1–2018T4 with trend and seasonality;
  3. combine aligned four-quarter moving-block residual resampling with normal draws from each design-based cell estimate/SE, using 999 replications and seed 13811, and construct simultaneous maximum-statistic bands;
  4. label any cell-regression single-period covariance as diagnostic only.
- Estimand consequence: none; this is a full-rank reparameterization and an honest time-series/design-uncertainty procedure.
- Expected sign/significance consequence recorded before estimation: unknown.

## Amendment 4 — computational implementation of the PNADC survey-LPM robustness

- Timestamp: 2026-09-02T01:54:00-03:00
- Stage detected: first microdata robustness execution; the full `survey::svyglm` call was manually stopped after 30 minutes. It produced no accepted output and modified no raw file.
- Affected specification: only `pnadc_microdata_robustness.estimator_2`. The design-based cell analysis and the dwelling/period-clustered individual LPM are unchanged.
- Prior rule: call `survey::svyglm` directly on every person row using period-prefixed Estrato and UPA.
- Technical problem: direct construction/linearization of the million-row survey GLM did not complete within a proportionate replication time, despite stable memory. Repeating it would violate the locked efficiency requirement without changing the linear estimator.
- Replacement fixed before re-estimation: compute the same weighted Gaussian LPM from exact UPA × design-cell sufficient statistics (`sum(weight)` and `sum(weight*outcome)`), then form the Taylor sandwich by aggregating score contributions at period-prefixed UPA and centering them within period-prefixed Estrato. The bread is the exact weighted cross-product matrix. No row sampling or outcome approximation is permitted. Compare the collapsed point coefficient with the individual weighted LPM and fail if they differ beyond numerical tolerance.
- Variance details: use the with-replacement stratum-centered PSU meat with `n_h/(n_h-1)` finite-cluster correction; report lonely strata and apply the predeclared `adjust` rule if any occur.
- Estimand consequence: none. Linear-regression sufficient statistics preserve the point estimate; only the computational route to the design-linearized covariance changes.
- Expected sign/significance consequence recorded before re-estimation: point estimate must be numerically identical; variance consequence unknown.

Permitted amendments are limited to documented data errors or technical non-identification/impossibility. Each entry must be written here **before** re-estimation and must record the affected specification, prior rule, replacement, evidence, timestamp, and expected estimand consequence. Changes motivated by sign, magnitude, p-value, fit in the post period, or preferred narrative are forbidden.
