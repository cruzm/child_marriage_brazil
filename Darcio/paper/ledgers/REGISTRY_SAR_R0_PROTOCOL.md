# Registry/SAR R0 — local-readiness protocol

**Version:** 1.0.0  
**Frozen:** 2026-09-04T15:57:13-03:00  
**Timing:** after all public-data and SINASC results, before any restricted RC.2
microdata, exact-age tabulation, or coefficient.  
**Scope:** local feasibility only; this protocol does not authorize an external
request and cannot close the causal-identification gate.

## Objective and decision

R0 asks whether the exact-date Civil Registry redesign is ready to be sent to
the IBGE. It audits the public planning inputs, selects and exports a compatible
aggregate denominator candidate, computes a transparent power envelope, and
tests the intended estimator on synthetic data with a known effect.

The strongest possible R0 verdict is `LOCAL_READY_EXTERNAL_PENDING`. This means
that all work possible without the restricted files is reproducible. It does
not mean that the RC.2 fields exist in every analytical year, that their quality
passes the thresholds below, or that the reform effect has been estimated.

## Causal object reserved for the restricted-data design

The target is the post-minus-pre change in the formal-marriage event-rate
discontinuity at age 16. Exact age is measured on the celebration date. The
numerator counts spouses entering registered civil marriages; the denominator
measures compatible resident population person-time. The design is an
age-by-calendar difference in discontinuities for event rates, not an
individual-outcome RD.

The required assumption is that, absent Law 13.811/2019, the age-16
discontinuity would have changed smoothly at 13 March 2019. Pre-law stability,
placebo dates, placebo ages, heaping, date edits, and celebration-to-registration
lags must probe this assumption before a causal claim is allowed.

The maximum future claim is local: the effect of the post-law eligibility
regime on formal civil-marriage incidence near age 16. The design cannot by
itself identify informal unions, all child marriage, or effects far from the
cutoff.

## Public planning inputs

R0 uses three pre-existing aggregate files:

1. `REGISTRY_PERSON_EVENTS_ANNUAL.csv` for age-15 and age-16 counts by
   registration year. These counts screen power only because neither timing nor
   age has the future celebration-date meaning.
2. `QUARTERLY_DENOMINATORS_AGE_SEX.csv` for the selected national PNADC
   exposure candidate.
3. `DENOMINATORS_AGE_SEX.csv` for an annual-versus-quarterly population check.

No public coefficient is re-estimated and no SINASC specification is reopened.

## Denominator selected before restricted outcomes

The primary candidate is the quarterly national PNADC population at completed
ages 15 and 16, separately for combined, female, and male populations. For a
cell at an exact age-day within a quarter, R0 exports:

- population divided by 365.2425 as the approximate stock per exact age-day;
- population multiplied by quarter length and divided by 365.2425 as
  person-time for an exact age-day accumulated over that quarter; and
- the corresponding survey standard errors.

This is a smooth-exposure approximation, not a directly observed daily risk
set. The future restricted analysis must retain denominator uncertainty. A
birth-cohort reconstruction from SINASC/SIM may validate the approximation but
cannot silently replace it after the policy contrast is seen.

The combined-sex primary candidate must contain all 96 year-quarter-age cells,
have maximum CV no larger than 2.5%, and at least 2,000 unweighted observations
per cell. Female and male sensitivities must satisfy the same coverage and
sample-size rule with maximum CV no larger than 4%. Where annual PNADC estimates
exist, the largest absolute annual-versus-quarterly difference must not exceed
5% for any sex.

## Power envelope

R0 converts the four public counts — pre/post by ages 15/16 — into planning
counts for 30-, 90-, 180-, and 365-day windows. It crosses three within-age
allocation multipliers (0.5, 1, and 1.5) with variance-inflation factors (1,
1.5, and 2). The calculation uses a two-sided 5% test, 80% power, and the
Poisson four-cell approximation for a log difference in incidence-rate ratios.

The base screen requires a decline MDE no larger than 20% for combined sexes at
90 days under uniform allocation and no variance inflation. The stress screen
requires an MDE no larger than 30% at 180 days with half the proportional count
and variance inflation of two. A pass remains provisional until exact
celebration-date counts and the final inference method are available.

## Synthetic dry run

The dry run generates monthly-by-exact-age-day cells for 2013–2024, omits March
2019, and marks every row `synthetic=TRUE`. A PPML model with a person-time
offset estimates a known below-age-16 post-law incidence-rate ratio of 0.60.
The recovered log coefficient must be within 0.10 log point of the truth and
its 95% interval must contain the true value. Synthetic estimates are software
tests and are forbidden from the paper's substantive exhibits.

## External go/no-go criteria

The inquiry must confirm annual retention and coding of celebration dates,
birth dates, residence, registration dates, source-flow and edit/imputation
flags, including the SEADE flow for São Paulo. Inside the SAR, exact dates must
be at least 99% valid in target ages, residence at least 95% valid, annual totals
must reconcile to public tables, and exact-window power must be recalculated.

Any failure stops outcome inspection or keeps the material descriptive. R0
cannot relabel a pending external criterion as passed.

## Reproduction

From the repository root:

```bash
make -f Darcio/Makefile registry-sar-r0
```

The check-only target verifies frozen hashes and existing aggregate artifacts:

```bash
make -f Darcio/Makefile registry-sar-r0-check
```

