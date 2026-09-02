#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(readxl)
  library(survey)
  library(arrow)
  library(digest)
})

start_time <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
darcio_root <- file.path(project_root, "Darcio")
raw_dir <- file.path(darcio_root, "data", "raw_external", "pnadc_visita1")
doc_dir <- file.path(darcio_root, "references", "pnadc_documentation")
audit_dir <- file.path(darcio_root, "outputs", "audit")
data_dir <- file.path(darcio_root, "outputs", "data")
log_dir <- file.path(darcio_root, "outputs", "logs")
manifest <- fread(file.path(audit_dir, "PNADC_EXTERNAL_ACQUISITION_MANIFEST.csv"))
build_validation <- fread(file.path(audit_dir, "PNADC_OFFICIAL_BUILD_VALIDATION.csv"))
options(survey.lonely.psu = "adjust")

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

fields <- c("Ano", "UF", "UPA", "Estrato", "V1032", "V2007")
read_map <- function(path) {
  raw <- suppressMessages(as.data.table(read_excel(path, col_names = FALSE)))
  setnames(raw, paste0("column_", seq_len(ncol(raw))))
  map <- raw[column_3 %chin% fields, .(
    field = column_3,
    start = as.integer(column_1),
    width = as.integer(column_2)
  )]
  if (!setequal(map$field, fields)) stop("Minimal all-person dictionary fields are incomplete: ", path)
  map[, end := start + width - 1L]
  setorder(map, start)
  map
}

read_minimal <- function(zip_path, member_name, map, chunk_lines = 30000L) {
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
  rbindlist(pieces, use.names = TRUE)
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

extract_svyby <- function(result, groups) {
  out <- as.data.table(result)
  se_column <- grep("^se($|\\.)", names(out), value = TRUE)[1L]
  estimate_column <- setdiff(names(out), c(groups, se_column))[1L]
  setnames(out, c(estimate_column, se_column), c("population", "population_se"))
  keep <- c(groups, "population", "population_se")
  out[, ..keep]
}

estimate_level <- function(design, d, level, combined = TRUE) {
  geo <- switch(level, UF = "uf", region = "region", Brazil = character())
  groups <- c(geo, if (!combined) "sex_code" else character())
  by_formula <- if (length(groups)) as.formula(paste("~", paste(groups, collapse = "+"))) else ~one_group
  if (!length(groups)) {
    d[, one_group := "Brazil"]
    design <- update(design, one_group = "Brazil")
    groups <- "one_group"
  }
  estimate <- extract_svyby(svyby(~one, by_formula, design, svytotal, vartype = "se", na.rm = TRUE), groups)
  counts <- d[, .(unweighted_n = .N), by = groups]
  estimate <- merge(estimate, counts, by = groups, all.x = TRUE)
  estimate[, `:=`(
    geography_level = level,
    geography_value = if (level == "UF") as.character(uf) else if (level == "region") as.character(region) else "Brazil",
    sex = if (combined) "combined" else fifelse(sex_code == 1L, "male", "female")
  )]
  estimate[, .(geography_level, geography_value, sex, population, population_se, unweighted_n)]
}

results <- list()
validation <- list()
for (i in seq_len(nrow(manifest))) {
  year_start <- Sys.time()
  year_value <- manifest$year[[i]]
  zip_path <- file.path(project_root, manifest$relative_path[[i]])
  if (!identical(digest(zip_path, algo = "sha256", file = TRUE), manifest$sha256[[i]])) stop("Hash mismatch: ", zip_path)
  dictionary <- file.path(doc_dir, dictionary_for_year(year_value))
  map <- read_map(dictionary)
  d <- read_minimal(zip_path, manifest$member_name[[i]], map)
  d[, `:=`(
    year = as.integer(Ano),
    uf = as.integer(UF),
    region = region_from_uf(as.integer(UF)),
    upa = factor(paste(year_value, UPA, sep = "-")),
    stratum = factor(paste(year_value, Estrato, sep = "-")),
    annual_calibrated_weight = suppressWarnings(as.numeric(V1032)),
    sex_code = as.integer(V2007),
    one = 1
  )]
  if (nrow(d) != build_validation[year == year_value]$source_rows) stop("All-person row count disagrees with first PNADC build")
  if (anyNA(d$annual_calibrated_weight) || any(d$annual_calibrated_weight <= 0)) stop("Invalid calibrated weight in ", year_value)
  design <- svydesign(ids = ~upa, strata = ~stratum, weights = ~annual_calibrated_weight,
                      data = d, nest = TRUE, check.strata = FALSE)
  year_result <- rbindlist(c(
    lapply(c("UF", "region", "Brazil"), function(level) estimate_level(design, d, level, combined = TRUE)),
    lapply(c("UF", "region", "Brazil"), function(level) estimate_level(design, d, level, combined = FALSE))
  ), use.names = TRUE)
  year_result[, year := year_value]
  year_result[, `:=`(
    population_cv = population_se / population,
    ci_lower = pmax(0, population - qnorm(0.975) * population_se),
    ci_upper = population + qnorm(0.975) * population_se
  )]
  results[[i]] <- year_result
  direct_population <- sum(d$annual_calibrated_weight)
  design_population <- year_result[geography_level == "Brazil" & sex == "combined"]$population
  validation[[i]] <- data.table(
    year = year_value,
    source_rows = nrow(d),
    ufs = uniqueN(d$uf),
    strata = uniqueN(d$stratum),
    upas = uniqueN(d$upa),
    weighted_population_direct = direct_population,
    weighted_population_design = design_population,
    exact_point_estimate_match = abs(direct_population - design_population) < 1e-6,
    elapsed_seconds = as.numeric(difftime(Sys.time(), year_start, units = "secs"))
  )
  cat(sprintf("year=%d all_person_rows=%d elapsed_seconds=%.2f\n", year_value, nrow(d), validation[[i]]$elapsed_seconds))
  rm(d, design, year_result)
  gc(verbose = FALSE)
}

population <- rbindlist(results, use.names = TRUE)
setcolorder(population, c(
  "year", "geography_level", "geography_value", "sex", "population", "population_se",
  "population_cv", "ci_lower", "ci_upper", "unweighted_n"
))
setorder(population, geography_level, year, geography_value, sex)
fwrite(population, file.path(data_dir, "TOTAL_POPULATION_DENOMINATORS.csv"))
write_parquet(population, file.path(data_dir, "TOTAL_POPULATION_DENOMINATORS.parquet"), compression = "zstd")
validation_dt <- rbindlist(validation)
fwrite(validation_dt, file.path(audit_dir, "TOTAL_POPULATION_BUILD_VALIDATION.csv"))
if (any(validation_dt$ufs != 27L) || any(!validation_dt$exact_point_estimate_match)) stop("Total-population validation failed")

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(start_time, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("source_rows=%s", format(sum(validation_dt$source_rows), scientific = FALSE)),
  sprintf("output_cells=%s", format(nrow(population), scientific = FALSE)),
  "microdata_output_rows=0",
  "weight=V1032; not divided by four",
  "variance=Taylor linearization with official strata and UPAs",
  "max_parallel_processes=1",
  "raw_files_modified=0"
)
writeLines(log_lines, file.path(log_dir, "03b_build_total_population.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
