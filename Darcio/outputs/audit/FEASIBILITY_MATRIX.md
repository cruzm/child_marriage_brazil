# Feasibility matrix

Finalized: 2026-09-02T03:15:51-0300

| Condition found | Implementation | Status |
|---|---|---|
| Registry with annual age + PNADC quarterly post-2019 | Quarterly age-based DiD using registration-quarter; annual and monthly-registration sensitivities | Implementable |
| Registry dates of birth and marriage | No exact-age local RD; retain aggregate design | Blocked |
| PNADC annual first visit lacks 2020–2021 | Quarterly PNADC supplies all quarters; annual robustness does not interpolate gaps | Resolved for primary |
| Quarterly UF denominators exceed maximum CV ceiling | Aggregate numerator and denominator to region; Brazil sensitivity | Implementable |
| Behavioral union cells rare by geography/sex | Brazil combined primary; sex and region heterogeneity only with intervals/power warnings | Limited |
| Registry month is registration, not occurrence | Interpret quarterly timing as registration timing; annual robustness | Limited |
| Municipality unsupported | No municipal estimates | Blocked |
| Registry has exact 15–19 and a single <15 category | Rates at 15–19; <15 counts/shares only | Implementable/limited |
| Same-sex Registry variables available | Include two spouse contributions consistently | Implementable |
| Stable dwelling but no person-longitudinal key | Repeated cross-sections; no transition causal estimand | Blocked |
| No post-2019 Registry period | Not found: Registry extends through 2024 | Implementable |
| No post-2019 population denominator | Not found: quarterly PNADC covers 2019T2–2024T4 | Implementable |

