#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(readxl)
  library(arrow)
  library(digest)
})

start_time <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
darcio_root <- file.path(project_root, "Darcio")
raw_dir <- file.path(darcio_root, "data", "raw_external", "pnadc_visita1")
doc_dir <- file.path(darcio_root, "references", "pnadc_documentation")
audit_dir <- file.path(darcio_root, "outputs", "audit")
data_dir <- file.path(darcio_root, "outputs", "data", "pnadc_adolescents")
log_dir <- file.path(darcio_root, "outputs", "logs")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

manifest_path <- file.path(audit_dir, "PNADC_EXTERNAL_ACQUISITION_MANIFEST.csv")
if (!file.exists(manifest_path)) stop("Run Darcio/src/01_acquire_pnadc.R first")
manifest <- fread(manifest_path)
setorder(manifest, year)

dictionary_for_year <- function(year) {
  if (year %in% 2012:2014) "dicionario_PNADC_microdados_2012_a_2014_visita1_20220224.xls"
  else if (year == 2015) "dicionario_PNADC_microdados_2015_visita1_20220224.xls"
  else if (year == 2016) "dicionario_PNADC_microdados_2016_visita1_20220224.xls"
  else if (year == 2017) "dicionario_PNADC_microdados_2017_visita1_20220224.xls"
  else if (year == 2018) "dicionario_PNADC_microdados_2018_visita1_20220224.xls"
  else if (year == 2019) "dicionario_PNADC_microdados_2019_visita1_20230811.xls"
  else if (year == 2022) "dicionario_PNADC_microdados_2022_visita1_20231129.xls"
  else if (year == 2023) "dicionario_PNADC_microdados_2023_visita1_20241220.xls"
  else if (year == 2024) "dicionario_PNADC_microdados_2024_visita1_20251119.xls"
  else stop("No audited dictionary mapping for year ", year)
}

fields <- c(
  "Ano", "Trimestre", "UF", "Capital", "RM_RIDE", "UPA", "Estrato",
  "V1008", "V1014", "V1022", "V1023", "V1031", "V1032", "V2003",
  "V2005", "V2007", "V2008", "V20081", "V20082", "V2009", "V2010",
  "V3002", "VD3004", "VD3005", "V4001", "VD4019", "VD4031"
)
core_fields <- c(
  "Ano", "Trimestre", "UF", "UPA", "Estrato", "V1008", "V1014", "V1032",
  "V2003", "V2005", "V2007", "V2008", "V20081", "V20082", "V2009"
)

read_dictionary_map <- function(path) {
  raw <- suppressMessages(as.data.table(read_excel(path, col_names = FALSE)))
  setnames(raw, paste0("column_", seq_len(ncol(raw))))
  map <- raw[column_3 %chin% fields, .(
    field = column_3,
    start = suppressWarnings(as.integer(column_1)),
    width = suppressWarnings(as.integer(column_2)),
    description = as.character(column_5)
  )]
  map <- map[!is.na(start) & !is.na(width)]
  missing_core <- setdiff(core_fields, map$field)
  if (length(missing_core)) stop("Dictionary lacks core fields: ", paste(missing_core, collapse = ", "))
  map[, end := start + width - 1L]
  setorder(map, start)
  map
}

parse_chunk <- function(lines, map) {
  ans <- setNames(vector("list", nrow(map)), map$field)
  for (i in seq_len(nrow(map))) {
    ans[[i]] <- trimws(substr(lines, map$start[[i]], map$end[[i]]))
  }
  as.data.table(ans)
}

as_integer_blank_na <- function(x) {
  x[x == ""] <- NA_character_
  suppressWarnings(as.integer(x))
}

as_numeric_blank_na <- function(x) {
  x[x == ""] <- NA_character_
  suppressWarnings(as.numeric(x))
}

read_zip_selected <- function(zip_path, member_name, map, chunk_lines = 25000L) {
  con <- unz(zip_path, filename = member_name, open = "rt", encoding = "ASCII")
  on.exit(close(con), add = TRUE)
  pieces <- list()
  index <- 0L
  repeat {
    lines <- readLines(con, n = chunk_lines, warn = FALSE)
    if (!length(lines)) break
    index <- index + 1L
    pieces[[index]] <- parse_chunk(lines, map)
    rm(lines)
    if (index %% 4L == 0L) gc(verbose = FALSE)
  }
  rbindlist(pieces, use.names = TRUE, fill = TRUE)
}

region_from_uf <- function(uf) {
  fifelse(uf %in% 11:17, "North",
    fifelse(uf %in% 21:29, "Northeast",
      fifelse(uf %in% 31:35, "Southeast",
        fifelse(uf %in% 41:43, "South",
          fifelse(uf %in% 50:53, "Central-West", NA_character_)
        )
      )
    )
  )
}

year_logs <- list()
validation <- list()

for (i in seq_len(nrow(manifest))) {
  year_start <- Sys.time()
  year_value <- manifest$year[[i]]
  zip_path <- file.path(project_root, manifest$relative_path[[i]])
  if (!file.exists(zip_path)) stop("Missing acquired ZIP: ", zip_path)
  current_hash <- digest(zip_path, algo = "sha256", file = TRUE)
  if (!identical(current_hash, manifest$sha256[[i]])) stop("Hash mismatch: ", zip_path)

  dictionary_name <- dictionary_for_year(year_value)
  dictionary_path <- file.path(doc_dir, dictionary_name)
  if (!file.exists(dictionary_path)) stop("Missing official dictionary: ", dictionary_path)
  map <- read_dictionary_map(dictionary_path)
  raw <- read_zip_selected(zip_path, manifest$member_name[[i]], map)

  character_fields <- intersect(c("UPA", "Estrato", "V1008", "V1014", "V2003"), names(raw))
  for (field in character_fields) set(raw, j = field, value = trimws(raw[[field]]))
  integer_fields <- setdiff(intersect(fields, names(raw)), c(character_fields, "V1031", "V1032", "VD4019"))
  for (field in integer_fields) set(raw, j = field, value = as_integer_blank_na(raw[[field]]))
  for (field in intersect(c("V1031", "V1032", "VD4019"), names(raw))) {
    set(raw, j = field, value = as_numeric_blank_na(raw[[field]]))
  }

  if (any(raw$Ano != year_value, na.rm = TRUE)) stop("Year field disagrees with file year ", year_value)
  raw[, household_key_raw := paste(UPA, V1008, V1014, sep = "-")]
  household <- raw[, .(
    household_members = .N,
    n_responsible = sum(V2005 == 1L, na.rm = TRUE),
    n_spouse = sum(V2005 %in% c(2L, 3L), na.rm = TRUE),
    n_child_stepchild = sum(V2005 %in% 4:6, na.rm = TRUE),
    n_son_daughter_in_law = sum(V2005 == 7L, na.rm = TRUE)
  ), by = household_key_raw]
  raw <- household[raw, on = "household_key_raw"]

  adolescents <- raw[V2009 %between% c(14L, 19L)]
  adolescents[, union_conservative := as.integer(
    V2005 %in% c(2L, 3L) | (V2005 == 1L & n_spouse > 0L)
  )]
  adolescents[, expanded_nested_match := V2005 %in% 4:6 & n_son_daughter_in_law > 0L |
    V2005 == 7L & n_child_stepchild > 0L]
  adolescents[, union_expanded := as.integer(union_conservative == 1L | expanded_nested_match)]
  adolescents[, union_expanded_ambiguous := as.integer(
    expanded_nested_match & (n_child_stepchild != 1L | n_son_daughter_in_law != 1L)
  )]
  adolescents[, household_cluster := sprintf(
    "%d-%07d", year_value, match(household_key_raw, unique(household_key_raw))
  )]

  adolescents[, `:=`(
    year = Ano,
    quarter = Trimestre,
    uf = UF,
    region = region_from_uf(UF),
    capital_code = Capital,
    metro_code = RM_RIDE,
    upa = UPA,
    stratum = Estrato,
    annual_calibrated_weight = V1032,
    annual_uncalibrated_weight = V1031,
    person_order = V2003,
    household_role_code = V2005,
    sex_code = V2007,
    birth_day = fifelse(V2008 %in% 1:31, V2008, NA_integer_),
    birth_month = fifelse(V20081 %in% 1:12, V20081, NA_integer_),
    birth_year = fifelse(V20082 %between% c(1900L, year_value), V20082, NA_integer_),
    age = V2009,
    race_color_code = V2010,
    urban_rural_code = V1022,
    area_type_code = V1023,
    school_attendance = fifelse(V3002 %in% c(1L, 2L), as.integer(V3002 == 1L), NA_integer_),
    education_level_code = VD3004,
    years_education_code = VD3005,
    worked_reference_week = fifelse(V4001 %in% c(1L, 2L), as.integer(V4001 == 1L), NA_integer_),
    usual_monthly_earnings_raw = VD4019,
    usual_weekly_hours_raw = VD4031
  )]

  keep <- c(
    "year", "quarter", "uf", "region", "capital_code", "metro_code", "upa", "stratum",
    "household_cluster", "person_order", "annual_calibrated_weight", "annual_uncalibrated_weight",
    "age", "sex_code", "birth_day", "birth_month", "birth_year", "race_color_code",
    "urban_rural_code", "area_type_code", "household_role_code", "household_members",
    "n_responsible", "n_spouse", "n_child_stepchild", "n_son_daughter_in_law",
    "union_conservative", "union_expanded", "union_expanded_ambiguous",
    "school_attendance", "education_level_code", "years_education_code",
    "worked_reference_week", "usual_monthly_earnings_raw", "usual_weekly_hours_raw"
  )
  keep <- intersect(keep, names(adolescents))
  output <- adolescents[, ..keep]
  setorder(output, uf, upa, household_cluster, person_order)

  year_dir <- file.path(data_dir, paste0("year=", year_value))
  dir.create(year_dir, recursive = TRUE, showWarnings = FALSE)
  output_path <- file.path(year_dir, "part-0.parquet")
  write_parquet(output, output_path, compression = "zstd")

  validation[[i]] <- output[, .(
    source_rows = nrow(raw),
    adolescent_rows = .N,
    ufs = uniqueN(uf),
    strata = uniqueN(stratum),
    upas = uniqueN(upa),
    households = uniqueN(household_cluster),
    age_min = min(age, na.rm = TRUE),
    age_max = max(age, na.rm = TRUE),
    male_rows = sum(sex_code == 1L, na.rm = TRUE),
    female_rows = sum(sex_code == 2L, na.rm = TRUE),
    weight_missing = sum(is.na(annual_calibrated_weight)),
    weight_nonpositive = sum(annual_calibrated_weight <= 0, na.rm = TRUE),
    weighted_population_14_19 = sum(annual_calibrated_weight, na.rm = TRUE),
    union_conservative_n = sum(union_conservative, na.rm = TRUE),
    union_expanded_n = sum(union_expanded, na.rm = TRUE),
    union_expanded_ambiguous_n = sum(union_expanded_ambiguous, na.rm = TRUE),
    duplicate_person_keys = .N - uniqueN(paste(household_cluster, person_order, sep = "-")),
    output_bytes = file.info(output_path)$size,
    dictionary = dictionary_name,
    dictionary_sha256 = digest(dictionary_path, algo = "sha256", file = TRUE),
    source_sha256 = current_hash
  ), by = .(year)]

  elapsed_year <- as.numeric(difftime(Sys.time(), year_start, units = "secs"))
  year_logs[[i]] <- data.table(
    year = year_value,
    elapsed_seconds = elapsed_year,
    source_rows = nrow(raw),
    adolescent_rows = nrow(output),
    output_bytes = file.info(output_path)$size,
    finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  cat(sprintf("year=%d source_rows=%d adolescent_rows=%d elapsed_seconds=%.2f\n",
              year_value, nrow(raw), nrow(output), elapsed_year))
  rm(raw, household, adolescents, output)
  gc(verbose = FALSE)
}

validation_dt <- rbindlist(validation, fill = TRUE)
year_logs_dt <- rbindlist(year_logs, fill = TRUE)
fwrite(validation_dt, file.path(audit_dir, "PNADC_OFFICIAL_BUILD_VALIDATION.csv"))
fwrite(year_logs_dt, file.path(log_dir, "02_build_pnadc_by_year.csv"))

schema <- data.table(
  field = names(read_parquet(file.path(data_dir, paste0("year=", manifest$year[[1L]]), "part-0.parquet"), as_data_frame = TRUE)),
  description = c(
    "reference year", "interview quarter within annual first-visit file", "state code", "macroregion derived from UF",
    "capital code", "metropolitan/RIDE code", "primary sampling unit", "survey stratum",
    "non-reversible within-year household serial", "person order within household", "IBGE annual calibrated weight V1032",
    "IBGE annual uncalibrated weight V1031", "age in completed years", "sex code (1 male, 2 female)",
    "valid birth day; invalid codes set missing", "valid birth month; invalid codes set missing", "valid birth year; invalid codes set missing",
    "IBGE race/color code", "urban/rural code", "area-type code", "household-role code V2005", "number of household members",
    "number of household heads", "number of head spouses", "number of children/stepchildren of head", "number of sons/daughters-in-law",
    "spouse of head or adolescent head with spouse present", "conservative union plus plausible nested child/in-law pairing",
    "expanded-only pairing has multiple or unmatched candidate roles", "currently attends school", "derived education-level code",
    "derived years-of-education code", "worked at least one hour in reference week", "raw derived habitual monthly labor income",
    "raw derived habitual weekly hours"
  ),
  unit = c(
    "year", "quarter", "IBGE code", "label", "IBGE code", "IBGE code", "identifier", "identifier",
    "pseudonymous identifier", "order", "persons", "persons", "completed years", "code", "day", "month", "year",
    "code", "code", "code", "code", "persons", "persons", "persons", "persons", "persons", "binary", "binary", "binary",
    "binary", "code", "code", "binary", "Brazilian reais/month (raw code)", "hours/week (raw code)"
  ),
  source = "IBGE PNADC annual first visit; year-specific official dictionary",
  notes = "All raw household selection keys were dropped after union construction; data restricted to ages 14-19"
)
fwrite(schema, file.path(data_dir, "SCHEMA.csv"))

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(start_time, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("years=%d", nrow(validation_dt)),
  sprintf("source_rows=%s", format(sum(validation_dt$source_rows), scientific = FALSE)),
  sprintf("adolescent_rows=%s", format(sum(validation_dt$adolescent_rows), scientific = FALSE)),
  sprintf("output_bytes=%s", format(sum(validation_dt$output_bytes), scientific = FALSE)),
  "physical_uncompressed_raw_bytes=0",
  "max_parallel_processes=1",
  "raw_local_project_files_modified=0"
)
writeLines(log_lines, file.path(log_dir, "02_build_pnadc.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
