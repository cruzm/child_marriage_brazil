# Claim--Evidence Matrix — Paper 1

**Version:** 2026-09-04, manuscript v0.3 after SINASC daily Gates G0--G3 and the
local Registry/SAR R0 readiness package.
**Rule:** `verified` means the cited local artifact or primary external source was
opened. A model-dependent interval never becomes a design-free bound, and failure to
reject zero never becomes evidence of zero.

## Gate verdict

The manuscript can proceed as a working draft, but Gate 5 remains open. Every empirical
claim and exhibit in v0.3 uses observed official microdata or published aggregates. The
Registry/SAR R0 software-recovery data and coefficient are explicitly excluded from the
manuscript. The numerical claims are aligned with the post-A1 and daily SINASC outputs
and the executed Registry rolling-origin exercise. Neither real-data extension closed
identification: all five public-Registry counterfactuals fail calibration, while the
daily SINASC counterfactual gate is qualified and its informativeness gate is
inconclusive.
The remaining binding items are:
(i) confirmation and access for the exact-date, residence-based Registry fields documented
in the IBGE `RC.2` instrument, rather than another functional form fit to the same 24
pre-quarters; (ii) execution of the exact-date data, counterfactual, and information
gates after access; and (iii) manual completion of the novelty checks listed in
`NOVELTY_SEARCH_LOG.md`. The unsupported count of countries in the opening paragraph was
removed; the narrower SDG Target 5.3 claim is now anchored to the official UN page.

| ID | Location / claim | Type | Evidence | Status | Maximum defensible wording / action |
|---|---|---|---|---|---|
| C01 | Law 13,811 took effect on 13 March 2019 and eliminated the exceptions below age 16 | legal | Planalto law and compiled Civil Code; `references/SOURCES.csv` | **verified externally** | State the exact legal change. Do not describe it as a ban on every marriage below 18. |
| C02 | Ages 16--17 remained eligible with parental authorization | legal | Civil Code art. 1,517 | **verified externally** | Factual statement permitted. |
| C03 | The reform had no state discretion, phase-in, or verified grandfathering | legal/institutional | Current legal ledger and primary text | **partially verified** | Retain “we could not verify” for grandfathering; do not assert absence of implementation heterogeneity. |
| C04 | Registry age-15 estimate is −1.1%, CI [−14.9%, +14.9%] | causal, conditional | `REGISTRY_PRIMARY_EFFECT.csv`; locked PPML | **verified from files** | “The locked specification estimates…” The interval is conditional on the linear age-trend counterfactual. |
| C05 | No-trend estimate is −37.8% | robustness | `REGISTRY_TREND_SPECIFICATION_DIVERGENCE.csv` | **verified from files** | Call it the otherwise identical no-trend estimate. Do not call it “spurious” as an established fact. |
| C06 | The data rule out a large short-run decline | causal | C04--C05; rolling-origin models and diagnostics | **not established design-wide** | Only: “Conditional on the locked model, the CI excludes declines larger than 14.9%.” Every trend candidate fails calibration, and the seasonal-level interval includes a 49% decline. |
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
| C24 | The Registry trend-sensitivity protocol is ex ante | transparency | protocol timestamps; original results already known | **false as stated** | Call it a **post-result protocol frozen before its own extension estimates**. It does not amend the original lock. |
| C25 | None of five Registry trend models passes the frozen calibration gate | design diagnostic | `REGISTRY_TREND_SENSITIVITY_MODELS.csv`; 13 acceptance tests | **verified from files** | State the failed gate and retain all five models. Do not relabel a lowest-RMSE failure as validated. |
| C26 | Registry point estimates across the five forecast models span −33.7% to +12.8% | specification sensitivity | `REGISTRY_TREND_SENSITIVITY_SUMMARY.csv` | **verified from files, descriptive** | Call this an all-model **point-estimate specification envelope**, not a confidence set, identified set, or causal bound. |
| C27 | The sensitivity exercise rules out a Mexico-sized 49% decline | cross-design causal comparison | C25--C26 plus model-specific intervals | **false design-wide** | The decline is outside the locked/global-linear intervals but inside the seasonal-level interval [−54.7%, −0.3%]. Use Mexico only as contextual scale. |
| C28 | The inverse-RMSE-squared ensemble estimates +3.0% | model averaging | `REGISTRY_TREND_SENSITIVITY_SUMMARY.csv` | **verified from files, descriptive** | Report as the frozen-weight point estimate only; no ensemble interval was prespecified, and failed component calibration prevents causal elevation. |
| C29 | Eliminating child, early, and forced marriage is SDG Target 5.3 | international policy | official UN DESA Goal 5 page; `references/SOURCES.csv` | **verified externally** | State the target. The earlier unsupported “more than fifty countries” count was removed rather than approximated. |
| C30 | Judicial authorization requests/refusals are not publicly available | data availability | CNJ DataJud documentation; CPC art. 189; `DATAJUD_CLASS_143_PUBLIC_PROBE.csv` | **false as an unqualified statement** | A relevant public process class exists, but it excludes secret cases and lacks a complete, reliable pre-2019 age-specific series. Say that no research-ready public file was found. |
| C31 | Public DataJud class 143 can test pre-law judicial tightening | mechanism/identification | 27-court aggregate probe; Resolutions 331/2020 and 437/2021 | **not supported** | Public API is audit-only: 94.1% of 3,574 records have post-snapshot dates, the class conflates age/consent, and only three courts have plausible 2019 records. Seek secrecy-inclusive aggregates. |
| C32 | Restricted IBGE Registry files may contain exact celebration/birth dates and residence | data availability | 2009 RC manual; 2022 RC.2 questionnaire; IBGE confidentiality and SAR manuals | **verified as collected and access-route eligible; annual retention not yet verified** | State that the instrument collects the fields and SAR is the documented access route. Do not claim that every 2013--2024 analytical file is complete until IBGE confirms it. |
| C33 | Exact Registry microdata would by themselves create a conventional RD | identification | event-only data structure; `ADMINISTRATIVE_DATA_FEASIBILITY_2026-09-02.md` | **false** | Use an age-by-calendar difference in discontinuities for event rates only with a compatible risk-set denominator and continuity diagnostics. |
| C34 | The restricted Registry redesign is locally ready for external transmission | feasibility | `REGISTRY_SAR_R0_RESULTS.md`; 30 acceptance checks; output manifest | **verified from files** | State `LOCAL_READY_EXTERNAL_PENDING`. Do not translate local readiness into data access, field availability, or causal validity. |
| C35 | Public counts establish adequate power for the exact-date design | precision | `REGISTRY_SAR_R0_POWER_ENVELOPE.csv` | **provisional only** | Report the base 19.09% and stress 25.88% decline MDEs as planning screens. Exact-window counts and final inference must be revalidated inside the SAR. |
| C36 | The PNADC package is a directly observed exact-day risk set | measurement | `REGISTRY_SAR_R0_PNADC_EXPOSURE.csv`; denominator audit | **false** | It is a precise national quarterly stock converted to person-time under an explicit smooth within-age allocation. Retain survey uncertainty and validate the approximation. |
| C37 | The synthetic PPML result supports a reform effect | causal | `REGISTRY_SAR_R0_SYNTHETIC_RECOVERY.csv` | **false** | The known IRR of 0.60 is a software-recovery test only and is prohibited from substantive exhibits. |
| C38 | The daily SINASC primary sample contains 126,138 births and 1,342 married outcomes | data/measurement | `SINASC_DAILY_PRIMARY.csv`; G0/G3 sample audits | **verified from files** | State that these are observed singleton live births within 90 days of age 16 in 2016--2018 and 2022--2024. Do not generalize to all adolescents. |
| C39 | The daily age-16 estimate is +0.342 p.p., CI [−0.140,+0.824], p=0.164 | local contrast | `SINASC_DAILY_PRIMARY.csv` | **verified from files** | Call it the post-minus-pre change in recorded married-status jump. The estimate is inconclusive and is not a causal effect. |
| C40 | The daily design precisely establishes no local response | causal/equivalence | `SINASC_DAILY_PRIMARY.csv`: MDE80 0.688; 90% interval crosses the ±0.25 margin | **false** | Say the data do not distinguish zero from policy-relevant local changes. |
| C41 | The delay-sensitive estimate is +0.323 p.p., CI [−0.318,+0.964], Holm p=0.328 | local contrast | `SINASC_DAILY_PRIMARY.csv` | **verified from files** | Report as a secondary profile contrast. It cannot replace the primary jump or rescue a gate. |
| C42 | Thirteen daily sensitivities are positive, +0.148 to +0.356 p.p. | specification sensitivity | `SINASC_DAILY_SENSITIVITY.csv` | **verified from files** | Report the full range with the primary result; consistency of signs does not establish the counterfactual or causality. |
| C43 | Daily density and predetermined composition validate the full causal design | identification | G1 audit | **overstated** | G1 passes its frozen hard-failure rules only. It supports local comparability at the birthday, not stability of the age-16 jump across eras or absence of birth selection. |
| C44 | Daily placebo tests pass because none rejects | identification | `SINASC_DAILY_PLACEBOS.csv`; G2 gate | **false** | The placebo family does not reject, but no 90% interval establishes equivalence within ±0.25 p.p.; G2 is qualified. |
| C45 | Exact-age SINASC can replace the failed Registry counterfactual | design hierarchy | daily protocol and G3 gate | **false** | The protocol is post-result and mechanically says `DO_NOT_ADVANCE_AS_CAUSAL_CORE`; report it as complementary local evidence only. |
| C46 | Synthetic R0 records contribute to a manuscript estimate or exhibit | provenance | `paper/main.tex`; `paper/check_consistency.R`; Table 14 exporter input list | **false and mechanically prohibited** | Every manuscript result must trace to observed Registry, PNADC, SINASC, or DHS data. Software-test artifacts remain outside the paper. |

## Current canonical Registry trend-sensitivity numbers

The canonical source is the CSV set generated by
`src/24_analyze_registry_trend_sensitivity.R` under the two locked protocol hashes
recorded in `IDENTIFICATION_GATE.md`:

- calibration gate: **failed**, zero qualified or strong candidates;
- global linear (rank 1): RMSE 0.131; +2.0%, interval [−17.6%, +23.4%], p=0.853;
- local linear, 12 quarters: RMSE 0.156; +1.1%, interval [−14.4%, +18.8%];
- local linear, 16 quarters: RMSE 0.157; +10.1%, interval [−10.8%, +37.0%];
- global quadratic: RMSE 0.243; +12.8%, interval [−13.6%, +48.3%];
- seasonal level (rank 5): RMSE 0.391; −33.7%, interval [−54.7%, −0.3%];
- inverse-RMSE-squared ensemble: +3.0% (point only);
- all-model point envelope: [−33.7%, +12.8%] (not a causal bound).

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

## Current canonical exact-age SINASC numbers

The canonical sources are the frozen G0--G3 audit files and the CSVs generated by
`src/33_sinasc_daily_gate_g3.R`, validated by
`src/34_validate_sinasc_daily_gate_g3.R`:

- sample: 126,138 observed singleton live births, 1,342 recorded-married outcomes,
  5,183 municipality clusters, and 2,192 exact-date clusters;
- G0 `PASS`; G1 `PASS`; G2 `QUALIFIED`; G3 `INCONCLUSIVE`;
- primary `TAU`: +0.342 p.p., SE 0.246, CI95 [−0.140,+0.824], p=0.164,
  MDE80 0.688 p.p.;
- `DELAY90`: +0.323 p.p., CI95 [−0.318,+0.964], Holm p=0.328;
- temporal placebo: −0.280 p.p., CI90 [−0.725,+0.165], not equivalent;
- placebo ages 15/17/19: −0.027/+0.054/−0.064 p.p.; none rejects after Holm and none
  establishes 90% equivalence within ±0.25 p.p.;
- all 13 frozen sensitivity rows identify and span +0.148 to +0.356 p.p.;
- causal-core decision: `DO_NOT_ADVANCE_AS_CAUSAL_CORE`.

`src/39_export_sinasc_daily_paper.R` reads only these observed-data outputs and creates
`TABLE_14_SINASC_DAILY_DESIGN.tex`. The manuscript consistency check rejects named R0
software-test artifacts if they enter `paper/main.tex`.
