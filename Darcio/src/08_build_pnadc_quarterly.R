#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(readxl)
  library(arrow)
  library(digest)
  library(survey)
  library(parallel)
})

start_time <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
darcio_root <- file.path(project_root, "Darcio")
audit_dir <- file.path(darcio_root, "outputs", "audit")
data_dir <- file.path(darcio_root, "outputs", "data", "pnadc_quarterly_adolescents")
log_dir <- file.path(darcio_root, "outputs", "logs")
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
manifest <- fread(file.path(audit_dir, "PNADC_QUARTERLY_ACQUISITION_MANIFEST.csv"))
setorder(manifest, year, quarter)

dictionary_path <- file.path(
  darcio_root, "references", "pnadc_quarterly_documentation",
  "dicionario_PNADC_microdados_trimestral.xls"
)
fields <- c(
  "Ano", "Trimestre", "UF", "Capital", "RM_RIDE", "UPA", "Estrato",
  "V1008", "V1014", "V1016", "V1022", "V1023", "V1027", "V1028", "V2003",
  "V2005", "V2007", "V2008", "V20081", "V20082", "V2009", "V2010",
  "V3002", "VD3004", "VD3005", "V4001", "VD4019", "VD4031"
)

raw_dictionary <- suppressMessages(as.data.table(read_excel(dictionary_path, col_names = FALSE)))
setnames(raw_dictionary, paste0("column_", seq_len(ncol(raw_dictionary))))
field_map <- raw_dictionary[column_3 %chin% fields, .(
  field = column_3,
  start = suppressWarnings(as.integer(column_1)),
  width = suppressWarnings(as.integer(column_2)),
  description = as.character(column_5),
  coding = as.character(column_7),
  documented_period = as.character(column_8)
)]
if (!setequal(field_map$field, fields)) stop("Quarterly dictionary lacks required fields: ", paste(setdiff(fields, field_map$field), collapse = ", "))
field_map[, end := start + width - 1L]
setorder(field_map, start)
fwrite(field_map, file.path(audit_dir, "PNADC_QUARTERLY_DICTIONARY_POSITIONS.csv"))

meminfo <- readLines("/proc/meminfo", warn = FALSE)
mem_total_kib <- as.numeric(sub("^MemTotal:[[:space:]]+([0-9]+).*$", "\\1", grep("^MemTotal:", meminfo, value = TRUE)))
mem_available_kib <- as.numeric(sub("^MemAvailable:[[:space:]]+([0-9]+).*$", "\\1", grep("^MemAvailable:", meminfo, value = TRUE)))
estimated_worker_kib <- 2.2 * 1024^2
workers_by_memory <- max(1L, floor((mem_available_kib - 4 * 1024^2) / estimated_worker_kib))
workers <- min(4L, max(1L, workers_by_memory), max(1L, floor(detectCores() / 2L)))
if ((mem_total_kib - mem_available_kib) / mem_total_kib > 0.70) workers <- 1L

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

read_selected <- function(zip_path, member_name, map, chunk_lines = 22000L) {
  con <- unz(zip_path, member_name, open = "rt", encoding = "ASCII")
  on.exit(close(con), add = TRUE)
  pieces <- list()
  index <- 0L
  repeat {
    lines <- readLines(con, n = chunk_lines, warn = FALSE)
    if (!length(lines)) break
    index <- index + 1L
    values <- setNames(vector("list", nrow(map)), map$field)
    for (j in seq_len(nrow(map))) values[[j]] <- trimws(substr(lines, map$start[[j]], map$end[[j]]))
    pieces[[index]] <- as.data.table(values)
    rm(lines, values)
    if (index %% 4L == 0L) gc(verbose = FALSE)
  }
  rbindlist(pieces, use.names = TRUE, fill = TRUE)
}

as_integer_blank_na <- function(x) {
  x[x == ""] <- NA_character_
  suppressWarnings(as.integer(x))
}

as_numeric_blank_na <- function(x) {
  x[x == ""] <- NA_character_
  suppressWarnings(as.numeric(x))
}

extract_svyby <- function(result, groups) {
  out <- as.data.table(result)
  se_column <- grep("^se($|\\.)", names(out), value = TRUE)[1L]
  estimate_column <- setdiff(names(out), c(groups, se_column))[1L]
  setnames(out, c(estimate_column, se_column), c("population", "population_se"))
  keep <- c(groups, "population", "population_se")
  out[, ..keep]
}

estimate_total_population <- function(d, year_value, quarter_value) {
  design <- svydesign(
    ids = ~upa_design,
    strata = ~stratum_design,
    weights = ~quarterly_calibrated_weight,
    data = d,
    nest = TRUE,
    check.strata = FALSE
  )
  levels <- list(UF = "uf", region = "region")
  results <- rbindlist(lapply(names(levels), function(level) {
    group <- levels[[level]]
    result <- extract_svyby(
      svyby(~one, as.formula(paste0("~", group)), design, svytotal, vartype = "se", na.rm = TRUE),
      group
    )
    counts <- d[, .(unweighted_n = .N), by = group]
    result <- merge(result, counts, by = group, all.x = TRUE)
    result[, `:=`(
      geography_level = level,
      geography_value = as.character(get(group))
    )]
    result[, .(geography_level, geography_value, population, population_se, unweighted_n)]
  }), use.names = TRUE)
  brazil_estimate <- svytotal(~one, design, na.rm = TRUE)
  brazil <- data.table(
    geography_level = "Brazil",
    geography_value = "Brazil",
    population = as.numeric(coef(brazil_estimate)),
    population_se = as.numeric(SE(brazil_estimate)),
    unweighted_n = nrow(d)
  )
  output <- rbindlist(list(results, brazil), use.names = TRUE)
  output[, `:=`(
    year = year_value,
    quarter = quarter_value,
    population_cv = population_se / population,
    ci_lower = pmax(0, population - qnorm(0.975) * population_se),
    ci_upper = population + qnorm(0.975) * population_se
  )]
  output
}

process_quarter <- function(i) {
  file_start <- Sys.time()
  row <- manifest[i]
  year_value <- row$year
  quarter_value <- row$quarter
  zip_path <- file.path(project_root, row$relative_path)
  if (!identical(digest(zip_path, algo = "sha256", file = TRUE), row$sha256)) stop("Hash mismatch: ", zip_path)
  raw <- read_selected(zip_path, row$member_name, field_map)

  character_fields <- intersect(c("UPA", "Estrato", "V1008", "V1014", "V2003"), names(raw))
  for (field in character_fields) set(raw, j = field, value = trimws(raw[[field]]))
  integer_fields <- setdiff(intersect(fields, names(raw)), c(character_fields, "V1027", "V1028", "VD4019"))
  for (field in integer_fields) set(raw, j = field, value = as_integer_blank_na(raw[[field]]))
  for (field in intersect(c("V1027", "V1028", "VD4019"), names(raw))) {
    set(raw, j = field, value = as_numeric_blank_na(raw[[field]]))
  }
  if (any(raw$Ano != year_value, na.rm = TRUE) || any(raw$Trimestre != quarter_value, na.rm = TRUE)) {
    stop("File period disagrees with manifest: ", basename(zip_path))
  }
  raw[, `:=`(
    year = year_value,
    quarter = quarter_value,
    visit = V1016,
    uf = UF,
    region = region_from_uf(UF),
    upa_design = factor(paste(year_value, quarter_value, UPA, sep = "-")),
    stratum_design = factor(paste(year_value, quarter_value, Estrato, sep = "-")),
    quarterly_calibrated_weight = V1028,
    one = 1
  )]
  if (anyNA(raw$quarterly_calibrated_weight) || any(raw$quarterly_calibrated_weight <= 0)) {
    stop("Invalid quarterly calibrated weight in ", year_value, "Q", quarter_value)
  }
  total_population <- estimate_total_population(raw, year_value, quarter_value)

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
  adolescents[, household_cluster := paste(
    digest2int(household_key_raw, seed = 13811L),
    digest2int(household_key_raw, seed = 27162L), sep = "-"
  )]
  adolescents[, `:=`(
    capital_code = Capital,
    metro_code = RM_RIDE,
    upa = UPA,
    stratum = Estrato,
    quarterly_uncalibrated_weight = V1027,
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
    "year", "quarter", "visit", "uf", "region", "capital_code", "metro_code", "upa", "stratum",
    "household_cluster", "person_order", "quarterly_calibrated_weight", "quarterly_uncalibrated_weight",
    "age", "sex_code", "birth_day", "birth_month", "birth_year", "race_color_code",
    "urban_rural_code", "area_type_code", "household_role_code", "household_members",
    "n_responsible", "n_spouse", "n_child_stepchild", "n_son_daughter_in_law",
    "union_conservative", "union_expanded", "union_expanded_ambiguous",
    "school_attendance", "education_level_code", "years_education_code",
    "worked_reference_week", "usual_monthly_earnings_raw", "usual_weekly_hours_raw"
  )
  output <- adolescents[, ..keep]
  setorder(output, uf, upa, household_cluster, person_order)
  quarter_dir <- file.path(data_dir, sprintf("year=%d", year_value), sprintf("quarter=%d", quarter_value))
  dir.create(quarter_dir, recursive = TRUE, showWarnings = FALSE)
  output_path <- file.path(quarter_dir, "part-0.parquet")
  write_parquet(output, output_path, compression = "zstd")

  validation <- data.table(
    year = year_value,
    quarter = quarter_value,
    source_rows = nrow(raw),
    adolescent_rows = nrow(output),
    ufs = uniqueN(raw$uf),
    strata = uniqueN(raw$stratum_design),
    upas = uniqueN(raw$upa_design),
    households = uniqueN(raw$household_key_raw),
    male_rows = sum(output$sex_code == 1L, na.rm = TRUE),
    female_rows = sum(output$sex_code == 2L, na.rm = TRUE),
    weight_missing = sum(is.na(output$quarterly_calibrated_weight)),
    weight_nonpositive = sum(output$quarterly_calibrated_weight <= 0, na.rm = TRUE),
    weighted_population_14_19 = sum(output$quarterly_calibrated_weight, na.rm = TRUE),
    union_conservative_n = sum(output$union_conservative, na.rm = TRUE),
    union_expanded_n = sum(output$union_expanded, na.rm = TRUE),
    union_expanded_ambiguous_n = sum(output$union_expanded_ambiguous, na.rm = TRUE),
    duplicate_person_keys = nrow(output) - uniqueN(paste(output$household_cluster, output$person_order, sep = "-")),
    output_bytes = file.info(output_path)$size,
    source_sha256 = row$sha256,
    elapsed_seconds = as.numeric(difftime(Sys.time(), file_start, units = "secs")),
    finished_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  cat(sprintf("year=%d quarter=%d source_rows=%d adolescent_rows=%d elapsed_seconds=%.2f\n",
              year_value, quarter_value, validation$source_rows, validation$adolescent_rows, validation$elapsed_seconds))
  list(validation = validation, total_population = total_population)
}

options(survey.lonely.psu = "adjust")
results <- mclapply(seq_len(nrow(manifest)), process_quarter, mc.cores = workers, mc.preschedule = FALSE)
if (any(vapply(results, inherits, logical(1L), what = "try-error"))) stop("At least one quarterly worker failed")
validation <- rbindlist(lapply(results, `[[`, "validation"), use.names = TRUE)
total_population <- rbindlist(lapply(results, `[[`, "total_population"), use.names = TRUE)
setorder(validation, year, quarter)
setorder(total_population, year, quarter, geography_level, geography_value)
fwrite(validation, file.path(audit_dir, "PNADC_QUARTERLY_BUILD_VALIDATION.csv"))
fwrite(total_population, file.path(darcio_root, "outputs", "data", "QUARTERLY_TOTAL_POPULATION_DENOMINATORS.csv"))
write_parquet(total_population, file.path(darcio_root, "outputs", "data", "QUARTERLY_TOTAL_POPULATION_DENOMINATORS.parquet"), compression = "zstd")

if (any(validation$ufs != 27L) || any(validation$weight_missing != 0L) ||
    any(validation$weight_nonpositive != 0L) || any(validation$duplicate_person_keys != 0L)) {
  stop("Quarterly PNADC validation failed")
}

schema_path <- file.path(data_dir, "SCHEMA.csv")
first_output <- as.data.table(read_parquet(file.path(data_dir, "year=2013", "quarter=1", "part-0.parquet")))
schema <- data.table(
  field = names(first_output),
  source = "IBGE PNADC quarterly; official dictionary Dicionario_e_input_20221031",
  note = "Ages 14-19 only; V1028 is quarterly calibrated weight; household selection key replaced by two-seed digest2int identifier"
)
fwrite(schema, schema_path)

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(start_time, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("workers=%d", workers),
  sprintf("source_rows=%s", format(sum(validation$source_rows), scientific = FALSE)),
  sprintf("adolescent_rows=%s", format(sum(validation$adolescent_rows), scientific = FALSE)),
  sprintf("output_bytes=%s", format(sum(validation$output_bytes), scientific = FALSE)),
  sprintf("mem_total_kib=%s", format(mem_total_kib, scientific = FALSE)),
  sprintf("mem_available_start_kib=%s", format(mem_available_kib, scientific = FALSE)),
  "physical_uncompressed_raw_bytes=0",
  "weight=V1028 quarterly calibrated; not divided by four",
  "raw_files_modified=0"
)
writeLines(log_lines, file.path(log_dir, "08_build_pnadc_quarterly.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
