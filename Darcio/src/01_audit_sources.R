#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(DBI)
  library(duckdb)
})

start_time <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
darcio_root <- file.path(project_root, "Darcio")
audit_dir <- file.path(darcio_root, "outputs", "audit")
log_dir <- file.path(darcio_root, "outputs", "logs")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

read_mem_available_kib <- function() {
  lines <- readLines("/proc/meminfo", warn = FALSE)
  val <- sub("^MemAvailable:[[:space:]]+([0-9]+).*", "\\1", grep("^MemAvailable:", lines, value = TRUE))
  suppressWarnings(as.numeric(val))
}

mem_start_kib <- read_mem_available_kib()

# -----------------------------------------------------------------------------
# Registry Civil complete tables cache
# -----------------------------------------------------------------------------

registry_path <- file.path(project_root, "data", "cache", "rc_raw_cache.rds")
registry <- as.data.table(readRDS(registry_path))
registry_object_bytes <- as.numeric(object.size(registry))

required_registry <- c(
  "ano", "uf", "regiao", "cod_mun", "nome_mun", "idade_m", "n_total_row",
  "h_men15", "h_15", "h_16", "h_17", "h_18", "h_19", "h_20_24",
  "h_25_29", "h_30_34", "h_35_39", "h_40_44", "h_45_49", "h_50_54",
  "h_55_59", "h_60_64", "h_65+", "h_0"
)
missing_registry <- setdiff(required_registry, names(registry))
if (length(missing_registry)) stop("Registry cache lacks required fields: ", paste(missing_registry, collapse = ", "))

female_map <- data.table(
  female_age_raw = c(
    "Menos de 15 anos", "15 anos", "16 anos", "17 anos", "18 anos", "19 anos",
    "20 a 24 anos", "25 a 29 anos", "30 a 34 anos", "35 a 39 anos",
    "40 a 44 anos", "45 a 49 anos", "50 a 54 anos", "55 a 59 anos",
    "60 a 64 anos", "65 anos ou mais", "Idade ignorada"
  ),
  age_group = c(
    "<15", "15", "16", "17", "18", "19", "20-24", "25-29", "30-34",
    "35-39", "40-44", "45-49", "50-54", "55-59", "60-64", "65+", "unknown"
  )
)
female_map[, `:=`(
  below_15 = age_group == "<15",
  below_16 = age_group %in% c("<15", "15"),
  age_known = age_group != "unknown"
)]

male_map <- data.table(
  male_column = c(
    "h_men15", "h_15", "h_16", "h_17", "h_18", "h_19", "h_20_24",
    "h_25_29", "h_30_34", "h_35_39", "h_40_44", "h_45_49", "h_50_54",
    "h_55_59", "h_60_64", "h_65+"
  ),
  age_group = c(
    "<15", "15", "16", "17", "18", "19", "20-24", "25-29", "30-34",
    "35-39", "40-44", "45-49", "50-54", "55-59", "60-64", "65+"
  )
)
male_map[, `:=`(
  below_15 = age_group == "<15",
  below_16 = age_group %in% c("<15", "15")
)]

registry[, male_age_unknown_count := suppressWarnings(as.numeric(as.character(h_0)))]
registry[is.na(male_age_unknown_count), male_age_unknown_count := 0]
registry[, female_age_group := female_map$age_group[match(idade_m, female_map$female_age_raw)]]
registry[, female_below_16 := female_age_group %in% c("<15", "15")]

registry_long <- melt(
  registry,
  id.vars = c("ano", "uf", "regiao", "cod_mun", "nome_mun", "idade_m", "female_age_group", "female_below_16"),
  measure.vars = male_map$male_column,
  variable.name = "male_column",
  value.name = "marriages",
  variable.factor = FALSE
)
registry_long[, source_value_missing := is.na(marriages)]
registry_long[is.na(marriages), marriages := 0]
registry_long[, male_age_group := male_map$age_group[match(male_column, male_map$male_column)]]
registry_long[, male_below_16 := male_age_group %in% c("<15", "15")]

female_counts <- registry[, .(
  persons_married = sum(n_total_row + male_age_unknown_count, na.rm = TRUE)
), by = .(year = ano, uf, age_group = female_age_group)]
female_counts[, sex := "female"]
setcolorder(female_counts, c("year", "uf", "sex", "age_group", "persons_married"))

male_counts <- registry_long[, .(
  persons_married = sum(marriages, na.rm = TRUE)
), by = .(year = ano, uf, age_group = male_age_group)]
male_counts[, sex := "male"]
setcolorder(male_counts, c("year", "uf", "sex", "age_group", "persons_married"))

male_unknown <- registry[, .(
  persons_married = sum(male_age_unknown_count, na.rm = TRUE)
), by = .(year = ano, uf)]
male_unknown[, `:=`(sex = "male", age_group = "unknown")]
setcolorder(male_unknown, c("year", "uf", "sex", "age_group", "persons_married"))

registry_spouse_age <- rbindlist(list(female_counts, male_counts, male_unknown), use.names = TRUE)
registry_spouse_age <- registry_spouse_age[, .(persons_married = sum(persons_married)), by = .(year, uf, sex, age_group)]
setorder(registry_spouse_age, year, uf, sex, age_group)
fwrite(registry_spouse_age, file.path(audit_dir, "REGISTRY_SPOUSE_AGE_COUNTS.csv"))

affected_known <- registry_long[
  female_below_16 | male_below_16,
  .(affected_known = sum(marriages, na.rm = TRUE)),
  by = .(year = ano)
]
affected_female_known_male_unknown <- registry[
  female_below_16 == TRUE,
  .(affected_female_known_male_unknown = sum(male_age_unknown_count, na.rm = TRUE)),
  by = .(year = ano)
]

registry_year <- registry[, .(
  n_source_rows = .N,
  registration_places = uniqueN(nome_mun),
  municipality_codes = uniqueN(cod_mun),
  ufs = uniqueN(uf),
  regions = uniqueN(regiao),
  female_age_categories = uniqueN(idade_m),
  total_opposite_sex_marriages = sum(n_total_row + male_age_unknown_count, na.rm = TRUE),
  marriages_with_female_unknown_age = sum((n_total_row + male_age_unknown_count)[female_age_group == "unknown"], na.rm = TRUE),
  marriages_with_male_unknown_age = sum(male_age_unknown_count, na.rm = TRUE),
  known_male_age_cells_recorded_as_na = sum(is.na(unlist(.SD))),
  negative_known_age_cells = sum(unlist(.SD) < 0, na.rm = TRUE),
  legacy_total_mismatch_rows = sum(n_total_row != rowSums(.SD, na.rm = TRUE), na.rm = TRUE)
), by = .(year = ano), .SDcols = male_map$male_column]

registry_year <- merge(registry_year, affected_known, by = "year", all.x = TRUE)
registry_year <- merge(registry_year, affected_female_known_male_unknown, by = "year", all.x = TRUE)
both_ages_unknown <- registry[
  female_age_group == "unknown",
  .(marriages_with_both_ages_unknown = sum(male_age_unknown_count, na.rm = TRUE)),
  by = .(year = ano)
]
registry_year <- merge(registry_year, both_ages_unknown, by = "year", all.x = TRUE)
registry_year[is.na(affected_known), affected_known := 0]
registry_year[is.na(affected_female_known_male_unknown), affected_female_known_male_unknown := 0]
registry_year[is.na(marriages_with_both_ages_unknown), marriages_with_both_ages_unknown := 0]
registry_year[, affected_marriage := affected_known + affected_female_known_male_unknown]
registry_year[, affected_share := affected_marriage / total_opposite_sex_marriages]
registry_year[, any_age_unknown_share := (
  marriages_with_female_unknown_age + marriages_with_male_unknown_age -
    marriages_with_both_ages_unknown
) / total_opposite_sex_marriages]

correct_key_duplicates <- registry[, .N, by = .(ano, nome_mun, idade_m)][N > 1L]
code_key_duplicates <- registry[, .N, by = .(ano, cod_mun, idade_m)][N > 1L]
code_name_collisions <- unique(registry[, .(ano, cod_mun, nome_mun, uf)])[, .(
  distinct_place_names = uniqueN(nome_mun),
  place_names = paste(sort(unique(nome_mun)), collapse = " || ")
), by = .(year = ano, cod_mun)][distinct_place_names > 1L]

duplicate_correct_by_year <- correct_key_duplicates[, .(duplicate_correct_keys = .N), by = .(year = ano)]
duplicate_code_by_year <- code_key_duplicates[, .(duplicate_code_keys = .N), by = .(year = ano)]
collided_codes_by_year <- code_name_collisions[, .(collided_municipality_codes = .N), by = year]
registry_year <- merge(registry_year, duplicate_correct_by_year, by = "year", all.x = TRUE)
registry_year <- merge(registry_year, duplicate_code_by_year, by = "year", all.x = TRUE)
registry_year <- merge(registry_year, collided_codes_by_year, by = "year", all.x = TRUE)
for (col in c("duplicate_correct_keys", "duplicate_code_keys", "collided_municipality_codes")) {
  set(registry_year, which(is.na(registry_year[[col]])), col, 0L)
}

fwrite(registry_year, file.path(audit_dir, "REGISTRY_VALIDATION_BY_YEAR.csv"))
fwrite(code_name_collisions, file.path(audit_dir, "REGISTRY_CODE_COLLISIONS.csv"))

registry_inconsistencies <- rbindlist(list(
  data.table(
    issue = "duplicate using registration-place name + year + female age",
    count = nrow(correct_key_duplicates),
    severity = if (nrow(correct_key_duplicates)) "blocking" else "none",
    interpretation = "The name includes the state suffix and is the usable local registration-place identifier."
  ),
  data.table(
    issue = "duplicate using cod_mun + year + female age",
    count = nrow(code_key_duplicates),
    severity = "high",
    interpretation = "cod_mun is corrupted/non-unique across same-named places in different states; do not use it for joins."
  ),
  data.table(
    issue = "municipality codes mapped to more than one registration-place name",
    count = nrow(code_name_collisions),
    severity = "high",
    interpretation = "Municipal analysis is blocked; UF aggregation uses the state suffix extracted from nome_mun."
  ),
  data.table(
    issue = "negative marriage cells",
    count = sum(registry_year$negative_known_age_cells),
    severity = if (sum(registry_year$negative_known_age_cells)) "blocking" else "none",
    interpretation = "Marriage cell frequencies must be nonnegative."
  ),
  data.table(
    issue = "legacy n_total_row inconsistent with known male-age columns",
    count = sum(registry_year$legacy_total_mismatch_rows),
    severity = if (sum(registry_year$legacy_total_mismatch_rows)) "high" else "none",
    interpretation = "Checks the cached row-sum construction."
  )
), fill = TRUE)
fwrite(registry_inconsistencies, file.path(audit_dir, "REGISTRY_INCONSISTENCIES.csv"))

# -----------------------------------------------------------------------------
# Compare complete-table cache with the local SIDRA T4406 extracts
# -----------------------------------------------------------------------------

sidra_files <- list.files(file.path(project_root, "data", "raw"), pattern = "^rc_sidra_[0-9]{4}\\.rds$", full.names = TRUE)
sidra <- rbindlist(lapply(sidra_files, function(path) {
  d <- as.data.table(readRDS(path))
  d[, source_file := basename(path)]
  d
}), fill = TRUE)

sidra_standard <- sidra[, .(
  year = suppressWarnings(as.integer(as.character(Ano))),
  uf = as.character(`Unidade da Federação`),
  age_group_raw = as.character(`Grupo de idade do segundo cônjuge`),
  age_code = as.character(`Grupo de idade do segundo cônjuge (Código)`),
  value = suppressWarnings(as.numeric(as.character(Valor))),
  variable = as.character(Variável),
  month = as.character(`Mês do registro`),
  source_file
)]

sidra_standard[, age_group := female_map$age_group[match(age_group_raw, female_map$female_age_raw)]]
uf_name_to_sigla <- c(
  "Rondônia"="RO", "Acre"="AC", "Amazonas"="AM", "Roraima"="RR", "Pará"="PA", "Amapá"="AP", "Tocantins"="TO",
  "Maranhão"="MA", "Piauí"="PI", "Ceará"="CE", "Rio Grande do Norte"="RN", "Paraíba"="PB", "Pernambuco"="PE",
  "Alagoas"="AL", "Sergipe"="SE", "Bahia"="BA", "Minas Gerais"="MG", "Espírito Santo"="ES", "Rio de Janeiro"="RJ",
  "São Paulo"="SP", "Paraná"="PR", "Santa Catarina"="SC", "Rio Grande do Sul"="RS", "Mato Grosso do Sul"="MS",
  "Mato Grosso"="MT", "Goiás"="GO", "Distrito Federal"="DF"
)
sidra_standard[, uf_sigla := unname(uf_name_to_sigla[uf])]

matrix_female_uf <- registry_spouse_age[sex == "female", .(matrix_value = sum(persons_married)), by = .(year, uf_sigla = uf, age_group)]
sidra_validation <- merge(
  sidra_standard[!is.na(age_group) & !is.na(uf_sigla), .(sidra_value = sum(value, na.rm = FALSE)), by = .(year, uf_sigla, age_group)],
  matrix_female_uf,
  by = c("year", "uf_sigla", "age_group"),
  all.x = TRUE
)
sidra_validation[, difference := matrix_value - sidra_value]
sidra_validation[, exact_match := !is.na(difference) & difference == 0]
fwrite(sidra_validation, file.path(audit_dir, "REGISTRY_SIDRA_VALIDATION.csv"))

sidra_coverage <- sidra_standard[, .(
  n_rows = .N,
  ufs = uniqueN(uf_sigla, na.rm = TRUE),
  age_codes = uniqueN(age_code),
  labeled_age_rows = sum(!is.na(age_group) & nzchar(age_group_raw)),
  numeric_values = sum(!is.na(value)),
  missing_values = sum(is.na(value))
), by = year][order(year)]
fwrite(sidra_coverage, file.path(audit_dir, "SIDRA_LOCAL_COVERAGE.csv"))

# -----------------------------------------------------------------------------
# PNADC annual-by-first-visit filtered cache
# -----------------------------------------------------------------------------

pnadc_path <- file.path(project_root, "data", "cache", "didc_pnadc_cache.rds")
pnadc <- as.data.table(readRDS(pnadc_path))
pnadc_object_bytes <- as.numeric(object.size(pnadc))

required_pnadc <- c("Ano", "UF", "Trimestre", "pes_comcalib", "condno_domic", "sexo", "idade", "cor_raca", "sit_domic", "nasc_mes", "nasc_ano")
missing_pnadc <- setdiff(required_pnadc, names(pnadc))
if (length(missing_pnadc)) stop("PNADC cache lacks required fields: ", paste(missing_pnadc, collapse = ", "))

pnadc[, `:=`(
  year = suppressWarnings(as.integer(as.character(Ano))),
  age = suppressWarnings(as.integer(as.character(idade))),
  weight = suppressWarnings(as.numeric(as.character(pes_comcalib))),
  union_spouse_different_sex = as.integer(as.character(condno_domic) == "Cônjuge ou companheiro(a) de sexo diferente"),
  union_spouse_any_sex = as.integer(as.character(condno_domic) %in% c(
    "Cônjuge ou companheiro(a) de sexo diferente",
    "Cônjuge ou companheiro(a) do mesmo sexo"
  ))
)]

pnadc_age <- pnadc[, .(
  unweighted_n = .N,
  weighted_population = sum(weight, na.rm = TRUE),
  kish_effective_n = sum(weight, na.rm = TRUE)^2 / sum(weight^2, na.rm = TRUE),
  union_spouse_different_n = sum(union_spouse_different_sex, na.rm = TRUE),
  union_spouse_different_weighted = sum(weight * union_spouse_different_sex, na.rm = TRUE),
  union_spouse_any_n = sum(union_spouse_any_sex, na.rm = TRUE),
  union_spouse_any_weighted = sum(weight * union_spouse_any_sex, na.rm = TRUE)
), by = .(year, age, sex = as.character(sexo))]
pnadc_age[, `:=`(
  union_spouse_different_prevalence = union_spouse_different_weighted / weighted_population,
  union_spouse_any_prevalence = union_spouse_any_weighted / weighted_population,
  design_se_available = FALSE,
  precision_note = "UPA and Estrato were removed from this cache; Kish n is descriptive, not a design-based variance estimate"
)]
fwrite(pnadc_age, file.path(audit_dir, "PNADC_AGE_VALIDATION.csv"))

pnadc_year <- pnadc[, .(
  n_rows = .N,
  ufs = uniqueN(UF),
  quarters = paste(sort(unique(as.integer(as.character(Trimestre)))), collapse = ";"),
  age_min = min(age, na.rm = TRUE),
  age_max = max(age, na.rm = TRUE),
  sex_levels = paste(sort(unique(as.character(sexo))), collapse = ";"),
  weighted_population = sum(weight, na.rm = TRUE),
  missing_weight = sum(is.na(weight)),
  missing_birth_month = sum(is.na(nasc_mes) | as.character(nasc_mes) %in% c("99", "")),
  missing_birth_year = sum(is.na(nasc_ano) | as.character(nasc_ano) %in% c("999", "9999", "")),
  union_spouse_different_n = sum(union_spouse_different_sex),
  union_spouse_any_n = sum(union_spouse_any_sex),
  union_spouse_different_weighted = sum(weight * union_spouse_different_sex),
  union_spouse_any_weighted = sum(weight * union_spouse_any_sex)
), by = year][order(year)]
pnadc_year[, `:=`(
  product_class = "PNAD Continua annual by first visit (inferred from V1032 provenance)",
  design_ids_available = FALSE,
  household_ids_available = FALSE,
  complete_conservative_union_available = FALSE
)]
fwrite(pnadc_year, file.path(audit_dir, "PNADC_VALIDATION_BY_YEAR.csv"))

pnadc_roles <- pnadc[, .(
  unweighted_n = .N,
  weighted_population = sum(weight, na.rm = TRUE)
), by = .(role = as.character(condno_domic))][order(-unweighted_n)]
fwrite(pnadc_roles, file.path(audit_dir, "PNADC_ROLE_DISTRIBUTION.csv"))

# -----------------------------------------------------------------------------
# Legacy processed objects: suitability diagnostics
# -----------------------------------------------------------------------------

legacy_pnadc <- as.data.table(readRDS(file.path(project_root, "data", "processed", "dc_pnadc_dcm.rds")))
legacy_pnadc_diag <- legacy_pnadc[, .(
  n_rows = .N,
  in_union = sum(choice == "in_union", na.rm = TRUE),
  wait = sum(choice == "wait", na.rm = TRUE),
  in_union_labeled_spouse = sum(choice == "in_union" & grepl("Cônjuge|companheiro", as.character(condno_domic)), na.rm = TRUE),
  wait_labeled_responsible = sum(choice == "wait" & as.character(condno_domic) == "Pessoa responsável pelo domicílio", na.rm = TRUE),
  other_role_rows = sum(!grepl("Cônjuge|companheiro|Pessoa responsável", as.character(condno_domic)), na.rm = TRUE),
  upa_missing = sum(is.na(UPA)),
  strata_missing = sum(is.na(Estrato)),
  weight_missing = sum(is.na(pes_comcalib))
), by = .(year = suppressWarnings(as.integer(as.character(Ano))))]
legacy_pnadc_diag[, suitability := "blocked for prevalence/causal union outcome: role-selected sample and choice mechanically labels spouses as in_union and adolescent heads as wait"]
fwrite(legacy_pnadc_diag, file.path(audit_dir, "LEGACY_PNADC_DIAGNOSTIC.csv"))

legacy_registry <- as.data.table(readRDS(file.path(project_root, "data", "processed", "dc_rc_dcm.rds")))
legacy_registry_diag <- legacy_registry[, .(
  n_rows = .N,
  denominator_min = suppressWarnings(min(n_casamentos_2029, na.rm = TRUE)),
  denominator_max = suppressWarnings(max(n_casamentos_2029, na.rm = TRUE)),
  exact_rate_identity_share = mean(abs(rate_per_1k_2029 - 1000 * n_total_row / n_casamentos_2029) < 1e-10, na.rm = TRUE)
), by = .(year = ano)]
legacy_registry_diag[, suitability := "blocked as population incidence: n_casamentos_2029 is a marriage count, not population at risk"]
fwrite(legacy_registry_diag, file.path(audit_dir, "LEGACY_REGISTRY_DIAGNOSTIC.csv"))

# Update inventory analytical status for unsuitable derived objects.
inventory_path <- file.path(audit_dir, "DATA_INVENTORY.csv")
if (file.exists(inventory_path)) {
  inventory <- fread(inventory_path)
  inventory[relative_path %in% c("data/processed/dc_pnadc_dcm.rds", "data/processed/dc_rc_dcm.rds"), `:=`(
    status = "bloqueado",
    integrity_note = fifelse(
      relative_path == "data/processed/dc_pnadc_dcm.rds",
      "Role-selected sample cannot estimate union prevalence; choice is mechanically defined by household role",
      "Legacy rate divides marriages by marriages aged 20-29, not by population at risk"
    )
  )]
  fwrite(inventory, inventory_path, na = "")
}

# -----------------------------------------------------------------------------
# DuckDB audit
# -----------------------------------------------------------------------------

db_path <- file.path(project_root, "data", "child_marriage.duckdb")
con <- dbConnect(duckdb(), db_path, read_only = TRUE)
tables <- dbListTables(con)
duck_tables <- rbindlist(lapply(tables, function(tb) {
  n <- dbGetQuery(con, paste("SELECT COUNT(*) AS n FROM", dbQuoteIdentifier(con, tb)))$n[[1L]]
  cols <- dbListFields(con, tb)
  year_col <- intersect(cols, c("ano", "Ano", "year"))
  yr <- if (length(year_col)) {
    dbGetQuery(con, paste(
      "SELECT MIN(TRY_CAST(", dbQuoteIdentifier(con, year_col[[1L]]), " AS INTEGER)) AS min_year,",
      "MAX(TRY_CAST(", dbQuoteIdentifier(con, year_col[[1L]]), " AS INTEGER)) AS max_year FROM",
      dbQuoteIdentifier(con, tb)
    ))
  } else data.frame(min_year = NA_integer_, max_year = NA_integer_)
  data.table(table = tb, n_rows = n, n_columns = length(cols), min_year = yr$min_year[[1L]], max_year = yr$max_year[[1L]])
}))
duck_schema <- rbindlist(lapply(tables, function(tb) {
  x <- as.data.table(dbGetQuery(con, paste("DESCRIBE", dbQuoteIdentifier(con, tb))))
  x[, table := tb]
  x
}), fill = TRUE)
dbDisconnect(con, shutdown = TRUE)
fwrite(duck_tables, file.path(audit_dir, "DUCKDB_TABLES.csv"))
fwrite(duck_schema, file.path(audit_dir, "DUCKDB_SCHEMA.csv"))

# -----------------------------------------------------------------------------
# Mandatory PNADC variable crosswalk
# -----------------------------------------------------------------------------

crosswalk <- data.table(
  canonical_field = c(
    "year", "quarter", "visit", "uf", "region", "public_domain", "household_id", "person_id",
    "upa", "stratum", "calibrated_weight", "uncalibrated_weight", "replicate_weights",
    "age", "birth_day", "birth_month", "birth_year", "sex", "race_color", "household_role",
    "school_attendance", "education_level", "worked", "hours", "earnings", "urban_rural"
  ),
  raw_or_local_field = c(
    "Ano", "Trimestre", "not stored; provenance fixes interview=1", "UF", "not stored; derivable from UF",
    "not stored", "not stored (UPA+V1008+V1014)", "not stored (household key+V2003)",
    "not stored", "not stored", "pes_comcalib <- V1032", "not stored (V1031)", "not stored",
    "idade <- V2009", "not stored (V2008)", "nasc_mes <- V20081", "nasc_ano <- V20082",
    "sexo <- V2007; cache filtered to female", "cor_raca <- V2010", "condno_domic <- V2005",
    "not stored (V3002)", "not stored (VD3004/VD3005)", "not stored (V4001)",
    "not stored (VD4031/V4039 depending product)", "not stored (VD4019/V403312 depending product)", "sit_domic <- V1022"
  ),
  source_object = "data/cache/didc_pnadc_cache.rds",
  availability = c(
    "available", "available", "inferred from source code", "available", "derivable", "missing",
    "missing", "missing", "missing", "missing", "available", "missing", "missing", "available",
    "missing", "available", "available", "available but only female", "available", "available",
    "missing", "missing", "missing", "missing", "missing", "available"
  ),
  dictionary_checked = "notes/data dictionary/dicionario_PNADC_microdados_2022_visita1_20231129.xls; notes/data dictionary/Dicionario_e_input_20221031.zip",
  audit_decision = c(
    "use", "descriptive only within annual-by-visit product", "classify as first visit", "use", "derive",
    "blocked", "must reacquire official microdata", "must reacquire official microdata", "must reacquire official microdata",
    "must reacquire official microdata", "use for annual point estimates", "not needed if calibrated weight used",
    "not available in local cache", "use annual age; no conventional RD", "blocks exact age in days", "use only for birth-month checks",
    "use only for birth-year checks", "blocks male and combined estimates", "use if needed", "use for spouse-of-head lower-bound outcome",
    "must reacquire for exploratory outcome", "must reacquire for exploratory outcome", "must reacquire for exploratory outcome",
    "must reacquire for exploratory outcome", "must reacquire for exploratory outcome", "use"
  )
)
fwrite(crosswalk, file.path(audit_dir, "VARIABLE_CROSSWALK.csv"))

# -----------------------------------------------------------------------------
# Combined coverage matrix by source/year
# -----------------------------------------------------------------------------

registry_coverage <- registry_year[, .(
  source = "registry_complete_tables_cache",
  product_class = "Registry Civil aggregate cells; opposite-sex marriages",
  year,
  periods = "annual registration year",
  n_rows = n_source_rows,
  geography_units = registration_places,
  geography_level = "place of registration (name); UF supported",
  age_support = "<15;15;16;17;18;19;5-year groups;65+;unknown for both spouses",
  sex_coverage = "male and female spouses in opposite-sex marriages",
  weighted_population = NA_real_,
  event_count = total_opposite_sex_marriages,
  unweighted_union_count = NA_real_,
  usable_for = "annual numerators, joint-age affected marriages, delay/bunching; not a population rate without denominator",
  notes = "Age is years completed at registration; location is cartorio; cod_mun is unusable"
)]

pnadc_coverage <- pnadc_year[, .(
  source = "pnadc_didc_cache",
  product_class,
  year,
  periods = paste0("quarters present: ", quarters),
  n_rows,
  geography_units = ufs,
  geography_level = "UF label only; UPA and stratum removed",
  age_support = paste0(age_min, "-", age_max, " years"),
  sex_coverage = sex_levels,
  weighted_population,
  event_count = NA_real_,
  unweighted_union_count = union_spouse_any_n,
  usable_for = "annual female population point estimates and spouse-of-head lower-bound union prevalence; no design-based SE",
  notes = "2020-2021 deliberately absent; household pairing impossible"
)]

sidra_cov_out <- sidra_coverage[, .(
  source = "registry_sidra_local_extracts",
  product_class = "SIDRA table 4406 UF aggregate; second-spouse selected ages",
  year,
  periods = "annual; month fixed at Total",
  n_rows,
  geography_units = ufs,
  geography_level = "UF",
  age_support = sprintf("%d age codes; %d labeled rows", age_codes, labeled_age_rows),
  sex_coverage = "second spouse in male-female marriages",
  weighted_population = NA_real_,
  event_count = NA_real_,
  unweighted_union_count = NA_real_,
  usable_for = "validation and selected second-spouse numerators",
  notes = sprintf("numeric values=%d; missing values=%d", numeric_values, missing_values)
)]

coverage <- rbindlist(list(registry_coverage, pnadc_coverage, sidra_cov_out), fill = TRUE)
setorder(coverage, source, year)
fwrite(coverage, file.path(audit_dir, "COVERAGE_BY_YEAR.csv"))

rm(registry_long, legacy_pnadc, legacy_registry, pnadc)
gc(verbose = FALSE)

mem_end_kib <- read_mem_available_kib()
elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(start_time, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("registry_rows=%d", nrow(registry)),
  sprintf("registry_object_bytes=%s", format(registry_object_bytes, scientific = FALSE)),
  sprintf("pnadc_rows=%d", sum(pnadc_year$n_rows)),
  sprintf("pnadc_object_bytes=%s", format(pnadc_object_bytes, scientific = FALSE)),
  sprintf("mem_available_start_kib=%s", format(mem_start_kib, scientific = FALSE)),
  sprintf("mem_available_end_kib=%s", format(mem_end_kib, scientific = FALSE)),
  "max_parallel_processes=4",
  "raw_files_modified=0"
)
writeLines(log_lines, file.path(log_dir, "01_audit_sources.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
