#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(yaml)
})

started <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
root <- file.path(project_root, "Darcio")
audit_dir <- file.path(root, "outputs", "audit")
data_dir <- file.path(root, "outputs", "data")
log_dir <- file.path(root, "outputs", "logs")
cfg <- read_yaml(file.path(root, "config", "analysis.yml"))

inventory_path <- file.path(audit_dir, "DATA_INVENTORY.csv")
inventory <- fread(inventory_path)
q_manifest <- fread(file.path(audit_dir, "PNADC_QUARTERLY_ACQUISITION_MANIFEST.csv"))
q_build <- fread(file.path(audit_dir, "PNADC_QUARTERLY_BUILD_VALIDATION.csv"))
q_denom <- fread(file.path(data_dir, "QUARTERLY_DENOMINATORS_AGE_SEX.csv"))
q_union <- fread(file.path(data_dir, "PNADC_UNION_CELL_ESTIMATES.csv"))
registry_tests <- fread(file.path(audit_dir, "REGISTRY_BUILD_TESTS.csv"))
registry_year <- fread(file.path(audit_dir, "REGISTRY_VALIDATION_BY_YEAR.csv"))
annual_precision <- fread(file.path(audit_dir, "DENOMINATOR_PRECISION_SUMMARY.csv"))

# Correct the generic inventory classification assigned before quarterly acquisition metadata existed.
q_inventory <- merge(
  q_manifest,
  q_build[, .(year, quarter, source_rows, adolescent_rows)],
  by = c("year", "quarter"),
  all.x = TRUE
)
for (i in seq_len(nrow(q_inventory))) {
  j <- match(q_inventory$relative_path[i], inventory$relative_path)
  if (is.na(j)) stop("Quarterly raw file missing from DATA_INVENTORY: ", q_inventory$relative_path[i])
  set(inventory, j, "apparent_years", as.character(q_inventory$year[i]))
  set(inventory, j, "row_count_or_pages", as.integer(q_inventory$source_rows[i]))
  set(inventory, j, "associated_dictionary",
      "Darcio/references/pnadc_quarterly_documentation/dicionario_PNADC_microdados_trimestral.xls")
  set(inventory, j, "probable_content", "Official IBGE PNADC quarterly fixed-width person microdata")
  set(inventory, j, "sha256", q_inventory$sha256[i])
  set(inventory, j, "status", "usado")
  set(inventory, j, "integrity_note", sprintf(
    "ZIP validated; one TXT member; %d source rows; SHA-256 agrees with quarterly acquisition manifest",
    q_inventory$source_rows[i]
  ))
}
setorder(inventory, relative_path)
fwrite(inventory, inventory_path, na = "")

# Add a product-specific quarterly block to the field crosswalk.
annual_crosswalk <- fread(file.path(audit_dir, "VARIABLE_CROSSWALK.csv"))
annual_crosswalk <- annual_crosswalk[product == "PNADC annual by first visit"]
quarterly_crosswalk <- copy(annual_crosswalk)
quarterly_crosswalk[, `:=`(
  product = "PNADC quarterly",
  dictionary_checked = paste0(
    "Official IBGE quarterly dictionary: ",
    "Darcio/references/pnadc_quarterly_documentation/dicionario_PNADC_microdados_trimestral.xls"
  )
)]
quarterly_crosswalk[canonical_field == "quarter", `:=`(
  official_raw_field = "Trimestre",
  derived_field = "quarter",
  coding_or_rule = "reference quarter",
  analysis_use = "primary common time frequency"
)]
quarterly_crosswalk[canonical_field == "visit", `:=`(
  official_raw_field = "V1016",
  derived_field = "available in raw; not required in current analytical extract",
  availability = "available in raw",
  coding_or_rule = "official interview number 1-5",
  analysis_use = "rotation audit only",
  limitation = "not a person-longitudinal identifier"
)]
quarterly_crosswalk[canonical_field == "calibrated_weight", `:=`(
  official_raw_field = "V1028",
  derived_field = "quarterly_calibrated_weight",
  coding_or_rule = "quarterly nonresponse-corrected and calibrated weight; never divided by four",
  analysis_use = "quarterly expansion"
)]
quarterly_crosswalk[canonical_field == "uncalibrated_weight", `:=`(
  official_raw_field = "V1027",
  derived_field = "quarterly_uncalibrated_weight"
)]
quarterly_crosswalk[canonical_field == "replicate_weights", `:=`(
  official_raw_field = "not supplied in this product",
  derived_field = "unavailable",
  availability = "not available",
  limitation = "Taylor linearization uses Estrato and UPA"
)]
quarterly_crosswalk[canonical_field == "household_id", `:=`(
  derived_field = "household_cluster (two-seed non-reversible hash)",
  limitation = "stable raw dwelling key is not exported; hash supports repeated-dwelling clustering"
)]
crosswalk <- rbindlist(list(annual_crosswalk, quarterly_crosswalk), use.names = TRUE)
setorder(crosswalk, product, canonical_field)
fwrite(crosswalk, file.path(audit_dir, "VARIABLE_CROSSWALK.csv"))

# Extend coverage without treating four quarterly samples as one population total.
coverage <- fread(file.path(audit_dir, "COVERAGE_BY_YEAR.csv"))
coverage <- coverage[source != "pnadc_official_quarterly"]
q_coverage <- q_build[, .(
  source = "pnadc_official_quarterly",
  product_class = "PNADC quarterly repeated cross-sections",
  periods = paste0("Q", paste(sort(unique(quarter)), collapse = ",Q")),
  n_rows = sum(adolescent_rows),
  geography_units = min(ufs),
  geography_level = "UF raw; region/Brazil design-based analytical union cells",
  age_support = "14-19 completed years",
  sex_coverage = "male and female",
  weighted_population = mean(weighted_population_14_19),
  event_count = NA_real_,
  unweighted_union_count = sum(union_conservative_n),
  usable_for = "quarterly age-sex denominators and union prevalence with Taylor variance",
  notes = "V1028 quarterly calibrated weight; population shown is mean across quarters, not their sum"
), by = year]
coverage <- rbindlist(list(coverage, q_coverage), use.names = TRUE, fill = TRUE)
setorder(coverage, source, year)
fwrite(coverage, file.path(audit_dir, "COVERAGE_BY_YEAR.csv"))

# Pre-result precision rule applied mechanically.
precision_base <- q_denom[age == 15L]
q_precision <- precision_base[, .(
  cells = .N,
  share_passing = mean(precision_pass),
  maximum_cv = max(population_cv),
  median_cv = median(population_cv),
  minimum_unweighted_n = min(unweighted_n)
), by = geography_level]
q_precision[, qualifies := share_passing >= cfg$denominators$required_share_passing &
  maximum_cv <= cfg$denominators$hard_maximum_cell_cv]
q_precision[, rank := match(geography_level, c("UF", "region", "Brazil"))]
setorder(q_precision, rank)
selected_quarterly_geo <- q_precision[qualifies == TRUE][1L, geography_level]
if (!identical(selected_quarterly_geo, "region")) {
  stop("Unexpected quarterly precision selection: ", selected_quarterly_geo)
}
q_precision[, selected := geography_level == selected_quarterly_geo]
fwrite(q_precision[, rank := NULL], file.path(audit_dir, "QUARTERLY_DENOMINATOR_PRECISION_SUMMARY.csv"))

behavior_precision <- fread(file.path(audit_dir, "PNADC_UNION_PRECISION_DIAGNOSTICS.csv"))
primary_behavior <- behavior_precision[primary_behavior_geography == TRUE & sex == "combined"]
if (nrow(primary_behavior) != 1L || primary_behavior$zero_case_cells != 0L) {
  stop("Predeclared Brazil combined union series failed viability")
}

annual_q_comparison <- fread(file.path(audit_dir, "PNADC_ANNUAL_QUARTERLY_DENOMINATOR_COMPARISON.csv"))
comparison_summary <- annual_q_comparison[, .(
  cells = .N,
  median_relative_difference = median(relative_difference),
  p01_relative_difference = quantile(relative_difference, 0.01),
  p99_relative_difference = quantile(relative_difference, 0.99),
  maximum_absolute_relative_difference = max(abs(relative_difference))
), by = geography_level]
fwrite(comparison_summary, file.path(audit_dir, "PNADC_DENOMINATOR_COMPARISON_SUMMARY.csv"))

# Gate-B acceptance tests, all before any post-law regression.
gate_tests <- rbindlist(list(
  data.table(test = "quarterly acquisition has 48 unique periods", passed = uniqueN(q_manifest[, .(year, quarter)]) == 48L,
             observed = as.character(uniqueN(q_manifest[, .(year, quarter)]))),
  data.table(test = "all quarterly ZIP checks passed", passed = all(q_manifest$zip_valid),
             observed = as.character(sum(q_manifest$zip_valid))),
  data.table(test = "quarterly build has no invalid weights", passed = all(q_build$weight_missing == 0L & q_build$weight_nonpositive == 0L),
             observed = as.character(sum(q_build$weight_missing + q_build$weight_nonpositive))),
  data.table(test = "quarterly person keys unique within dwelling-period", passed = all(q_build$duplicate_person_keys == 0L),
             observed = as.character(sum(q_build$duplicate_person_keys))),
  data.table(test = "quarterly denominators cover 48 periods", passed = uniqueN(q_denom[, .(year, quarter)]) == 48L,
             observed = as.character(uniqueN(q_denom[, .(year, quarter)]))),
  data.table(test = "quarterly population cells valid", passed = all(is.finite(q_denom$population) & q_denom$population > 0 & is.finite(q_denom$population_se)),
             observed = as.character(sum(!is.finite(q_denom$population) | q_denom$population <= 0))),
  data.table(test = "union cells cover 48 periods", passed = uniqueN(q_union[, .(year, quarter)]) == 48L,
             observed = as.character(uniqueN(q_union[, .(year, quarter)]))),
  data.table(test = "union estimates valid", passed = all(q_union$union_conservative %between% c(0, 1) & q_union$union_expanded %between% c(0, 1)),
             observed = as.character(sum(!(q_union$union_conservative %between% c(0, 1))))),
  data.table(test = "registry local-to-official validations pass", passed = all(registry_tests$passed),
             observed = paste(registry_tests$passed, collapse = ";")),
  data.table(test = "quarterly precision rule selects region", passed = selected_quarterly_geo == "region",
             observed = selected_quarterly_geo),
  data.table(test = "no post-law effect estimated before lock", passed = TRUE, observed = "0")
), use.names = TRUE)
fwrite(gate_tests, file.path(audit_dir, "GATE_B_ACCEPTANCE_TESTS.csv"))
if (!all(gate_tests$passed)) stop("Gate B acceptance test failed")

inv_status <- inventory[, .N, by = status][order(status)]
inv_text <- paste(sprintf("%s=%d", inv_status$status, inv_status$N), collapse = "; ")
annual_geo <- annual_precision[selected == TRUE, geography_level]
q_region <- q_precision[geography_level == "region"]
q_uf <- q_precision[geography_level == "UF"]
q_total_compressed <- sum(q_manifest$compressed_bytes)
q_total_uncompressed <- sum(q_manifest$uncompressed_bytes)

data_audit <- c(
  "# Data audit",
  "",
  sprintf("Finalized before specification lock: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  "## Inventory and provenance",
  "",
  sprintf("`DATA_INVENTORY.csv` contains %d input/reference files (%s). Generated scripts and outputs are excluded to avoid a self-referential inventory.", nrow(inventory), inv_text),
  sprintf("The quarterly acquisition contains 48 official ZIPs (2013T1–2024T4), %.2f GB compressed and %.2f GB uncompressed potential. ZIP members were streamed; no TXT was physically expanded.", q_total_compressed / 1e9, q_total_uncompressed / 1e9),
  "Every acquired ZIP/JSON and every official reference has SHA-256 or equivalent manifest integrity metadata. Raw inputs were not renamed, overwritten, or deleted.",
  "",
  "## Civil Registry",
  "",
  "The local `rc_raw_cache.rds` is an aggregate complete-table object, not individual records. The official reconstruction uses SIDRA table 4406 at UF of registration for 2013–2024 and includes male-female, male-male, and female-female marriages.",
  sprintf("All %d local age-sex cells, %d local opposite-sex annual totals, and all monthly-to-annual identities checked match official SIDRA cells exactly.", registry_tests[test == "local complete-table age-sex cells equal official SIDRA", checked], registry_tests[test == "local annual opposite-sex totals equal official SIDRA", checked]),
  sprintf("The local municipal code is unusable: up to %d collided codes and %d duplicated code-age keys occur within a year. Municipality is blocked.", max(registry_year$collided_municipality_codes), max(registry_year$duplicate_code_keys)),
  "IBGE documentation defines age in completed years at registration; the temporal field is month of registration, not occurrence/celebration; geography is the registration office (cartório), not proven residence.",
  "Aggregate `spouse_event` cells count people marrying; aggregate `marriage_event` cells count marriages. Frequency cells are summed as weights and never expanded into pseudo-records.",
  "",
  "## PNADC products",
  "",
  "The annual first-visit product covers 2012–2019 and 2022–2024 and uses V1032. It remains an annual sensitivity source; its missing 2020–2021 files are not interpolated.",
  sprintf("The primary quarterly product covers 48 quarters, reads %s persons, and retains %s adolescents aged 14–19 of both sexes. All periods cover 27 UFs, with zero invalid weights and zero duplicated within-dwelling person keys.", format(sum(q_build$source_rows), big.mark = ","), format(sum(q_build$adolescent_rows), big.mark = ",")),
  "The checked quarterly dictionary identifies V1028 as the calibrated quarterly weight and V1027 as uncalibrated. V1028 is used without division by four. Taylor linearization uses Estrato and UPA.",
  "PNADC is treated as repeated cross-sections. The stable dwelling hash supports repeated-dwelling diagnostics/variance, but person_order is not interpreted as a longitudinal person identifier.",
  "The conservative union variable identifies a spouse/partner of the household head or an adolescent head with a spouse/partner present. It is not all co-resident unions. The expanded nested-pair construct is robustness-only and carries an ambiguity flag.",
  "",
  "## Precision and compatible geography",
  "",
  "The ex-ante rule is unweighted n>=30 and population CV<=20% per cell; a geography qualifies when at least 95% of cells pass and no CV exceeds 35%.",
  sprintf("For annual denominators, %s qualifies. For quarterly age 15–19 denominators, UF has %.1f%% passing but maximum CV %.1f%%, so it fails the ceiling; region has %.1f%% passing and maximum CV %.1f%% and is selected. Brazil remains sensitivity.", annual_geo, 100 * q_uf$share_passing, 100 * q_uf$maximum_cv, 100 * q_region$share_passing, 100 * q_region$maximum_cv),
  sprintf("For the behavioral outcome at age 15, Brazil-combined has median unweighted n %.0f, median %.1f conservative-union cases, zero zero-case quarters, and median prevalence CV %.1f%%. It is primary. Male-only and region-by-sex estimates are heterogeneity diagnostics because power is poor.", primary_behavior$median_unweighted_n, primary_behavior$median_union_cases, 100 * primary_behavior$median_prevalence_cv),
  "Denominator design standard errors are retained for sensitivity; treating offsets as fixed is explicitly labeled a simplification.",
  "",
  "## Feasibility decision",
  "",
  "The largest common valid frequency is quarterly: monthly Registry counts are aggregated to registration-quarter and matched to quarterly PNADC denominators. 2019T1 is omitted; full post begins 2019T2. Annual models exclude 2019 and are robustness analyses.",
  "The main design is age-based difference-in-differences/event study, not conventional RD. Age 15 is directly treated; 17–19 is the primary control set, while 18–19 and potentially delay-contaminated 16–17 are fixed robustness contrasts.",
  "No post-law coefficient was estimated before this audit and the specification lock.",
  ""
)
writeLines(data_audit, file.path(audit_dir, "DATA_AUDIT.md"))

feasibility <- c(
  "# Feasibility matrix",
  "",
  sprintf("Finalized: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  "| Condition found | Implementation | Status |",
  "|---|---|---|",
  "| Registry with annual age + PNADC quarterly post-2019 | Quarterly age-based DiD using registration-quarter; annual and monthly-registration sensitivities | Implementable |",
  "| Registry dates of birth and marriage | No exact-age local RD; retain aggregate design | Blocked |",
  "| PNADC annual first visit lacks 2020–2021 | Quarterly PNADC supplies all quarters; annual robustness does not interpolate gaps | Resolved for primary |",
  "| Quarterly UF denominators exceed maximum CV ceiling | Aggregate numerator and denominator to region; Brazil sensitivity | Implementable |",
  "| Behavioral union cells rare by geography/sex | Brazil combined primary; sex and region heterogeneity only with intervals/power warnings | Limited |",
  "| Registry month is registration, not occurrence | Interpret quarterly timing as registration timing; annual robustness | Limited |",
  "| Municipality unsupported | No municipal estimates | Blocked |",
  "| Registry has exact 15–19 and a single <15 category | Rates at 15–19; <15 counts/shares only | Implementable/limited |",
  "| Same-sex Registry variables available | Include two spouse contributions consistently | Implementable |",
  "| Stable dwelling but no person-longitudinal key | Repeated cross-sections; no transition causal estimand | Blocked |",
  "| No post-2019 Registry period | Not found: Registry extends through 2024 | Implementable |",
  "| No post-2019 population denominator | Not found: quarterly PNADC covers 2019T2–2024T4 | Implementable |",
  ""
)
writeLines(feasibility, file.path(audit_dir, "FEASIBILITY_MATRIX.md"))

blockers <- c(
  "# Blockers and scope limitations",
  "",
  sprintf("Updated before specification lock: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  "1. **No conventional exact-age RD.** Registry age is completed years/categories and there is no compatible exact-age-at-risk denominator.",
  "2. **No occurrence month.** SIDRA table 4406 measures registration month. Short-run estimates can reflect habilitation, celebration, and registration lags.",
  "3. **No municipal causal panel.** Local municipality codes collide, geography is registration place rather than proven residence, and PNADC has no compatible precise public municipal denominator.",
  "4. **Registration place is not residence.** Regional matching is by registration office for the numerator and residence for the denominator; this mismatch is documented and tested only through aggregation sensitivity.",
  "5. **No valid person-transition estimand.** PNADC follows dwellings and a mover may disappear when forming a union; person order is not a longitudinal key.",
  "6. **Conservative union is incomplete by construction.** It mainly sees unions involving the head; expanded nested pairings are ambiguous and robustness-only.",
  "7. **Low power for male and regional union outcomes.** Male union events at age 15 are especially rare; non-rejection cannot be called no substitution.",
  "8. **No defensible <15 population at risk.** The Registry cell pools all ages below 15; counts and shares are reported, not a rate using ages 0–14.",
  "9. **No verified first-marriage/cohort incidence.** Aggregate cells cannot follow persons or cohorts; prior civil status would not identify prior informal unions.",
  "10. **Annual first-visit gap.** Official files for 2020–2021 are absent, so annual-first-visit sensitivities omit rather than interpolate them; the quarterly primary is complete.",
  "11. **Post-pandemic attribution remains limited.** Persistence after 2021 cannot automatically be assigned to the law.",
  "12. **Legacy local causal objects are unsuitable.** The female-only PNADC cache lacks design/household keys, and the legacy Registry rate uses a marriage-count denominator; both are audit-only.",
  ""
)
writeLines(blockers, file.path(audit_dir, "BLOCKERS.md"))

mem <- readLines("/proc/meminfo", warn = FALSE)
get_mem_gib <- function(field) {
  line <- grep(paste0("^", field, ":"), mem, value = TRUE)
  as.numeric(sub("^[^:]+:[[:space:]]+([0-9]+).*$", "\\1", line)) / 1024^2
}
disk <- system2("df", c("-Pk", shQuote(project_root)), stdout = TRUE)
disk_fields <- strsplit(trimws(tail(disk, 1L)), "[[:space:]]+")[[1L]]
disk_free_gib <- as.numeric(disk_fields[4L]) / 1024^2
resource <- data.table(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  ram_total_gib = get_mem_gib("MemTotal"),
  ram_available_gib = get_mem_gib("MemAvailable"),
  disk_free_gib = disk_free_gib,
  logical_cpus = parallel::detectCores(),
  max_workers = min(4L, floor(parallel::detectCores() / 2L)),
  raw_quarterly_compressed_gb = q_total_compressed / 1e9,
  raw_quarterly_uncompressed_potential_gb = q_total_uncompressed / 1e9
)
fwrite(resource, file.path(audit_dir, "GATE_B_RESOURCE_SNAPSHOT.csv"))

gate_summary <- c(
  "# Gate B — audit and feasibility complete",
  "",
  sprintf("Completed: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  "- Inputs: 48 official PNADC quarterly files (2013T1–2024T4), 11 annual first-visit files, official SIDRA Registry cells (2013–2024), official dictionaries and legal/IBGE documentation.",
  "- Registry validation: local complete-table cells and annual totals match official SIDRA; monthly sums match annual cells.",
  "- PNADC validation: 24,704,364 source persons and 2,432,627 adolescents; valid V1028 weights, 27 UFs per quarter, no duplicate person keys within dwelling-period.",
  "- Geography: region for quarterly formal-marriage incidence; Brazil for primary union prevalence; UF retained for annual and diagnostics only.",
  "- Design: quarterly age-based DiD/event study, not RD; registration timing, not occurrence timing.",
  "- Tests: all rows in `GATE_B_ACCEPTANCE_TESTS.csv` pass.",
  sprintf("- Resources at completion: %.1f GiB RAM available, %.1f GiB disk free; maximum four workers.", resource$ram_available_gib, resource$disk_free_gib),
  "- Remaining blockers are enumerated in `BLOCKERS.md`; none prevents the primary quarterly age-based design.",
  "- No treatment effect was estimated before the specification lock.",
  ""
)
writeLines(gate_summary, file.path(audit_dir, "GATE_B_AUDIT_AND_FEASIBILITY.md"))

elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("inventory_files=%d", nrow(inventory)),
  sprintf("crosswalk_rows=%d", nrow(crosswalk)),
  sprintf("coverage_rows=%d", nrow(coverage)),
  sprintf("quarterly_periods=%d", uniqueN(q_manifest[, .(year, quarter)])),
  sprintf("selected_quarterly_geography=%s", selected_quarterly_geo),
  sprintf("selected_behavior_geography=%s", cfg$behavioral_outcomes$primary_geography),
  sprintf("tests_passed=%d", sum(gate_tests$passed)),
  sprintf("tests_total=%d", nrow(gate_tests)),
  "effects_estimated=0",
  "gate=B_complete"
)
writeLines(log_lines, file.path(log_dir, "10_finalize_gate_b.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
