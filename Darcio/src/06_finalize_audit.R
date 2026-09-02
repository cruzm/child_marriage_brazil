#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(digest)
})

start_time <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
darcio_root <- file.path(project_root, "Darcio")
audit_dir <- file.path(darcio_root, "outputs", "audit")
data_dir <- file.path(darcio_root, "outputs", "data")
log_dir <- file.path(darcio_root, "outputs", "logs")

inventory_path <- file.path(audit_dir, "DATA_INVENTORY.csv")
inventory <- fread(inventory_path)
inventory <- inventory[!startsWith(relative_path, "Darcio/data/raw_external/") &
                         !startsWith(relative_path, "Darcio/references/")]

pnadc_manifest <- fread(file.path(audit_dir, "PNADC_EXTERNAL_ACQUISITION_MANIFEST.csv"))
registry_manifest <- fread(file.path(audit_dir, "REGISTRY_EXTERNAL_ACQUISITION_MANIFEST.csv"))
pnadc_build <- fread(file.path(audit_dir, "PNADC_OFFICIAL_BUILD_VALIDATION.csv"))

external_files <- c(
  list.files(file.path(darcio_root, "data", "raw_external"), recursive = TRUE, full.names = TRUE),
  list.files(file.path(darcio_root, "references"), recursive = TRUE, full.names = TRUE)
)
external_files <- external_files[file.info(external_files)$isdir %in% FALSE]

format_label <- function(path) {
  ext <- tolower(tools::file_ext(path))
  switch(ext,
    zip = "ZIP archive containing fixed-width TXT",
    json = "JSON",
    xls = "Excel 97-2003 workbook",
    xlsx = "Excel workbook",
    pdf = "PDF",
    txt = "plain text",
    html = "HTML directory listing",
    csv = "CSV",
    "unknown"
  )
}

reference_row_count <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext %in% c("txt", "html", "csv")) return(length(readLines(path, warn = FALSE)))
  NA_integer_
}

external_inventory <- rbindlist(lapply(external_files, function(path) {
  rel <- substring(normalizePath(path, mustWork = TRUE), nchar(project_root) + 2L)
  base <- basename(path)
  pnadc_match <- pnadc_manifest[basename(relative_path) == base]
  registry_match <- registry_manifest[basename(relative_path) == base]
  is_pnadc <- nrow(pnadc_match) == 1L
  is_registry <- nrow(registry_match) == 1L
  status <- if (is_registry) fifelse(registry_match$status == "duplicate", "duplicado", "usado") else "usado"
  if (base == "sidra_4406_query_test.json") status <- "obsoleto"
  years <- if (is_pnadc) as.character(pnadc_match$year) else if (is_registry) as.character(registry_match$year) else {
    hits <- regmatches(base, gregexpr("(19|20)[0-9]{2}", base))[[1L]]
    paste(unique(hits), collapse = ";")
  }
  rows <- if (is_pnadc) pnadc_build[year == pnadc_match$year]$source_rows else if (is_registry) registry_match$rows else reference_row_count(path)
  sha <- if (is_pnadc) pnadc_match$sha256 else if (is_registry) registry_match$sha256 else digest(path, algo = "sha256", file = TRUE)
  dictionary <- if (is_pnadc) pnadc_build[year == pnadc_match$year]$dictionary else if (grepl("PNADC_.*visita1", base, ignore.case = TRUE)) base else ""
  probable <- if (is_pnadc) "Official IBGE PNADC annual first-visit fixed-width microdata" else if (is_registry) {
    "Official IBGE SIDRA table 4406 Registry Civil cells at UF level"
  } else if (grepl("dicionario|input_PNADC", base, ignore.case = TRUE)) {
    "Official year/layout-specific PNADC dictionary or input specification"
  } else if (grepl("lei|civil|registro|pnadc|sidra|ibge", base, ignore.case = TRUE)) {
    "Official legal or IBGE documentation/source capture"
  } else "Research source registry or reference"
  integrity <- if (is_pnadc) "ZIP validated; one TXT member; SHA-256 in PNADC acquisition manifest" else if (is_registry) {
    sprintf("SIDRA header/schema/27 UFs/row count validated; zero symbols=%d; missing symbols=%d",
            registry_match$zero_symbols, registry_match$missing_symbols)
  } else "SHA-256 computed at Gate B"
  data.table(
    relative_path = rel,
    size_bytes = as.integer(file.info(path)$size),
    format = format_label(path),
    compression = if (tolower(tools::file_ext(path)) == "zip") "ZIP" else "none/unknown",
    encoding = if (tolower(tools::file_ext(path)) %in% c("json", "txt", "html", "csv")) "UTF-8/ASCII as supplied" else "",
    delimiter = if (tolower(tools::file_ext(path)) == "csv") "," else "",
    apparent_years = years,
    row_count_or_pages = as.integer(rows),
    associated_dictionary = dictionary,
    probable_content = probable,
    sha256 = sha,
    modified_time = as.POSIXct(file.info(path)$mtime, tz = "UTC"),
    status = status,
    duplicate_of = if (status == "duplicado") "year-specific validated SIDRA JSON files" else "",
    integrity_note = integrity
  )
}), use.names = TRUE, fill = TRUE)

inventory <- rbindlist(list(inventory, external_inventory), use.names = TRUE, fill = TRUE)
inventory[relative_path == "data/raw/rc_sidra_2020.rds", `:=`(
  status = "bloqueado",
  integrity_note = "Local extract has blank age labels and all values missing; official year-specific SIDRA JSON is used instead"
)]
inventory[relative_path == "data/cache/didc_pnadc_cache.rds", `:=`(
  status = "obsoleto",
  integrity_note = "Female-only audit cache without UPA, stratum, or household keys; replaced explicitly by official first-visit files"
)]
inventory[relative_path == "data/child_marriage.duckdb", `:=`(
  status = "obsoleto",
  integrity_note = "Contains Registry tables only; documented PNADC tables are absent"
)]
inventory[relative_path %in% c("data/raw/rc_sidra_2023.rds", "data/raw/rc_sidra_2024.rds"), `:=`(
  status = "duplicado",
  duplicate_of = "Darcio/data/raw_external/sidra_4406_second_age_annual_<year>.json"
)]
setorder(inventory, relative_path)
fwrite(inventory, inventory_path, na = "")

crosswalk <- data.table(
  canonical_field = c(
    "year", "quarter", "visit", "uf", "region", "public_domain", "household_id", "person_id", "upa", "stratum",
    "calibrated_weight", "uncalibrated_weight", "replicate_weights", "age", "birth_day", "birth_month", "birth_year",
    "sex", "race_color", "household_role", "school_attendance", "education_level", "worked", "hours", "earnings", "urban_rural"
  ),
  product = "PNADC annual by first visit",
  official_raw_field = c(
    "Ano", "Trimestre", "file is first-visit product", "UF", "derived from UF", "Capital/RM_RIDE/V1023",
    "UPA+V1008+V1014", "household key+V2003", "UPA", "Estrato", "V1032", "V1031", "not supplied",
    "V2009", "V2008", "V20081", "V20082", "V2007", "V2010", "V2005", "V3002", "VD3004/VD3005",
    "V4001", "VD4031", "VD4019", "V1022"
  ),
  derived_field = c(
    "year", "quarter", "implicit visit=1", "uf", "region", "capital_code/metro_code/area_type_code",
    "household_cluster (non-reversible serial)", "person_order (not a longitudinal person key)", "upa", "stratum",
    "annual_calibrated_weight", "annual_uncalibrated_weight", "unavailable", "age", "birth_day", "birth_month", "birth_year",
    "sex_code", "race_color_code", "household_role_code", "school_attendance", "education_level_code/years_education_code",
    "worked_reference_week", "usual_weekly_hours_raw", "usual_monthly_earnings_raw", "urban_rural_code"
  ),
  availability = c(rep("available", 12), "not available", rep("available", 13)),
  dictionary_checked = "Official year-specific IBGE first-visit dictionary in Darcio/references/pnadc_documentation",
  coding_or_rule = c(
    "reference year", "interview quarter within annual accumulated sample", "all files explicitly visita1", "IBGE state code",
    "UF-to-region deterministic map", "public domains only", "used transiently then raw selection keys dropped",
    "retained only as within-household order", "design PSU", "design stratum", "annual calibrated first-visit weight; never divided by 4",
    "annual uncalibrated weight", "no replicate-weight product", "completed years; no conventional RD", "invalid codes to missing",
    "invalid codes to missing", "invalid codes to missing", "1 male; 2 female", "official categories", "V2005 official categories",
    "1 yes; 2 no", "official derived codes", "1 yes; 2 no", "raw official derived code", "raw official derived code", "official code"
  ),
  analysis_use = c(
    "time", "seasonality/descriptive composition", "product classification", "primary geography", "geographic robustness",
    "heterogeneity", "union construction only", "not longitudinal", "variance", "variance", "population expansion",
    "audit only", "blocked", "treatment/control age", "exact-day feasibility audit", "birth-month audit", "birth-year audit",
    "sex strata", "heterogeneity", "union definitions", "exploratory", "exploratory", "exploratory", "exploratory", "exploratory", "heterogeneity"
  ),
  limitation = c(
    "annual common frequency", "not a quarterly cross-section weight", "household rotation product", "no municipal identifier",
    "derived", "no private municipality", "raw key not exported", "must not link persons over time", "public design identifier",
    "public design identifier", "calibrated to annual projection", "not used", "design-based SE uses Taylor linearization",
    "annual age only", "does not create exact marriage age", "does not create exact marriage age", "does not create exact marriage age",
    "none", "sample-size limits", "conservative definition misses non-head couples", "exploratory only", "layout varies by year",
    "exploratory only", "layout varies by year", "nominal/raw; not primary", "none"
  )
)
fwrite(crosswalk, file.path(audit_dir, "VARIABLE_CROSSWALK.csv"))

coverage_existing <- fread(file.path(audit_dir, "COVERAGE_BY_YEAR.csv"))
coverage_existing <- coverage_existing[!source %in% c("pnadc_official_first_visit", "registry_sidra_official", "pnadc_total_population")]
registry_people <- fread(file.path(data_dir, "REGISTRY_PERSON_EVENTS_ANNUAL.csv"))
registry_total <- fread(file.path(data_dir, "REGISTRY_TOTAL_MARRIAGES_ANNUAL.csv"))
registry_coverage <- registry_people[, .(
  source = "registry_sidra_official",
  product_class = "Registry Civil SIDRA table 4406; all couple compositions",
  year,
  periods = "annual plus 12 registration months",
  n_rows = .N,
  geography_units = uniqueN(uf_code),
  geography_level = "UF of registration office",
  age_support = "<15; exact 15-19; unknown for both spouses",
  sex_coverage = "male, female, combined; opposite- and same-sex marriages",
  weighted_population = NA_real_,
  event_count = registry_total[composition == "all" & year == .BY$year, sum(total_marriages)],
  unweighted_union_count = NA_real_,
  usable_for = "person-event numerators, affected marriages, delay/bunching, registration-month robustness",
  notes = "Age is completed years at registration; month is registration, not occurrence; location is cartorio"
), by = year]
pnadc_validation <- fread(file.path(audit_dir, "PNADC_OFFICIAL_BUILD_VALIDATION.csv"))
pnadc_coverage <- pnadc_validation[, .(
  source = "pnadc_official_first_visit",
  product_class = "PNADC annual by first visit",
  year,
  periods = "four interview quarters accumulated into annual first-visit sample",
  n_rows = adolescent_rows,
  geography_units = ufs,
  geography_level = "UF; design identifiers retained",
  age_support = "14-19 completed years",
  sex_coverage = "male and female",
  weighted_population = weighted_population_14_19,
  event_count = NA_real_,
  unweighted_union_count = union_conservative_n,
  usable_for = "age-sex denominators and union outcomes with design-based variance",
  notes = "V1032 annual calibrated weight; 2020-2021 absent from official first-visit product"
)]
total_validation <- fread(file.path(audit_dir, "TOTAL_POPULATION_BUILD_VALIDATION.csv"))
total_coverage <- total_validation[, .(
  source = "pnadc_total_population",
  product_class = "PNADC annual by first visit, all ages",
  year,
  periods = "annual",
  n_rows = source_rows,
  geography_units = ufs,
  geography_level = "UF/region/Brazil",
  age_support = "all ages",
  sex_coverage = "male, female, combined",
  weighted_population = weighted_population_design,
  event_count = NA_real_,
  unweighted_union_count = NA_real_,
  usable_for = "aggregate civil-marriage-rate denominator",
  notes = "No person-level all-age output retained"
)]
coverage <- rbindlist(list(coverage_existing, registry_coverage, pnadc_coverage, total_coverage), use.names = TRUE, fill = TRUE)
setorder(coverage, source, year)
fwrite(coverage, file.path(audit_dir, "COVERAGE_BY_YEAR.csv"))

registry_tests <- fread(file.path(audit_dir, "REGISTRY_BUILD_TESTS.csv"))
registry_year <- fread(file.path(audit_dir, "REGISTRY_VALIDATION_BY_YEAR.csv"))
denominator_selection <- fread(file.path(audit_dir, "DENOMINATOR_PRECISION_SUMMARY.csv"))
pnadc_acquisition <- fread(file.path(audit_dir, "PNADC_EXTERNAL_ACQUISITION_MANIFEST.csv"))
inv_status <- inventory[, .N, by = status][order(status)]
inv_status_text <- paste(sprintf("%s=%d", inv_status$status, inv_status$N), collapse = "; ")
selected_geo <- denominator_selection[selected == TRUE]$geography_level
ambiguous_share <- with(pnadc_validation,
  sum(union_expanded_ambiguous_n) / sum(union_expanded_n - union_conservative_n)
)

data_audit <- c(
  "# Data audit",
  "",
  sprintf("Created: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  "## Inventory and provenance",
  "",
  sprintf("The input inventory contains %d files (%s). Generated outputs and scripts are excluded from the self-referential inventory scope; all acquired raw files and official references are included.", nrow(inventory), inv_status_text),
  sprintf("The official PNADC acquisition contains %d ZIP files, %.2f GB compressed and %.2f GB uncompressed in-place; the TXT members were streamed and never physically expanded.",
          nrow(pnadc_acquisition), sum(pnadc_acquisition$compressed_bytes) / 1e9, sum(pnadc_acquisition$uncompressed_bytes) / 1e9),
  "All acquired PNADC ZIPs, SIDRA JSONs, dictionaries, and reference documents have SHA-256 hashes or equivalent acquisition-manifest integrity metadata.",
  "",
  "## Civil Registry",
  "",
  "The local `rc_raw_cache.rds` is an aggregate complete-table layout, not an individual event file. Rows index the second (female in male-female marriages) spouse's age and columns index the first (male) spouse's age; frequencies were summed without expanding rows.",
  "The official reconstruction uses SIDRA table 4406 for 2013-2024 and includes variables 221, 4373, and 4374, hence male-female, male-male, and female-female marriages. It yields aggregate `spouse_event` cells (one contribution per spouse) and aggregate `marriage_event` cells for affected marriages.",
  sprintf("All %d local age-sex cells and all %d local annual totals checked against the official API match exactly; all monthly sums also reproduce annual cells. Zero-frequency SIDRA symbol `-` is recoded to zero; no missing/suppression symbol occurs in the acquired queries.",
          registry_tests[test == "local complete-table age-sex cells equal official SIDRA"]$checked,
          registry_tests[test == "local annual opposite-sex totals equal official SIDRA"]$checked),
  sprintf("The local `cod_mun` field is unusable: each year has %d collided codes and %d duplicated code-age keys, while registration-place name plus state and age has zero duplicates. Municipal analysis is blocked.",
          max(registry_year$collided_municipality_codes), max(registry_year$duplicate_code_keys)),
  "IBGE documentation defines age as completed years at registration. The available month is month of registration, not month of occurrence/celebration. Geography is the registration office (cartorio), not proven residence.",
  "",
  "## PNADC",
  "",
  sprintf("Official annual first-visit files cover %s. The official directory has no 2020 or 2021 first-visit annual files.", paste(pnadc_validation$year, collapse = ", ")),
  sprintf("The streaming build read %s persons and retained %s adolescents aged 14-19. Every year has 27 UFs; there are zero missing/nonpositive calibrated weights and zero duplicated within-household person keys.",
          format(sum(pnadc_validation$source_rows), big.mark = ","), format(sum(pnadc_validation$adolescent_rows), big.mark = ",")),
  "The checked dictionary identifies V1032 as the annual first-visit weight corrected for nonresponse and calibrated to population projections. It is not divided by four. V1031 is uncalibrated and retained only for audit.",
  "The conservative union outcome identifies the head's spouse or an adolescent head with a spouse present. It does not capture all unions in a household. The expanded outcome adds plausible child/stepchild and son/daughter-in-law combinations.",
  sprintf("Among expanded-only candidate matches, %.1f%% are flagged ambiguous; the expanded definition is therefore robustness-only.", 100 * ambiguous_share),
  "The official UPA and stratum are retained. Population totals and standard errors use Taylor linearization; raw household selection keys are discarded after union construction and replaced by a non-reversible within-year serial.",
  "",
  "## Denominators and geography",
  "",
  "Before marriage effects were estimated, a cell was defined as precise when unweighted n>=30 and CV<=20%. A geography qualifies if at least 95% of age-15 sex/combined cells pass and no CV exceeds 35%.",
  sprintf("%s is selected: %.1f%% of its cells pass and its maximum CV is %.1f%%. Region and Brazil pass all cells and remain mandatory sensitivity analyses.",
          selected_geo, 100 * denominator_selection[selected == TRUE]$share_passing,
          100 * denominator_selection[selected == TRUE]$maximum_cv),
  "The denominator uncertainty is retained through design-based standard errors; fixed-offset estimates are explicitly a simplification. Municipality is not supported by either compatible public PNADC denominators or reliable registry identifiers.",
  "",
  "## Feasibility decision",
  "",
  "The common valid frequency is annual. The primary design is an age-based difference-in-differences, not a conventional RD. Calendar 2019 is excluded from the main post indicator; its 294/365 exposure is robustness/descriptive only. Monthly registration counts are supplementary and cannot be relabeled occurrence-month effects.",
  "The treated age is 15. Ages 16-17 are potentially contaminated by postponement; ages 17-19 are the primary comparison and 18-19 plus 16-17 are locked robustness sets.",
  ""
)
writeLines(data_audit, file.path(audit_dir, "DATA_AUDIT.md"))

feasibility <- c(
  "# Feasibility matrix",
  "",
  sprintf("Created: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  "| Condition | Finding | Implementation | Status |",
  "|---|---|---|---|",
  "| Registry age in annual categories + post-2019 PNADC annual first visit | Found | Annual age-based DiD; supplementary registration-month series | Implemented |",
  "| Registry date of birth and marriage | Not found | No local exact-age RD; preserve aggregate design | Blocked |",
  "| PNAD only annual/common annual frequency | Found | Aggregate Registry to year; exclude 2019 in main; partial-exposure robustness only | Implemented |",
  "| Only traditional PNAD through 2015 | Not applicable; official PNADC first visit is available post-2019 | Use PNADC, not traditional PNAD, for behavioral estimands | Implemented |",
  "| UF denominator imprecise | 98.3% pass; maximum CV 25.2%, below 35% ceiling | UF primary, region/Brazil design-based sensitivity; flag all failing cells | Implemented |",
  "| No valid post-2019 denominator | Not found | V1032 annual age-sex denominators exist in 2022-2024 | Implemented |",
  "| No valid Registry age | Not found | Exact 15-19 and <15 category exist | Implemented |",
  "| No post-2019 period | Not found | Registry through 2024; PNADC through 2024, except 2020-2021 | Implemented |",
  "| Municipality supported by both sources | Not found | Do not estimate municipal effects | Blocked |",
  "| Month of occurrence | Not found in analytical table | Use annual registration-year main; registration-month robustness only | Limited |",
  "| Person panel suitable for union transitions | Not found | Repeated cross-sections only; no transition estimand | Blocked |",
  "| Same-sex Registry coverage | Found in official variables 4373/4374 | Include both spouse contributions in sex-specific/person totals | Implemented |",
  ""
)
writeLines(feasibility, file.path(audit_dir, "FEASIBILITY_MATRIX.md"))

blockers <- c(
  "# Blockers and scope limitations",
  "",
  sprintf("Updated: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  "1. **No exact-age RD.** Neither dates of marriage/registration nor a compatible exact-age-at-risk population are available. Age is in completed years/categories. The project must not call its main design a conventional RD.",
  "2. **No month of occurrence in the analytical Registry table.** SIDRA table 4406 supplies month of registration. Monthly estimates may reflect habilitation, celebration, and registration lags and are supplementary only.",
  "3. **No municipal causal panel.** The local `cod_mun` is non-unique, the documented geography is place of registration rather than residence, and PNADC does not provide a compatible precise public municipal age-sex denominator.",
  "4. **No annual first-visit PNADC in 2020-2021.** These files are absent from the official product directory. Union outcomes and compatible total-population rates are not interpolated for those years.",
  "5. **No valid individual transition design.** PNADC follows sampled dwellings; a moving person can disappear precisely when forming a union. The official key documentation also warns that the person key is not longitudinal. Analysis is repeated cross-section.",
  "6. **Conservative union is a lower-bound construct.** It mainly observes unions involving the household head. The expanded nested-pair definition has substantial ambiguity and is robustness-only.",
  "7. **No verified first-marriage/cohort incidence.** Aggregate cells do not identify persons or cohorts, and conditioning on prior civil status would not recover informal prior unions. This estimand is not reported.",
  "8. **No clean annual short-run post period.** The law took effect on 13 March 2019, so 2019 is partial. The main annual model excludes it; registration-month April-December 2019 is supplementary, not an occurrence-month effect.",
  "9. **Local legacy PNADC and Registry-rate objects are unsuitable.** The local PNADC cache is female-only and lacks design/household keys; the legacy Registry rate divides marriages by another marriage count. They are retained only for audit and never used as causal outcomes.",
  "10. **The <15 Registry category has no defensible matching risk population.** Counts and shares are reported, but no rate using all children aged 0-14 is constructed.",
  ""
)
writeLines(blockers, file.path(audit_dir, "BLOCKERS.md"))

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(start_time, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("inventory_files=%d", nrow(inventory)),
  sprintf("coverage_rows=%d", nrow(coverage)),
  sprintf("crosswalk_rows=%d", nrow(crosswalk)),
  sprintf("selected_geography=%s", selected_geo),
  "effects_estimated=0",
  "gate=B"
)
writeLines(log_lines, file.path(log_dir, "06_finalize_audit.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
