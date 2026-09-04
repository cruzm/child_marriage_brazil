# SINASC daily protocol amendments

**Protocol:** `config/sinasc_daily_lock.yml`, version 1.0.0  
**Frozen:** 2026-09-04T13:38:08-03:00  
**Current status:** four prospective implementation clarifications; each was
recorded before the affected result was computed

This ledger records only data errors, unavailable frozen fields, software
non-identification, or implementation ambiguities discovered after the version-1.0.0
freeze. Every amendment must be written before computing the affected result.

For each amendment, record:

1. timestamp and discovery stage;
2. evidence independent of the affected coefficient;
3. estimands and outputs affected;
4. frozen rule being replaced;
5. replacement rule;
6. expected consequence, including expected sign if one can be stated; and
7. whether any affected outcome result had already been viewed.

Changes motivated by coefficient sign, magnitude, standard error, p-value, gate status,
or manuscript narrative are prohibited. A sensitivity specification cannot become the
primary specification through an amendment.

## A001 — Operational denominators for Gate G0

**Timestamp:** 2026-09-04T13:55:49-03:00  
**Discovery stage:** implementation of Gate G0, before its first run

1. **Evidence independent of the affected coefficient.** The frozen protocol fixes
   all G0 thresholds and sample restrictions, but it does not state the exact order in
   which pre-date eligibility, date validity, age reconciliation, bandwidth, and
   outcome-validity filters enter each denominator. Official annual totals also occur
   in publications from different extraction vintages; exact equality is meaningful
   only against an explicitly comparable anchor. These are implementation questions,
   not findings about an outcome contrast.
2. **Affected estimands and outputs.** Only G0 data-quality shares, counts, annual
   reconciliation, and the G0 verdict. No coefficient, discontinuity, density test,
   or causal estimand is affected or permitted in this run.
3. **Frozen rule being replaced.** No substantive frozen rule or numerical threshold
   is replaced. This amendment fills an unspecified denominator/order convention.
4. **Replacement/clarifying rule.** Apply the following deterministic conventions:

   - annual raw totals count every CSV row and must equal the designated independent,
     same-vintage official anchor exactly; retain conflicting preliminary vintages as
     contextual anchors and never silently substitute them;
   - the exact-date-validity denominator is the pre-date candidate set with reported
     `IDADEMAE` 15 or 16, `GRAVIDEZ=1`, and a valid `CODMUNRES` region prefix;
   - a date pair is valid only when both strings are strict eight-digit `ddmmyyyy`,
     round-trip to the same strings, the child birth year equals the file year, the
     maternal date precedes the child date, and calendar completed age is 8--59;
   - completed-age agreement is evaluated among exact-date-valid candidates and means
     equality between calendar completed age and reported `IDADEMAE`;
   - valid-status shares by era and side use exact-date-valid, age-reconciled,
     singleton, valid-geography records with positive triangular-kernel support at
     `h=90` (`abs(x)<90`), before restricting `ESTCIVMAE` to codes 1--5;
   - birth and married-event thresholds use the same records after the valid-status
     restriction. Band-count audits at `h` use `abs(x)<h`, with `x<0` below and
     `x>=0` above; and
   - calendar-month totals use every record with a strict valid child date in the file
     year, with invalid child dates reported separately.
5. **Expected consequence.** The clarification makes G0 reproducible and may change
   only the mechanical denominators relative to other plausible filter orders. There
   is no defensible expected sign for the resulting gate margins.
6. **Affected outcome result already viewed?** No. No table, plot, coefficient, share,
   or contrast indexed by daily distance from age 16 had been computed or viewed when
   this amendment was recorded.

## A002 — Operational implementation of Gate G1

**Timestamp:** 2026-09-04T14:20:43-03:00  
**Discovery stage:** implementation of Gate G1, before its first run

1. **Evidence independent of the affected statistics.** The lock defines the G1
   thresholds, mandates mass-point-adjusted `rddensity`, and points continuity tests
   to the primary estimator, but does not fix the density estimator's remaining
   options, the standardization denominator, the membership of missing categories,
   or the exact pre-outcome sample used by each diagnostic. Package versions and the
   SINASC data dictionary were checked without computing any G1 statistic.
2. **Affected estimands and outputs.** G1 density/heaping diagnostics, predetermined
   covariate continuity, composition diagnostics, status-missingness continuity, and
   the G1 verdict. No marriage-outcome coefficient or G2/G3 result is affected or
   permitted in this run.
3. **Frozen rule being replaced.** No threshold or substantive rule is replaced.
   This amendment makes the underspecified implementation choices deterministic.
4. **Replacement/clarifying rule.** Use these conventions:

   - the density universe contains singleton births with valid geography, exact dates,
     and reported/calendar-age agreement, irrespective of conjugal-status validity,
     on the frozen inclusive support `-180 <= x <= 180`;
   - in each era run `rddensity` at zero with `p=2`, `q=3`, unrestricted fits,
     triangular kernel, jackknife variance, mass-point adjustment, the combined
     data-driven bandwidth selector, regularization, bias correction, and binomial
     diagnostics. The hard gate uses the robust jackknife p-value and the absolute
     log ratio of the bias-corrected right and left density estimates. A nonpositive
     density estimate or software non-identification is `QUALIFIED`, never a pass;
   - exact count ratios use equal-day windows `x=-k,...,-1` and `x=0,...,k-1` for
     `k` in 7, 14, and 30. Daily and weekly birth counts are descriptive only and do
     not override the `rddensity` gate;
   - continuity models use valid-status records from that universe with `abs(x)<90`,
     triangular weights, the frozen stacked local-linear interactions, birth-year and
     child-month fixed effects, and two-way clustering by residence municipality and
     exact child date. The tested coefficient is `Above x Post` in percentage points;
   - the hard predetermined family consists of ten binary indicators: the five valid
     `RACACORMAE` categories and the five Brazilian-region prefixes of `CODUFNATU`.
     Holm adjustment is across all ten. Unknown race and birthplace indicators are
     reported in a separate non-hard missingness family;
   - standardized magnitude is the absolute percentage-point coefficient divided by
     100 times the triangular-weighted pooled standard deviation of the underlying
     binary indicator in the common continuity sample;
   - the non-hard composition family contains seven `ESCMAE2010` indicators (codes
     0--5 plus unknown), primiparity `1(QTDFILVIVO=0)` plus its unknown indicator, and
     five residence-region indicators. Holm adjustment is across these 14 diagnostics;
     and
   - the missing-status model uses the density universe with `abs(x)<90`, before the
     status restriction, and defines missing/invalid as `ESTCIVMAE` outside 1--5. It
     otherwise uses the same frozen estimator and reports `Above x Post` in percentage
     points. No married-status indicator is constructed.
5. **Expected consequence.** These choices determine finite-sample bandwidths,
   multiplicity families, and standardized scales. No expected sign is defensible for
   any density or continuity diagnostic.
6. **Affected result already viewed?** No. G0 counts were viewed as required, but no
   G1 density estimate, count ratio, covariate coefficient, status-missingness
   coefficient, or G1 verdict had been computed or viewed when A002 was recorded.

## A003 — Operational implementation of Gate G2

**Timestamp:** 2026-09-04T14:40:30-03:00  
**Discovery stage:** implementation of Gate G2, before its first run

1. **Evidence independent of the affected statistics.** The lock fixes the temporal
   and age placebo designs, the equivalence margin, the two failure clauses, and Holm
   adjustment for the three placebo ages. It does not state an affirmative pass rule
   for the age-placebo family, whether “two placebo ages reject” refers to raw or
   multiplicity-adjusted tests, how non-identification enters the combined G2 status,
   or the exact implementation of the annual-jump and leave-one-year diagnostics.
   Inspection was limited to the frozen documents, archive manifests, ZIP members,
   and column headers. The required 2013--2014 archives are locally available as
   `DNBR2013_csv.zip` and `DNBR2014_csv.zip`; no G2 outcome statistic was computed.
2. **Affected estimands and outputs.** Only the age-16 pre-law temporal placebo, the
   age-15/17/19 placebo family, annual age-16 jumps, leave-one-primary-year-out
   diagnostics, and the G2 verdict. The full primary age-16 pre-versus-post estimate,
   `DELAY90`, secondary outcomes, sensitivity estimates, and every G3 classification
   remain prohibited in this run.
3. **Frozen rule being replaced.** No outcome, period, bandwidth, estimator, numerical
   threshold, failure rule, or multiplicity family is replaced. This amendment fills
   implementation and classification gaps required to apply the frozen rules.
4. **Replacement/clarifying rule.** Apply the following deterministic conventions:

   - require unchanged `PASS` artifacts for G0 and G1 before constructing the G2
     outcome; validate every raw ZIP against `SHA256_MANIFEST.txt` and stream years
     sequentially without persisting person-level data;
   - for each relevant birthday, retain singleton births with valid residence
     geography, valid strict child and maternal dates, calendar/reported-age agreement,
     `ESTCIVMAE` in 1--5, and positive triangular support `abs(x)<90`. Define the
     placebo outcome as `100*1(ESTCIVMAE=2)`. A birth on the birthday is on the right;
   - construct each cutoff-specific birthday in calendar time. For placebo ages 15,
     17, and 19, exclude and count February-29 births when that anniversary does not
     exist. Any other impossible anniversary among otherwise eligible records stops
     execution;
   - estimate every pooled contrast with the frozen stacked local-linear interactions,
     triangular weights, birth-year and child-month fixed effects, and two-way
     clustering by residence municipality and exact child date. Report two-sided
     fixest confidence intervals at 90 and 95 percent and the coefficient on
     `Above x comparison-period` in percentage points;
   - the temporal placebo compares 2013--2014 with pseudo-post 2016--2018 at age 16.
     It is `PASS` only when identified and its IC90% lies wholly inside
     `[-0.25,+0.25]`; it is `FAIL` when identified, its IC95% excludes zero, and the
     absolute point estimate is at least 0.25; all other identified results and any
     non-identification are `QUALIFIED`;
   - compute raw two-sided p-values for ages 15, 17, and 19 and Holm-adjust all three.
     “Reject” in both frozen age-placebo failure clauses means Holm-adjusted `p<0.05`.
     The family is `PASS` only when all three estimates are identified and every IC90%
     lies wholly inside `[-0.25,+0.25]`. It is `FAIL` if at least one Holm rejection
     also has absolute magnitude at least 0.25, or at least two Holm rejections occur
     regardless of magnitude. Every case between those rules is `QUALIFIED`, applying
     the frozen intermediate rule conservatively rather than treating imprecision as
     evidence of balance;
   - estimate age-16 annual right-minus-left jumps for 2013--2014 and 2016--2024. A
     within-year model uses the same local-linear terms, weights, month fixed effects,
     and two-way clustering; the constant birth-year effect is omitted. Estimate all
     nine combinations that omit one of 2016--2018 and one of 2022--2024 from the
     stacked age-16 comparison. These are mandatory stability diagnostics only: their
     signs or p-values do not change a binding placebo verdict. Non-identification of
     any required annual or leave-one-out model makes an otherwise passing G2
     `QUALIFIED`; and
   - the combined G2 status is `FAIL` if either binding placebo component fails,
     `PASS` only if both pass and all required stability diagnostics are identified,
     and `QUALIFIED` otherwise. Do not compute the full-sample primary age-16 policy
     coefficient as part of G2.
5. **Expected consequence.** The conservative pass rules prevent wide placebo
   intervals or unadjusted multiple testing from being labeled successful
   counterfactual validation. No expected sign or likely gate status is defensible.
6. **Affected result already viewed?** No. G0 and G1 outputs had been viewed before
   this amendment, as required by sequential gating, but no temporal-placebo,
   age-placebo, annual-jump, leave-one-out coefficient, or G2 verdict had been computed
   or viewed. The earlier G0/G1 results are not changed by this clarification.

## A004 — Operational implementation of Gate G3

**Timestamp:** 2026-09-04T15:11:09-03:00  
**Discovery stage:** implementation of Gate G3, before its first run

1. **Evidence independent of the affected statistics.** The lock fixes the primary
   estimand, estimator, delay-sensitive estimand, sensitivity set, and six possible G3
   labels. It does not fix a precedence rule when labels overlap, the computational
   meaning of a Holm-adjusted interval, the exact implementation of `DELAY90`, or all
   sample details for the three frozen robustness samples. G1 already documented
   exact-day heaping through its prespecified binomial diagnostics, so the lock requires
   displaying all three donut estimates. The archived `rdrobust` 3.0.0 source was
   obtained from CRAN and installed locally; its API was checked only with synthetic
   data. No SINASC G3 outcome model, table, or plot was computed or viewed.
2. **Affected estimands and outputs.** The primary age-16 difference in discontinuities,
   `DELAY90`, joint Wald test, secondary outcomes, frozen sensitivities, `rdrobust`
   cross-checks, G3 classification, figures, and overall paper-path decision.
3. **Frozen rule being replaced.** No sample, outcome, period, bandwidth, estimator,
   threshold, sensitivity, or substantive decision rule is replaced. This amendment
   resolves implementation ambiguities needed to apply the frozen rules exactly once.
4. **Replacement/clarifying rule.** Apply these deterministic conventions:

   - require unchanged valid manifests and `PASS` verdicts for G0 and G1. G2 may be
     `PASS` or `QUALIFIED`; retain its actual verdict in the overall decision. A G2
     `FAIL` would stop G3 estimation. Stream only 2016--2018 and 2022--2024, validate
     every raw hash, and write no person-level derivative;
   - the primary sample contains known singleton gestations (`GRAVIDEZ=1`), valid
     residence geography, strict valid child and maternal dates, agreement between
     calendar and reported completed age, `ESTCIVMAE` in 1--5, and positive kernel
     support `abs(x)<h`. A birthday birth is above. The multiple-gestation check admits
     known codes 1--3 while retaining live birth as the unit. The unknown-status check
     uses otherwise primary-eligible singleton records before the status restriction
     and codes every status other than 2 as not married;
   - retain the entire locatable age-15/16 support for the full-support `rdrobust`
     diagnostic. It uses the package's `mserd` bandwidth selector with the frozen
     `p=1`, `q=2`, triangular kernel, nearest-neighbor variance with three matches, and
     mass-point adjustment. All fixed-bandwidth `rdrobust` fits use symmetric
     `h` and `b=2h`; separate pre and post bias-corrected jumps are subtracted only as
     a point comparison, with no standard error for that subtraction;
   - estimate `DELAY90` by the algebraically equivalent reparameterization
     `Above*Post*(x-45)`. Its coefficient on `Above*Post` equals `tau+45*phi` and uses
     the same observations, weights, fixed effects, and two-way covariance estimator as
     the primary fit. Compute the joint `tau=phi=0` test with `fixest::wald` from the
     original parameterization;
   - for the auxiliary family `{tau, DELAY90}`, compute raw two-sided p-values and Holm
     adjusted p-values. Rank the two raw p-values from smallest to largest; the
     rank-specific Holm interval uses confidence level
     `1-0.05/(2-rank+1)` (97.5 percent for rank 1 and 95 percent for rank 2). A delayed
     signal requires a positive `DELAY90`, Holm p below 0.05, a positive lower endpoint
     of that rank-specific interval, and no supported positive immediate jump. The
     primary `tau` table still reports its unadjusted 90 and 95 percent intervals because
     the lock has one primary outcome;
   - assign one G3 label in this precedence order: `SUPPORTED_POSITIVE_EFFECT`,
     `CONTRARY_EFFECT`, `DELAYED_RESPONSE_SIGNAL`,
     `INFORMATIVE_NO_LOCAL_PROFILE`, `INFORMATIVE_NO_JUMP`, then `INCONCLUSIVE`.
     The more informative profile-null label precedes the nested no-jump label. Report
     every underlying Boolean condition so a contrary immediate jump cannot conceal a
     separately detected delayed signal;
   - the pre-cutoff benchmark is the triangular-weighted married share among primary
     pre-law observations with `x<0` at `h=90`. Relative magnitude is `100*tau/share`;
     `MDE80=2.8*SE`. Non-identification of `tau` or `DELAY90` yields `INCONCLUSIVE`;
   - the precision check adds residence macroregion and race/color as categorical fixed
     effects, each with an explicit unknown/invalid category. HC1 means the `fixest`
     heteroskedastic covariance estimator. A donut of `d` days excludes
     `abs(x)<=d`. Because G1's already frozen binomial diagnostics reject local
     equal-day counts, display `d` in 1, 3, and 7, without using them to alter a gate;
   - fit `UNIAO_ESTAVEL` and `ANY_UNION` with the primary h=90 estimator and apply Holm
     only across those two raw p-values. They do not change the primary G3 label; and
   - the RD figure pools observations into seven-day bins by era. Suppress plotted bin
     shares when married-event counts are 1--9. Overlay descriptive, triangular-weighted
     local-linear fits by era and side; these lines illustrate the raw age profile and
     are not a substitute for the fixed-effect primary coefficient.
5. **Expected consequence.** These conventions make the frozen analysis reproducible,
   favor the primary immediate-jump result when classifications conflict, and prevent
   unadjusted delay or robustness results from rescuing a weak primary design. No
   expected sign, magnitude, precision, or G3 label is defensible before execution.
6. **Affected result already viewed?** No. Required G0--G2 outputs were already viewed,
   and G2 was `QUALIFIED`. No primary G3 coefficient, `DELAY90`, secondary-outcome
   estimate, sensitivity estimate, `rdrobust` estimate on SINASC, or G3 figure had been
   computed or viewed when this amendment was recorded.
