#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(survey)
  library(yaml)
})

start_time <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
darcio_root <- file.path(project_root, "Darcio")
config <- read_yaml(file.path(darcio_root, "config", "analysis.yml"))
input_dir <- file.path(darcio_root, "outputs", "data", "pnadc_adolescents")
audit_dir <- file.path(darcio_root, "outputs", "audit")
output_dir <- file.path(darcio_root, "outputs", "data")
log_dir <- file.path(darcio_root, "outputs", "logs")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

options(survey.lonely.psu = config$denominators$lonely_psu_adjustment)
cv_max <- as.numeric(config$denominators$maximum_cell_cv)
n_min <- as.integer(config$denominators$minimum_unweighted_cell_n)
required_share <- as.numeric(config$denominators$required_share_passing)
hard_cv <- as.numeric(config$denominators$hard_maximum_cell_cv)

parquet_files <- list.files(input_dir, pattern = "\\.parquet$", recursive = TRUE, full.names = TRUE)
if (!length(parquet_files)) stop("No PNADC adolescent Parquet files found")
pnadc <- rbindlist(lapply(parquet_files, function(path) as.data.table(read_parquet(path))), use.names = TRUE)
pnadc[, `:=`(
  year = as.integer(year),
  age = as.integer(age),
  sex_code = as.integer(sex_code),
  uf = as.integer(uf),
  upa = factor(paste(year, upa, sep = "-")),
  stratum = factor(paste(year, stratum, sep = "-")),
  one = 1
)]
if (anyNA(pnadc$annual_calibrated_weight) || any(pnadc$annual_calibrated_weight <= 0)) {
  stop("Annual calibrated weights must be present and positive")
}

extract_svyby <- function(result, group_names) {
  out <- as.data.table(result)
  variance_columns <- grep("^(se|cv|ci)($|\\.)", names(out), value = TRUE)
  estimate_col <- setdiff(names(out), c(group_names, variance_columns))[1L]
  se_candidates <- grep("^se($|\\.)", names(out), value = TRUE)
  if (!length(se_candidates)) stop("Could not identify standard-error column returned by svyby")
  setnames(out, c(estimate_col, se_candidates[[1L]]), c("population", "population_se"))
  columns_to_keep <- c(group_names, "population", "population_se")
  out[, ..columns_to_keep]
}

estimate_one_year <- function(year_value) {
  d <- pnadc[year == year_value]
  design <- svydesign(
    ids = ~upa,
    strata = ~stratum,
    weights = ~annual_calibrated_weight,
    data = d,
    nest = TRUE,
    check.strata = FALSE
  )

  estimate_level <- function(level) {
    geo_vars <- switch(level, UF = "uf", region = "region", Brazil = character())
    groups_sex <- c(geo_vars, "age", "sex_code")
    groups_combined <- c(geo_vars, "age")
    formula_sex <- as.formula(paste("~", paste(groups_sex, collapse = "+")))
    formula_combined <- as.formula(paste("~", paste(groups_combined, collapse = "+")))

    sex_est <- extract_svyby(
      svyby(~one, formula_sex, design, svytotal, vartype = "se", na.rm = TRUE, keep.var = TRUE),
      groups_sex
    )
    sex_n <- d[, .(unweighted_n = .N), by = groups_sex]
    sex_est <- merge(sex_est, sex_n, by = groups_sex, all.x = TRUE)
    sex_est[, sex := fifelse(sex_code == 1L, "male", fifelse(sex_code == 2L, "female", NA_character_))]

    combined_est <- extract_svyby(
      svyby(~one, formula_combined, design, svytotal, vartype = "se", na.rm = TRUE, keep.var = TRUE),
      groups_combined
    )
    combined_n <- d[, .(unweighted_n = .N), by = groups_combined]
    combined_est <- merge(combined_est, combined_n, by = groups_combined, all.x = TRUE)
    combined_est[, `:=`(sex_code = NA_integer_, sex = "combined")]

    if (level == "UF") {
      sex_est[, geography_value := as.character(uf)]
      combined_est[, geography_value := as.character(uf)]
    } else if (level == "region") {
      sex_est[, geography_value := as.character(region)]
      combined_est[, geography_value := as.character(region)]
    } else {
      sex_est[, geography_value := "Brazil"]
      combined_est[, geography_value := "Brazil"]
    }
    out <- rbindlist(list(sex_est, combined_est), use.names = TRUE, fill = TRUE)
    out[, `:=`(year = year_value, geography_level = level)]
    out[, .(
      year, geography_level, geography_value, age, sex, sex_code,
      population, population_se, unweighted_n
    )]
  }

  rbindlist(lapply(c("UF", "region", "Brazil"), estimate_level), use.names = TRUE)
}

years <- sort(unique(pnadc$year))
denominators <- rbindlist(lapply(years, function(y) {
  cat(sprintf("estimating_design_denominators_year=%d\n", y))
  estimate_one_year(y)
}), use.names = TRUE)
denominators[, `:=`(
  population_cv = population_se / population,
  ci_lower = pmax(0, population - qnorm(0.975) * population_se),
  ci_upper = population + qnorm(0.975) * population_se
)]
denominators[, precision_pass := !is.na(population_cv) & population_cv <= cv_max & unweighted_n >= n_min]
denominators[, fixed_denominator_simplification := TRUE]
setorder(denominators, geography_level, year, geography_value, sex, age)

fwrite(denominators, file.path(output_dir, "DENOMINATORS_AGE_SEX.csv"))
write_parquet(denominators, file.path(output_dir, "DENOMINATORS_AGE_SEX.parquet"), compression = "zstd")

selection <- denominators[age == 15L, .(
  cells = .N,
  share_passing = mean(precision_pass),
  minimum_unweighted_n = min(unweighted_n),
  median_unweighted_n = median(unweighted_n),
  maximum_cv = max(population_cv, na.rm = TRUE),
  median_cv = median(population_cv, na.rm = TRUE)
), by = geography_level]
selection[, order := match(geography_level, c("UF", "region", "Brazil"))]
setorder(selection, order)
selection[, eligible := share_passing >= required_share & maximum_cv <= hard_cv]
selected_geography <- selection[eligible == TRUE, geography_level][1L]
if (is.na(selected_geography) || !length(selected_geography)) selected_geography <- "Brazil"
selection[, selected := geography_level == selected_geography]
fwrite(selection, file.path(audit_dir, "DENOMINATOR_PRECISION_SUMMARY.csv"))

selection_lines <- c(
  "# Geography selection from denominator precision",
  "",
  sprintf("Created: %s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  "",
  "This decision uses only PNADC denominator precision, before any post-reform effect is estimated.",
  "The annual calibrated first-visit weight is V1032 and is not divided by four.",
  sprintf("A cell passes when unweighted n >= %d and CV <= %.0f%%.", n_min, 100 * cv_max),
  sprintf("A geography is eligible when at least %.0f%% of age-15 sex-specific/combined cells pass and no CV exceeds %.0f%%.",
          100 * required_share, 100 * hard_cv),
  "",
  "| Level | Cells | Share passing | Minimum n | Median n | Maximum CV | Median CV | Eligible | Selected |",
  "|---|---:|---:|---:|---:|---:|---:|:---:|:---:|",
  apply(selection, 1L, function(row) sprintf(
    "| %s | %s | %.3f | %s | %.1f | %.3f | %.3f | %s | %s |",
    row[["geography_level"]], row[["cells"]], as.numeric(row[["share_passing"]]),
    row[["minimum_unweighted_n"]], as.numeric(row[["median_unweighted_n"]]),
    as.numeric(row[["maximum_cv"]]), as.numeric(row[["median_cv"]]),
    row[["eligible"]], row[["selected"]]
  )),
  "",
  sprintf("**Selected primary geography: %s.**", selected_geography),
  "",
  "UF estimates remain available as a pre-specified sensitivity analysis. Normal-approximation intervals use Taylor linearization with the official strata, UPAs, and weights; lonely PSUs use the documented `adjust` rule."
)
writeLines(selection_lines, file.path(audit_dir, "GEOGRAPHY_SELECTION.md"))

validation <- denominators[, .(
  cells = .N,
  cells_passing = sum(precision_pass),
  minimum_population = min(population),
  maximum_population = max(population),
  minimum_unweighted_n = min(unweighted_n),
  maximum_cv = max(population_cv, na.rm = TRUE),
  missing_estimates = sum(is.na(population) | is.na(population_se))
), by = .(year, geography_level)]
fwrite(validation, file.path(audit_dir, "DENOMINATOR_VALIDATION_BY_YEAR.csv"))

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(start_time, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("input_rows=%s", format(nrow(pnadc), scientific = FALSE)),
  sprintf("output_cells=%s", format(nrow(denominators), scientific = FALSE)),
  sprintf("selected_geography=%s", selected_geography),
  sprintf("survey_version=%s", as.character(packageVersion("survey"))),
  sprintf("weight=%s", config$data$pnadc_weight),
  "weight_divided_by_four=false",
  "variance=Taylor linearization using annual strata and UPAs",
  "max_parallel_processes=1"
)
writeLines(log_lines, file.path(log_dir, "03_build_denominators.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
