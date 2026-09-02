# Claim--Evidence Matrix — Paper 1

**Version:** 2026-09-02, after SINASC Amendment A1.  
**Rule:** `verified` means the cited local artifact or primary external source was
opened. A model-dependent interval never becomes a design-free bound, and failure to
reject zero never becomes evidence of zero.

## Gate verdict

The manuscript can proceed as a working draft, but Gate 5 remains open. The numerical
claims are now aligned with the post-A1 SINASC outputs. The remaining binding items are:
(i) a defensible trend-sensitivity design for a single national reform, (ii) manual
completion of the novelty checks listed in `NOVELTY_SEARCH_LOG.md`, and (iii) verification
of the broad international-policy claims in the opening paragraph.

| ID | Location / claim | Type | Evidence | Status | Maximum defensible wording / action |
|---|---|---|---|---|---|
| C01 | Law 13,811 took effect on 13 March 2019 and eliminated the exceptions below age 16 | legal | Planalto law and compiled Civil Code; `references/SOURCES.csv` | **verified externally** | State the exact legal change. Do not describe it as a ban on every marriage below 18. |
| C02 | Ages 16--17 remained eligible with parental authorization | legal | Civil Code art. 1,517 | **verified externally** | Factual statement permitted. |
| C03 | The reform had no state discretion, phase-in, or verified grandfathering | legal/institutional | Current legal ledger and primary text | **partially verified** | Retain “we could not verify” for grandfathering; do not assert absence of implementation heterogeneity. |
| C04 | Registry age-15 estimate is −1.1%, CI [−14.9%, +14.9%] | causal, conditional | `REGISTRY_PRIMARY_EFFECT.csv`; locked PPML | **verified from files** | “The locked specification estimates…” The interval is conditional on the linear age-trend counterfactual. |
| C05 | No-trend estimate is −37.8% | robustness | `REGISTRY_TREND_SPECIFICATION_DIVERGENCE.csv` | **verified from files** | Call it the otherwise identical no-trend estimate. Do not call it “spurious” as an established fact. |
| C06 | The data rule out a large short-run decline | causal | C04 plus C05 and placebo diagnostics | **not established design-wide** | Only: “Conditional on the locked model, the CI excludes declines larger than 14.9%.” |
| C07 | MDE is a 19.3% decline | precision | `POWER_AND_MDE.csv` | **verified from files** | Report with the test size, power, estimand, and short post window. |
| C08 | Registrations and PNADC unions differ by “two orders of magnitude” | measurement | Registry flow rate versus PNADC stock prevalence | **invalid comparison** | Report both magnitudes separately and state that a flow and stock do not support a ratio. Manuscript corrected. |
| C09 | PNADC estimate is +0.399 p.p., CI [−0.003, +0.801], p=0.052 | behavioral, conditional | `PNADC_UNION_PRIMARY_EFFECT.csv` | **verified from files** | Describe conservative coresident-union **prevalence**, not entry into union. |
| C10 | The reform did not reduce unions | causal | C09; TOST fails; union indicator incomplete | **not established** | “The estimate does not identify a reduction in conservative coresident-union prevalence.” Do not claim zero or unchanged union formation. |
| C11 | PNADC indicates informal substitution | mechanism | C09 and similar microdata point estimates | **suggestive only** | “The positive sign is consistent with relative informalization but does not establish substitution.” |
| C12 | No reliable delay to ages 16--17 | mechanism | `REGISTRY_AGE_SPECIFIC_EFFECTS.csv`; recapture bootstrap | **verified from files, imprecise** | State that delay is not detected precisely; do not state that no delay occurred. |
| C13 | SINASC 2015 is incomplete and excluded under Amendment A1 | data quality | `SINASC_EXTENSION_AMENDMENTS.md`; SVSA validation recorded in source ledger | **verified from files and external anchor** | State exclusion and its timing. Never use 2015 descriptive totals in the paper. |
| C14 | SINASC trended S1 is +29.3%, CI [+11.3%, +50.1%] | diagnostic contrast | `SINASC_STATUS_PRIMARY.csv` | **verified from files** | Report as a failed-design estimate, not a causal effect. |
| C15 | SINASC no-trend S1 is −23.9% | diagnostic contrast | `SINASC_STATUS_ROBUSTNESS.csv` | **verified from files** | Report beside C14 as specification dependence. |
| C16 | [−23.9%, +29.3%] bounds the SINASC causal effect | causal/identification | endpoints C14–C15 only | **false as stated** | This is a **specification range**, not an identified set or confidence interval. Manuscript corrected. |
| C17 | A positive SINASC effect is mechanically impossible | mechanism | direct eligibility mechanism; outcome conditions on birth | **overstated** | It runs against the direct mechanism, but selection into birth and composition can move the conditional share. Manuscript corrected. |
| C18 | SINASC S4 is a precise null | precision | `SINASC_FERTILITY_S4.csv`: +1.6%, CI [−1.3%, +4.6%], p=0.284 | **not established as equivalence** | Report coefficient and interval; do not say “precise null” without an equivalence margin and test. |
| C19 | No differential missing-status change | diagnostic | current SINASC diagnostic: p=0.577 | **verified as non-rejection** | “Shows no detectable differential change.” Do not say missingness was ruled out. |
| C20 | First evaluation centered on Brazil's 2019 reform | novelty | 19-query log and closest-paper table | **provisionally verified** | Keep “to our knowledge”; complete the manual checks listed in `NOVELTY_SEARCH_LOG.md` before submission. Avoid “first causal evidence.” |
| C21 | Minimum-age laws generally change records rather than behavior | external interpretation | Brazil results plus closest international papers | **inferred** | Use “can” and define the setting: a small formal flow alongside prevalent informal unions. |
| C22 | Studies that omit pre-trends systematically overstate policy effects | external causal generalization | one Brazilian setting and cited international evidence | **overstated** | “Can attribute secular declines to the reform.” A systematic directional claim requires multi-setting evidence. |
| C23 | Specification lock predates all principal Registry/PNADC effects | transparency | lock hashes, timestamps, amendments | **verified from files** | Factual statement permitted; distinguish the later SINASC extension lock and Amendment A1. |

## Current canonical SINASC numbers

The canonical source is the post-A1 CSV set produced at 13:00 on 2026-09-02, not the
pre-amendment PDF or earlier prose:

- S1 trended: +29.3%, CI [+11.3%, +50.1%], p=0.0008;
- S1 no trend: −23.9%, CI [−33.6%, −12.7%];
- placebos: 2016 −5.9%, 2017 +19.7%, 2018 +36.8%;
- S4 age 15: +1.6%, CI [−1.3%, +4.6%], p=0.284;
- unknown status: +3.4%, p=0.577.

Any regeneration of these outputs requires rebuilding the manuscript and rerunning a
text-to-output consistency check before distributing the PDF.
