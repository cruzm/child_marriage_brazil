# SINASC daily age-16 protocol

**Version:** 1.0.0  
**Frozen:** 2026-09-04T13:38:08-03:00  
**Machine-readable lock:** `config/sinasc_daily_lock.yml`  
**Amendments:** `paper/ledgers/SINASC_DAILY_AMENDMENTS.md`  
**Status:** frozen before any outcome contrast by daily distance from an age cutoff

This is a prospective **post-result** protocol for a new design. The Registry, PNADC,
and age-group SINASC estimates were known before the freeze. No daily age-distance
plot, coefficient, standard error, density test, or placebo-cutoff result had been
constructed or viewed. The protocol neither modifies the earlier locks nor becomes
ex ante merely because the new running variable has not yet been analyzed.

## Decision in one paragraph

The pilot asks whether Brazil's 2019 reform increased the age-16 discontinuity in
recorded married status among adolescent mothers giving birth. It compares mothers
within 90 days of their sixteenth birthday in 2016--2018 with the corresponding local
age contrast in 2022--2024. A stacked local-linear model is primary. Exact-date quality,
birth density, predetermined composition, a pre-law pseudo-reform, and placebo cutoffs
at ages 15, 17, and 19 are binding gates. The design replaces the current causal core
only if those gates pass and the age profile is informative under the frozen decision
rule. A precise zero at the cutoff alone does not establish no response because marital
status may adjust after a processing delay. Failed gates remain failures; another
bandwidth or outcome cannot replace the frozen primary result.

## 1. Question, mechanism, and scope

### One-sentence question

> Did eliminating the below-16 pregnancy exception increase the discontinuity at age
> 16 in the probability that an adolescent mother is recorded as married when she
> gives birth?

Before Law 13.811/2019, pregnancy supplied the remaining operative route to civil
marriage below age 16. The law took effect on March 13, 2019 and prohibited civil
marriage below 16, while ordinary eligibility at ages 16--17 with authorization
remained. Define the age-16 jump as the married share just above the birthday minus the
share just below it. The mechanism predicts a more positive jump after the reform.

The outcome is `ESTCIVMAE=2` on the Declaration of Live Birth. It is a recorded status,
not a registry-verified marriage event. The estimand conditions on a singleton live
birth and is local to mothers near age 16. Even if every gate passes, the paper may not
claim an effect on all adolescents, all pregnancies, marriage incidence, or informal
unions not recorded by SINASC.

### Design diagram

```text
                         family and local conditions
                           |                   |
                           v                   v
Law 13.811 -> legal eligibility -> civil marriage -> status recorded at birth
      |                                  ^                 ^
      |                                  |                 |
      +-> fertility / pregnancy timing -> live-birth sample+

Exact age at childbirth -> ordinary eligibility begins at 16
Calendar period --------> marriage norms, registration, and status coding
```

Conditioning on a live birth defines the target population; it does not recover a
population effect for adolescents. Fertility or pregnancy-selection responses can also
change who appears in SINASC. No post-treatment maternal or infant variable enters the
primary regression.

## 2. Prior exposure and novelty of this analysis

The following facts were known before this protocol:

- the trended age-group SINASC estimate for married status is +29.3 percent and the
  no-trend estimate is -23.9 percent;
- joint leads and the 2017 and 2018 placebo reforms reject the age-group design;
- an existing robustness defines age as `(DTNASC-DTNASCMAE)/365.25`, floors it to whole
  years, and estimates +22.36 percent; that calculation contains no daily age-16 cutoff;
- annual and monthly marital-status shares, the audit counts for 2015 and 2019, and
  feasibility counts around completed ages 15--16 were known;
- the open 2015 file is 7.7 percent incomplete and cannot enter estimation; and
- 59,884 of 5,114,051 retained records for mothers aged 10--19 have invalid exact age
  under the existing broad validation (1.171 percent).

No daily distance-to-birthday outcome contrast or diagnostic was seen. This disclosure
must accompany any eventual paper use.

## 3. Data and sample

The source is the official annual SINASC open microdata for 2013--2024 already cached
with SHA-256 manifests. Each row is one live birth. The build will stream each archive,
retain only frozen fields, and never alter or persistently expand a raw file.

### Primary sample

The primary sample includes records that satisfy all five conditions:

1. birth year is 2016--2018 or 2022--2024;
2. `DTNASC` and `DTNASCMAE` parse strictly as calendar dates;
3. the mother's age at childbirth lies from 180 days before through 180 days after her
   sixteenth birthday;
4. `GRAVIDEZ=1`, restricting the analysis to singleton births so twins or higher-order
   multiples do not duplicate one mother's status; and
5. `ESTCIVMAE` is one of codes 1--5 and `CODMUNRES` has a valid Brazilian region prefix.

The main pre period is 2016--2018. The main post period is 2022--2024. These consecutive
three-year windows exclude the incomplete 2015 export, the 2019 transition, and the
2020--2021 pandemic. The post window also reduces legacy status from marriages entered
under the old exception. The price is important: the estimand is a mature-regime
contrast, not the immediate effect of publication.

Years 2013--2014 form a historical pre-law diagnostic. The analysis reports 2019, 2020,
and 2021 separately as transition and pandemic years. They never enter the primary
contrast. Including multiple gestations is a frozen robustness check.

### Exact calendar age

For mother `i`, construct her sixteenth birthday from the day and month in
`DTNASCMAE` and calendar year `year(DTNASCMAE)+16`. Define

```text
x_i = DTNASC_i - sixteenth_birthday_i
```

in integer days. Do not divide elapsed days by 365.25. `x_i<0` is below 16; `x_i>=0`
is at or above 16, so a birth on the birthday belongs to the legally eligible side.
Within the retained support, negative values must reconcile to `IDADEMAE=15` and
nonnegative values to `IDADEMAE=16`. The build logs every disagreement before excluding
it. An impossible sixteenth-birthday date stops the build rather than triggering a
silent correction.

For placebo ages 15, 17, and 19, mothers born on February 29 are excluded whenever the
corresponding anniversary does not exist in that year. Their counts remain in the audit.

## 4. Estimand and primary estimator

Let `J_pre` be the right-minus-left limit in the married share at age 16 during
2016--2018. Define `J_post` analogously for 2022--2024. The primary estimand is

```text
tau = J_post - J_pre,
```

in percentage points. The predicted sign is positive.

The primary estimator is a stacked local-linear probability model within 90 days of the
cutoff. It uses triangular weights `max(0, 1-|x|/90)` and fully interacts the running
variable with cutoff side and policy era:

```text
Y_i = alpha + theta Above_i + tau(Above_i x Post_i)
      + beta1 x_i + beta2(Above_i x x_i)
      + beta3(Post_i x x_i) + beta4(Above_i x Post_i x x_i)
      + birth-year FE + child-calendar-month FE + error_i.
```

`Y_i` equals 100 for `ESTCIVMAE=2` and zero for another valid status. `Post_i` equals
one in 2022--2024; its main effect is absorbed by birth-year fixed effects. Standard
errors are two-way clustered by municipality of residence and the child's exact date of
birth. The coefficient on `Above x Post` is the reported estimate.

The primary result reports the point estimate, 95 percent confidence interval, p-value,
pre-cutoff married share, effect relative to that share, and `MDE80 = 2.8 x SE`. Failure
to reject zero never becomes evidence of no effect without the frozen equivalence test.

### Delay-sensitive secondary estimand

Civil marriage requires habilitation and celebration. Legal eligibility can therefore
change the slope of married status after the birthday without generating an immediate
jump. Let `phi` denote the post-minus-pre change in the right-versus-left slope kink.
The frozen secondary estimand is

```text
DELAY90 = tau + 45 phi.
```

This is the equal-day average fitted excess over the first 90 days above the cutoff relative to a
continuation of the left-side profile. The analysis also reports the joint Wald test
`tau=phi=0`. `DELAY90` is more dependent on the local-linear approximation than the
cutoff jump. It cannot replace `tau`, repair a failed gate, or support an RD claim by
itself. For the auxiliary claim that either an immediate or accumulated response
exists, Holm adjustment applies across `tau` and `DELAY90`.

### `rdrobust` cross-check

A confirmatory cross-check estimates `J_pre` and `J_post` separately with `rdrobust`
3.0.0, then subtracts the bias-corrected jumps as a point-estimate comparison. It reports
each era's robust interval but does not construct inference for their difference:
separate fits do not retain the covariance generated by municipalities observed in both
eras. The stacked model supplies inference for `tau`. Frozen settings are local linear
`p=1`, bias polynomial `q=2`, triangular kernel, `h=90`, `b=180`, nearest-neighbor
variance with three matches, and mass-point adjustment. This check cannot displace the
stacked primary model.

## 5. Outcomes and multiplicity

### Primary outcome

- **MARRIED:** `100 x 1(ESTCIVMAE=2)`, among records with codes 1--5.

There is one primary outcome, cutoff, bandwidth, sample, and period contrast. No
multiplicity correction applies to it.

### Secondary outcome family

- **UNIAO_ESTAVEL:** `100 x 1(ESTCIVMAE=5)`, predicted negative or null for the change
  in the above-minus-below jump.
- **ANY_UNION:** `100 x 1(ESTCIVMAE in {2,5})`, predicted null under pure relabeling.

Holm adjustment applies across these two outcomes. `UNIAO_ESTAVEL` alone cannot prove
behavioral substitution because recorded categories may change without living
arrangements changing.

Unknown status, exact-date validity, and composition variables are diagnostics. Birth
weight, gestational age, prenatal care, Apgar scores, fertility, schooling effects, and
other downstream outcomes are outside this protocol. No heterogeneity search is
authorized.

## 6. Frozen sensitivity set

Every item below is reported regardless of sign or significance:

- bandwidths of 30, 60, and 180 days, keeping 90 days primary;
- `rdrobust` bias bandwidth equal to twice the estimation bandwidth;
- stacked-model inference clustered by exact age-in-days, and HC1 inference;
- a precision check adding only fixed macroregion and race/color categories;
- a local-quadratic stacked model at 180 days; and
- donut windows of 1, 3, and 7 days, displayed only if heaping is detected.

A donut estimate does not repair a density failure and never replaces the primary.
Researchers may not add or remove a bandwidth after seeing the coefficient plot.

## 7. Binding diagnostics

### Gate G0 — data integrity and power

Before computing an outcome coefficient, the build must establish:

- exact agreement between every primary year's row count and an independent official
  annual total or official tabulation; a checksum of the cached export is not enough;
- at least 98 percent valid exact dates in each primary year;
- at least 99 percent agreement between constructed and reported completed age among
  records with valid dates;
- at least 95 percent valid conjugal status in each era-by-side cell; and
- at least 10,000 births and 100 married outcomes in every era-by-side cell within the
  90-day bandwidth.

The audit also reports annual/monthly totals, exact-date validity by status, singleton
coding, and counts for every frozen bandwidth. Failure stops estimation and requires a
documented amendment or abandonment. If no independent total can be obtained for a
primary year, G0 is qualified rather than passed and the design cannot receive an
unconditional causal-core verdict.

### Gate G1 — density, missingness, and composition

Run `rddensity` at age 16 separately by era with mass-point adjustment. Complement it
with exact equal-day count comparisons: `x=-k,...,-1` versus `x=0,...,k-1` for
`k in {7,14,30}`. A density jump is a hard failure if it rejects equality at 5 percent
and exceeds 5 percent in magnitude in either primary era.

Apply the primary model to predetermined race/color and maternal-birthplace indicators.
Holm-adjusted `p<0.05` combined with an absolute standardized discontinuity of at least
0.10 is a hard failure. Schooling, parity, and residence are reported separately as
composition or possible response variables; they are not primary controls.

Unknown conjugal status is also an outcome. A significant post-minus-pre discontinuity
of at least 0.50 percentage points is a hard failure. Invalid maternal date cannot be
located on the daily running variable, so its rate is compared across completed ages 15
and 16 by era and reported as a coarser diagnostic.

### Gate G2 — counterfactual stability

The temporal placebo treats 2016--2018 as pseudo-post relative to 2013--2014, when both
periods precede the law. It repeats the age-16 model at 90 days. The placebo passes only
if its 90 percent interval lies within +/-0.25 percentage points. It fails if the
95 percent interval excludes zero and its magnitude reaches 0.25 points. Intermediate
cases are labeled qualified/inconclusive.

Repeat the primary era contrast at placebo birthdays 15, 17, and 19. Holm adjustment
applies across the three. The placebo-age gate fails if any adjusted `p<0.05` estimate
has magnitude of at least 0.25 points, or if two cutoffs reject regardless of size.

Estimate each valid year's age-16 jump and show all annual estimates in one figure.
Leave-one-pre-year and leave-one-post-year combinations must also remain visible. A
pooled coefficient cannot hide unstable annual jumps.

### Gate G3 — informativeness

The policy-relevant equivalence margin is +/-0.25 percentage points, approximately one
quarter of the under-16 married share seen in the pre-existing audit. Classify the
primary result mechanically:

- **supported positive effect:** 95 percent interval above zero and point estimate at
  least +0.25 points;
- **informative no-jump result:** the 90 percent interval for `tau` lies wholly inside
  [-0.25,+0.25]; this rules out only an immediate cutoff jump;
- **informative no-local-profile result:** both `tau` and `DELAY90` have 90 percent
  intervals wholly inside [-0.25,+0.25];
- **delayed-response signal:** `DELAY90` is positive with a Holm-adjusted 95 percent
  interval above zero while the immediate jump is not supported;
- **contrary effect:** 95 percent interval below zero;
- **inconclusive:** every other result.

This classification separates statistical detection, economic magnitude, and precision.

### Overall decision

The daily design advances as the paper's causal core only when G0 and G1 pass, G2
passes, and G3 yields either a supported positive jump or an informative absence of any
local profile change. The latter supports only a narrow local null. A delayed-response
signal or qualified G2 permits a conditional design seeking validation with exact
Registry microdata; it does not become a sharp RD result. Any hard failure, failed
counterfactual gate, or inconclusive profile means **do not recenter the paper**.

## 8. Exhibits fixed before estimation

1. **Figure 1:** weekly-binned married shares against daily distance from age 16,
   separately for pre and post, with local fits.
2. **Figure 2:** every annual age-16 jump with 95 percent intervals and explicit labels
   for transition and pandemic years.
3. **Table 1:** sample construction, date/status missingness, and era-by-side counts.
4. **Table 2:** primary estimate, MDE, equivalence classification, `rdrobust` check, and
   the complete bandwidth sensitivity set.
5. **Table 3:** density, continuity, temporal-placebo, and age-placebo gates.

Figures may not display municipality-by-day cells or cells with 1--9 outcome events.
Pool into weekly bins or suppress them. Estimation may use the public person-level data,
but only aggregates leave the analytical environment.

## 9. Threats that remain even after a pass

1. Age at childbirth is not age at marriage. Crossing 16 creates eligibility, but
   habilitation and celebration take time; the immediate jump may understate a delayed
   response.
2. Recorded status is not linked to a civil registry. Category changes can reflect
   reporting rather than legal marriage.
3. The sample conditions on a live birth. The design estimates no effect for adolescents
   who did not give birth.
4. The post period is separated from the reform by the pandemic. Difference-in-
   discontinuities removes smooth age profiles, not a new post-period shock that itself
   changes the age-16 jump.
5. SINASC lacks a stable public maternal identifier. The analysis cannot identify
   repeated births to the same mother; singleton restriction only prevents duplication
   within a multiple delivery.
6. A statistically clean local effect does not distinguish prevention from marriage
   delayed beyond the observed childbirth date.

These limitations define the claim. They do not become footnotes or disappear after a
significant coefficient.

## 10. Amendment and reporting rules

Only a documented data error, unavailable frozen field, software non-identification, or
implementation ambiguity permits an amendment. Record it in
`SINASC_DAILY_AMENDMENTS.md` before computing the affected result, including evidence,
timestamp, affected estimands, replacement rule, and expected direction. Coefficient
sign, magnitude, uncertainty, or narrative fit never justifies an amendment.

A failed gate cannot be repaired by promoting a sensitivity check. Any subsequent
design becomes version 2, explicitly post-version-1 results. All outputs must retain the
`post_result_protocol` label and the placeholder `[RESULT TO BE ESTIMATED]` remains until
the locked pipeline runs.

## 11. Paper path if the design passes

The paper would make one contribution: Brazil removed a pregnancy-specific legal route
below 16, and exact maternal birthdays reveal whether recorded marriage among mothers
shifted at the remaining eligibility threshold. Registry and PNADC evidence would become
measurement context rather than coequal identification strategies.

| Closest paper | Existing contribution | Distinction this design must sustain |
|---|---|---|
| Bellés-Obrero and Lombardi (2023) | Staggered Mexican bans, marriage registrations, and informal unions | Pregnancy-conditioned age-16 margin under a national Brazilian reform |
| McGavock (2021) | Regional rollout in Ethiopia's high-prevalence setting | Exact threshold in a low-formalization setting |
| Collin and Talbot (2023) | Cross-country enforcement tests around legal ages | Change in the age discontinuity induced by one reform |
| Blank, Charles, and Sallee (2009) | Administrative-versus-survey avoidance | A local policy contrast, not measurement divergence alone |
| Urquia et al. (2022) | Descriptive SINASC evidence through 2018 | Exact-age post-2019 policy design rather than another status description |

The ambitious journal set is *Journal of Human Resources*, *Journal of Development
Economics*, and *Journal of Population Economics*, conditional on a clean and informative
design. *World Development* and *Demographic Research* are the narrower set for a credible
local result or informative null. No outlet claim is made before the gates and substantive
magnitude are known.
