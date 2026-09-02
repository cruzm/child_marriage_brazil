# Estimands and specifications — frozen before effect estimation

Frozen: 2026-09-02T00:56:08-03:00  
Lock version: 1.0.0  
Random seed: 13811  
Post-reform coefficients inspected before this document: **no**

This document fixes the confirmatory analysis before opening any coefficient that compares the post-law period with the pre-law period. Descriptive validation totals used in the data audit are not treatment-effect estimates. Machine-readable details are in `config/specification_lock.yml`; any later change must be entered in `outputs/analysis/SPECIFICATION_AMENDMENTS.md` before re-estimation and may be justified only by a documented data error or technical impossibility.

## 1. Legal intervention and claims kept separate

Lei nº 13.811/2019 was published and took effect on 13 March 2019. It amended Civil Code art. 1.520 and removed the exceptions that had permitted civil marriage below the idade núbil. It did **not** prohibit every marriage below age 18: under art. 1.517, people aged 16 or 17 remained subject to parental or legal-representative authorization.

The direct age-eligibility contrast is therefore age 15 versus older ages, not “under 18” versus adults. Four claims will never be collapsed into one:

1. civil registrations involving people below 16 fell;
2. formal marriage was postponed to age 16 or 17;
3. formation/prevalence of unions fell;
4. unions shifted toward informal co-residence.

The Registry measures a flow of civil registrations. PNADC measures a stock of people observed in a limited class of co-resident unions. Their outcomes and coefficients will not be subtracted.

Official sources checked before the lock are the [law](https://www.planalto.gov.br/ccivil_03/_ato2019-2022/2019/lei/l13811.htm), the [compiled Civil Code](https://www.planalto.gov.br/ccivil_03/leis/2002/l10406compilada.htm), [IBGE Civil Registry documentation](https://www.ibge.gov.br/estatisticas/sociais/populacao/9110-estatisticas-do-registro-civil.html?lang=pt-BR), [SIDRA table 4406](https://sidra.ibge.gov.br/tabela/4406), and the [PNADC quarterly documentation directory](https://ftp.ibge.gov.br/Trabalho_e_Rendimento/Pesquisa_Nacional_por_Amostra_de_Domicilios_continua/Trimestral/Microdados/Documentacao/). Exact titles, clean URLs, access dates, local copies, and verification notes are recorded in `references/SOURCES.csv`.

## 2. Hierarchy of estimands

### 2.1 Primary estimand

The primary estimand is the short-run change attributable to the reform in civil-registration incidence at age 15:

\[
Y_{15,s,t}=100{,}000\times
\frac{\text{people of sex }s\text{ and age 15 in marriages registered in }t}
{\text{resident population of sex }s\text{ and age 15 in }t}.
\]

The predesignated primary population is both sexes combined. Female and male estimates are confirmatory and use exactly the same specification. The primary post window is 2019T2–2019T4; 2019T1 is omitted because it is partly pre-law and partly post-law.

The estimand concerns civil registrations at age 15. It is not, without additional evidence, the effect on all unions or on individual lifetime marriage probability.

### 2.2 Confirmatory and mechanism estimands

| Object | Unit | Status and interpretation |
|---|---:|---|
| Registered people aged 16, 17, 18, or 19 | per 100,000 same-age residents | Postponement/placebo contrasts; ages 16–17 may be contaminated by delay |
| Marriages with at least one spouse below 16 | count and share of registered marriages | Annual corroboration; no untreated geographic unit |
| Marriages with at least one spouse below 15 | count and share | No pooled 0–14 denominator is fabricated |
| Total registered marriages | per 100,000 total residents | Annual, strongly diluted descriptive secondary outcome |
| Aggregate recapture | excess people at 16–17 / absolute deficit at 15 | Aggregate accounting object, never the same individuals |

The Registry’s “below 15” category is not decomposed into invented ages. Because no substantively defensible matching risk population exists, it receives no rate.

### 2.3 Behavioral estimands

The behavioral primary outcome is quarterly prevalence of `union_conservative` at age 15 in Brazil. It equals one only when the adolescent is the household head’s spouse/partner or is the head and a spouse/partner is present. It therefore does not measure every union inside a household.

`union_expanded`, which adds plausible child/stepchild and son/daughter-in-law pairings, is robustness-only and retains an ambiguity flag. The equivalence margin is fixed at ±0.50 percentage point. Non-rejection of zero will not be called evidence of no substitution unless the confidence interval also satisfies the equivalence criterion and the power calculation is adequate.

## 3. Data and compatibility decisions fixed by Gate B

### 3.1 Civil Registry

Official SIDRA table 4406 supplies aggregate frequency cells for 2013–2024, including opposite-sex and both same-sex compositions. Each spouse contributes once to their own age-by-sex numerator. Marriage-level cells remain separate from person-level cells.

Age is completed age **at registration**. Time is month/quarter **of registration**, not occurrence or celebration. Geography is the registration office, not verified residence. These limitations must appear in every result note.

### 3.2 PNADC denominators

The quarterly PNADC supplies 48 repeated cross-sections from 2013T1 through 2024T4. V1028 is the calibrated quarterly weight and is never divided by four. Estrato and UPA define Taylor-linearized variance. The survey follows dwellings; no person-transition causal estimand is permitted.

The precision rule was set without marriage outcomes: an age-sex-period cell passes when unweighted `n >= 30` and population CV `<= 20%`; a geographic level qualifies if at least 95% of cells pass and no cell has CV above 35%. UF fails the maximum-CV ceiling. Region is therefore the primary common geography for Registry incidence; Brazil is mandatory sensitivity. UF is allowed for annual and diagnostic work only.

For union prevalence, rare events make Brazil-combined the primary geography/population. Region and sex-specific series are reported as heterogeneity diagnostics with their full intervals and power limitations.

### 3.3 Geographic mismatch

The numerator is classified by registration office and the denominator by residence. Region reduces but cannot eliminate this mismatch. Municipality is prohibited. Sensitivity at Brazil and annual UF aggregation will be shown, and no text may silently relabel registration place as residence.

## 4. Treatment timing and fixed windows

The event-study baseline is 2018T4. 2019T1 is absent from causal post indicators. For displayed event time, 2018T4 is `k=-1` and 2019T2 is `k=0`, with the omitted partial quarter skipped.

| Window | Definition | Role |
|---|---|---|
| `short_run_clean` | 2013T1–2018T4 versus 2019T2–T4; omit 2019T1 | Primary causal summary |
| `full_dynamic` | 2013T1–2024T4; omit 2019T1; mark 2020–2021 | Dynamics, not a single persistent-law claim |
| `exclude_pandemic` | Full span excluding 2019T1 and 2020T1–2021T4 | Required robustness |
| `post_pandemic` | 2022T1–2024T4 | Cautious persistence descriptor |

Annual models exclude 2019 in the main specification. A documented fraction of 294/365 is allowed only as robustness; it is legal exposure time, not assumed compliance.

## 5. Primary Registry specification

### 5.1 Sample and comparison ages

The primary sample is region × age × quarter for ages 15 and 17–19, both sexes combined. Age 15 is treated; ages 17–19 are controls. Fixed alternatives are 18–19 and 16–17. The latter is explicitly vulnerable to treatment-induced postponement.

### 5.2 PPML summary model

Let `g` denote region, `a` age, and `t` registration-quarter. The primary short-run model is

\[
E[N_{gat}\mid X] = P_{gat}\exp\{\alpha_{ga}+\lambda_{gt}
+\mu_{a,q(t)}+\phi_a \tau_t
+\beta\,1[a=15]1[t\ge 2019T2]\},
\]

where `N` is the number of people in registered marriages and `P` is the design-based resident-population estimate used as an offset. `alpha_ga` is region × age, `lambda_gt` is region × period, `mu_a,q(t)` is age-specific quarter-of-year seasonality, and `phi_a tau_t` is an age-specific linear trend centered at 2018T4. The version with trends is primary; the otherwise identical no-trend version is mandatory.

The model is repeated unchanged for female and male samples. Any observation or fixed-effect group dropped for a nonpositive offset, separation, or collinearity is logged. Fixed effects that accidentally absorb the treatment are a test failure, not a reason to change the estimand.

The coefficient is reported as:

- rate ratio `exp(beta)`;
- percentage change `100[exp(beta)-1]`;
- population-weighted model-implied points per 100,000 in 2019T2–T4;
- predicted registrations avoided in 2019T2–T4, with confidence interval.

The primary offset treats the population estimate as fixed and is labeled a simplification. Required sensitivities aggregate to Brazil and draw 499 positive denominator realizations from the design estimate/SE before refitting.

### 5.3 Event study

The full-dynamic PPML replaces the post indicator with age-15 × observed-quarter indicators, omitting 2018T4 and leaving out 2019T1. It uses the same fixed effects, seasonality, and primary trends. Raw-rate graphs and a no-trend event study accompany it.

Pre-period diagnostics include a joint lead test, simultaneous intervals where estimable, different pre-windows, seasonality, and a bound framed as an absolute 10% rate-ratio deviation over four quarters. Failure to reject leads is never called proof of parallel trends.

### 5.4 Linear-rate robustness

The same sample/specification is estimated by population-weighted least squares on rates per 100,000. It is robustness, not a replacement selected by fit or significance.

## 6. Inference for one national reform

The many geographic cells are not independent treatments. The primary PPML covariance clusters by quarter-period, capturing common national-period shocks. Every table reports periods and clusters.

The following are all required and discrepancies are disclosed:

1. two-way clustering by region and period, prominently noting only five region clusters;
2. aggregated age-series Newey–West HAC with lag four;
3. moving-block temporal residual bootstrap, block length four, 999 replications, seed 13811;
4. pseudo-reform dates 2015T2, 2016T2, 2017T2, and 2018T2, each with three pseudo-post quarters;
5. placebo focal ages 17, 18, and 19 with control sets fixed in the YAML lock.

Randomization-inference statistics use the absolute studentized treatment coefficient and a plus-one finite-sample correction. No procedure is chosen after seeing which has the smallest standard error.

## 7. Synthetic age control

A mandatory robustness constructs a synthetic age-15 counterfactual from ages 17, 18, and 19. Weights are nonnegative and sum to one. They minimize population-weighted squared rate error using 2013T1–2017T4 only; 2018T1–T4 is untouched holdout. Post-2018 information cannot enter weights or tuning. Weights, training RMSPE, holdout RMSPE, and post gap are reported.

## 8. Delay and aggregate recapture

Age-specific mechanism contrasts are fixed as follows: 15 versus 17–19; 16 versus 18–19; 17 versus 18–19; 18 versus 17 and 19; 19 versus 17–18. They do not all have the same causal interpretation.

The short-run aggregate deficit at age 15 and excess at ages 16–17 are obtained from model counterfactual predictions. Their ratio is labeled **aggregate recapture**. A joint 999-replication temporal block bootstrap supplies the interval. The ratio is not reported if the estimated age-15 deficit is nonnegative or effectively zero, and it never implies tracking the same people.

## 9. Pre-law exposure and complementary DDD

Because the pooled below-16 Registry numerator has no compatible population at risk, geographic exposure is named `prelaw_affected_marriage_share`, not an incidence rate:

\[
Exposure_g = \frac{\text{marriages with at least one spouse below 16, 2013--2017}}
{\text{all registered marriages, 2013--2017}}.
\]

2018 is holdout. A beta-binomial empirical-Bayes adjustment is estimated using only 2013–2017 UF counts. Both raw and adjusted exposure, scaled by one pre-period standard deviation, are shown.

The complementary annual UF PPML includes UF × age, UF × year, and age × year fixed effects and `Exposure_g × 1[age=15] × Post`. Its sample combines sexes, uses ages 15 and 17–19, excludes 2019 and 2020–2021, and uses population as offset. The coefficient is a gradient with pre-law exposure, not the national average treatment effect. Differential trends, regression to the mean, and 2018 holdout prediction are mandatory diagnostics.

## 10. PNADC union specifications

### 10.1 Design-based cell analysis

Quarterly design-based prevalences and standard errors are constructed by age, sex, and geography. The primary cell model uses Brazil-combined ages 14–19 and compares age 15 with ages 17–19. It is a weighted linear-probability meta-regression with age and period fixed effects, age-specific quarter seasonality, and age-specific linear trends centered at 2018T4.

Weights are inverse design variances winsorized at the fixed 5th and 95th percentiles within outcome. Inference uses period clustering/HAC lag four and 999 normal draws from each cell estimate and design SE. The primary window is 2019T2–T4; full dynamics, pandemic exclusions, sex, region, and `union_expanded` are fixed extensions.

The report includes the estimate in percentage points, confidence interval, unweighted counts, minimum detectable effect at 80% power and 5% size, and a TOST equivalence test against ±0.50 percentage point.

### 10.2 Microdata robustness

One LPM normalizes V1028 to mean one within quarter for numerical stability and uses two-way clustering by stable dwelling hash and period. A second survey-weighted LPM uses period-prefixed strata and UPAs. Binary models are robustness-only. No transition/panel effect is estimated.

## 11. Mandatory robustness and multiplicity

Without selection by result, the pipeline runs all control sets, trend/no-trend versions, four time windows, three sex samples, PPML and weighted linear rates, quarterly and annual aggregation, region/Brazil and permitted annual-UF aggregation, raw/empirical-Bayes exposure, conservative/expanded union, denominator-uncertainty sensitivity, synthetic controls, and date/age placebos.

The single combined-sex primary estimand is unadjusted. Female and male confirmatory p-values use Holm adjustment. Ages 16–19 use Holm within the delay family. Behavioral heterogeneity is exploratory and uses Benjamini–Hochberg within family. Any unplanned analysis is labeled exploratory and cannot replace the locked estimate.

## 12. Reporting constraints

Every result must show units, sample, timing, source, zeros, absent periods, and wide intervals. Figures mark 13 March 2019/2019T1 and the 2020–2021 pandemic period consistently. Neither long-run persistence nor a post-pandemic level is automatically attributed to the law.

The conclusion about civil registration rests on the short-run age-based comparison and its honest national-time inference. Conclusions about postponement and co-resident union require their own estimates. An imprecise PNADC interval yields “indeterminate,” not “zero effect.”
