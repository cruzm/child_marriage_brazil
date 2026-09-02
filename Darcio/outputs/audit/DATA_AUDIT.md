# Data audit

Finalized before specification lock: 2026-09-02T03:15:51-0300

## Inventory and provenance

`DATA_INVENTORY.csv` contains 332 input/reference files (bloqueado=3; desconhecido=53; duplicado=22; obsoleto=29; usado=225). Generated scripts and outputs are excluded to avoid a self-referential inventory.
The quarterly acquisition contains 48 official ZIPs (2013T1–2024T4), 10.23 GB compressed and 85.97 GB uncompressed potential. ZIP members were streamed; no TXT was physically expanded.
Every acquired ZIP/JSON and every official reference has SHA-256 or equivalent manifest integrity metadata. Raw inputs were not renamed, overwritten, or deleted.

## Civil Registry

The local `rc_raw_cache.rds` is an aggregate complete-table object, not individual records. The official reconstruction uses SIDRA table 4406 at UF of registration for 2013–2024 and includes male-female, male-male, and female-female marriages.
All 3780 local age-sex cells, 10 local opposite-sex annual totals, and all monthly-to-annual identities checked match official SIDRA cells exactly.
The local municipal code is unusable: up to 212 collided codes and 3604 duplicated code-age keys occur within a year. Municipality is blocked.
IBGE documentation defines age in completed years at registration; the temporal field is month of registration, not occurrence/celebration; geography is the registration office (cartório), not proven residence.
Aggregate `spouse_event` cells count people marrying; aggregate `marriage_event` cells count marriages. Frequency cells are summed as weights and never expanded into pseudo-records.

## PNADC products

The annual first-visit product covers 2012–2019 and 2022–2024 and uses V1032. It remains an annual sensitivity source; its missing 2020–2021 files are not interpolated.
The primary quarterly product covers 48 quarters, reads 24,704,364 persons, and retains 2,432,627 adolescents aged 14–19 of both sexes. All periods cover 27 UFs, with zero invalid weights and zero duplicated within-dwelling person keys.
The checked quarterly dictionary identifies V1028 as the calibrated quarterly weight and V1027 as uncalibrated. V1028 is used without division by four. Taylor linearization uses Estrato and UPA.
PNADC is treated as repeated cross-sections. The stable dwelling hash supports repeated-dwelling diagnostics/variance, but person_order is not interpreted as a longitudinal person identifier.
The conservative union variable identifies a spouse/partner of the household head or an adolescent head with a spouse/partner present. It is not all co-resident unions. The expanded nested-pair construct is robustness-only and carries an ambiguity flag.

## Precision and compatible geography

The ex-ante rule is unweighted n>=30 and population CV<=20% per cell; a geography qualifies when at least 95% of cells pass and no CV exceeds 35%.
For annual denominators, UF qualifies. For quarterly age 15–19 denominators, UF has 98.2% passing but maximum CV 71.2%, so it fails the ceiling; region has 100.0% passing and maximum CV 9.1% and is selected. Brazil remains sensitivity.
For the behavioral outcome at age 15, Brazil-combined has median unweighted n 8739, median 67.5 conservative-union cases, zero zero-case quarters, and median prevalence CV 15.7%. It is primary. Male-only and region-by-sex estimates are heterogeneity diagnostics because power is poor.
Denominator design standard errors are retained for sensitivity; treating offsets as fixed is explicitly labeled a simplification.

## Feasibility decision

The largest common valid frequency is quarterly: monthly Registry counts are aggregated to registration-quarter and matched to quarterly PNADC denominators. 2019T1 is omitted; full post begins 2019T2. Annual models exclude 2019 and are robustness analyses.
The main design is age-based difference-in-differences/event study, not conventional RD. Age 15 is directly treated; 17–19 is the primary control set, while 18–19 and potentially delay-contaminated 16–17 are fixed robustness contrasts.
No post-law coefficient was estimated before this audit and the specification lock.

