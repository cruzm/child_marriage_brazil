#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(yaml)
})

started <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
root <- file.path(project_root, "Darcio")
data_dir <- file.path(root, "outputs", "data")
audit_dir <- file.path(root, "outputs", "audit")
log_dir <- file.path(root, "outputs", "logs")
cfg <- read_yaml(file.path(root, "config", "analysis.yml"))
lock <- read_yaml(file.path(root, "config", "specification_lock.yml"))

region_codes <- c(
  "North" = "1", "Northeast" = "2", "Southeast" = "3",
  "South" = "4", "Central-West" = "5"
)
region_names <- setNames(names(region_codes), region_codes)

decorate_quarterly <- function(x) {
  x[, `:=`(
    period = sprintf("%dQ%d", year, quarter),
    period_index = (year - 2013L) * 4L + quarter,
    trend_2018q4 = (year - 2018L) * 4L + quarter - 4L,
    calendar_quarter = factor(quarter, levels = 1:4),
    treated_age = as.integer(age == 15L),
    partial_2019q1 = as.integer(year == 2019L & quarter == 1L),
    post_full = as.integer(year > 2019L | (year == 2019L & quarter >= 2L)),
    pandemic = as.integer(year %in% c(2020L, 2021L)),
    short_run_clean = as.integer(year <= 2018L | (year == 2019L & quarter >= 2L)),
    full_dynamic = as.integer(!(year == 2019L & quarter == 1L)),
    exclude_pandemic = as.integer(!(year == 2019L & quarter == 1L) & !year %in% c(2020L, 2021L)),
    post_pandemic = as.integer(year >= 2022L)
  )]
  x[, event_time := fifelse(
    year < 2019L,
    (year - 2018L) * 4L + quarter - 5L,
    fifelse(year == 2019L & quarter == 1L, NA_integer_,
            (year - 2019L) * 4L + quarter - 2L)
  )]
  x
}

write_both <- function(x, stem) {
  fwrite(x, file.path(data_dir, paste0(stem, ".csv")), na = "")
  write_parquet(x, file.path(data_dir, paste0(stem, ".parquet")), compression = "zstd")
}

registry_monthly <- fread(file.path(data_dir, "REGISTRY_PERSON_EVENTS_MONTHLY.csv"))
registry_monthly <- registry_monthly[age %in% 15:19]
registry_monthly[, `:=`(
  quarter = as.integer(ceiling(month / 3)),
  geography_value = unname(region_codes[region])
)]
if (anyNA(registry_monthly$geography_value)) stop("Registry contains an unmapped region")

registry_region <- registry_monthly[, .(
  persons_married = sum(persons_married),
  opposite_sex_people = sum(opposite_sex_people),
  same_sex_people = sum(same_sex_people)
), by = .(year, quarter, geography_value, age, sex)]
registry_brazil <- registry_region[, .(
  persons_married = sum(persons_married),
  opposite_sex_people = sum(opposite_sex_people),
  same_sex_people = sum(same_sex_people)
), by = .(year, quarter, age, sex)][, geography_value := "Brazil"]
registry_uf <- registry_monthly[, .(
  persons_married = sum(persons_married),
  opposite_sex_people = sum(opposite_sex_people),
  same_sex_people = sum(same_sex_people)
), by = .(year, quarter, geography_value = as.character(uf_code), age, sex)]

q_denom <- fread(file.path(data_dir, "QUARTERLY_DENOMINATORS_AGE_SEX.csv"))
q_denom <- q_denom[age %in% 15:19]
denom_keep <- c(
  "year", "quarter", "geography_value", "age", "sex", "population",
  "population_se", "population_cv", "unweighted_n", "precision_pass"
)

join_panel <- function(numerator, level) {
  denominator <- q_denom[geography_level == level, ..denom_keep]
  keys <- c("year", "quarter", "geography_value", "age", "sex")
  if (anyDuplicated(numerator, by = keys) || anyDuplicated(denominator, by = keys)) {
    stop("Nonunique analytical key at level ", level)
  }
  panel <- merge(numerator, denominator, by = keys, all = TRUE)
  panel[, geography_level := level]
  panel[, geography := if (level == "region") unname(region_names[geography_value]) else geography_value]
  panel[, `:=`(
    formal_marriage_rate_100k = 100000 * persons_married / population,
    offset_log_population = log(population),
    fixed_denominator_simplification = TRUE
  )]
  decorate_quarterly(panel)
  setorder(panel, year, quarter, geography_value, sex, age)
  panel
}

region_panel <- join_panel(registry_region, "region")
brazil_panel <- join_panel(registry_brazil, "Brazil")
uf_panel <- join_panel(registry_uf, "UF")
write_both(region_panel, "REGISTRY_QUARTERLY_PANEL_REGION")
write_both(brazil_panel, "REGISTRY_QUARTERLY_PANEL_BRAZIL")
write_both(uf_panel, "REGISTRY_QUARTERLY_PANEL_UF_DIAGNOSTIC")

# Annual UF panel for the locked annual robustness and exposure DDD.
registry_annual <- fread(file.path(data_dir, "REGISTRY_PERSON_EVENTS_ANNUAL.csv"))[age %in% 15:19]
registry_annual[, geography_value := as.character(uf_code)]
annual_denom <- fread(file.path(data_dir, "DENOMINATORS_AGE_SEX.csv"))[
  geography_level == "UF" & age %in% 15:19,
  .(year, geography_value, age, sex, population, population_se, population_cv,
    unweighted_n, precision_pass)
]
annual_panel <- merge(
  registry_annual[, .(year, geography_value, age, sex, persons_married,
                      opposite_sex_people, same_sex_people)],
  annual_denom,
  by = c("year", "geography_value", "age", "sex"),
  all = FALSE
)
annual_panel[, `:=`(
  uf_code = as.integer(geography_value),
  formal_marriage_rate_100k = 100000 * persons_married / population,
  offset_log_population = log(population),
  treated_age = as.integer(age == 15L),
  post_annual = as.integer(year >= 2020L),
  partial_2019 = as.integer(year == 2019L),
  pandemic = as.integer(year %in% c(2020L, 2021L)),
  trend_2018 = year - 2018L,
  fixed_denominator_simplification = TRUE
)]
setorder(annual_panel, year, uf_code, sex, age)
write_both(annual_panel, "REGISTRY_ANNUAL_PANEL_UF")

# Annual affected-marriage, below-15, and mechanically diluted total-rate outcomes.
affected <- fread(file.path(data_dir, "REGISTRY_AFFECTED_MARRIAGES_ANNUAL.csv"))[
  composition == "all"
]
affected_region <- affected[, .(
  total_marriages = sum(total_marriages),
  affected_marriages_below_16 = sum(affected_marriages_below_16),
  marriages_at_least_one_below_15 = sum(marriages_at_least_one_below_15)
), by = .(year, geography_value = region)]
affected_region[, geography_level := "region"]
affected_brazil <- affected[, .(
  total_marriages = sum(total_marriages),
  affected_marriages_below_16 = sum(affected_marriages_below_16),
  marriages_at_least_one_below_15 = sum(marriages_at_least_one_below_15)
), by = year][, `:=`(geography_level = "Brazil", geography_value = "Brazil")]
secondary <- rbindlist(list(affected_region, affected_brazil), use.names = TRUE)
secondary[, `:=`(
  affected_share_below_16 = affected_marriages_below_16 / total_marriages,
  share_at_least_one_below_15 = marriages_at_least_one_below_15 / total_marriages
)]
total_population <- fread(file.path(data_dir, "TOTAL_POPULATION_DENOMINATORS.csv"))[
  sex == "combined", .(year, geography_level, geography_value,
                        total_population = population,
                        total_population_se = population_se)
]
secondary <- merge(
  secondary, total_population,
  by = c("year", "geography_level", "geography_value"), all.x = TRUE
)
secondary[, total_marriage_rate_100k := 100000 * total_marriages / total_population]
setorder(secondary, year, geography_level, geography_value)
write_both(secondary, "REGISTRY_ANNUAL_SECONDARY_OUTCOMES")

# Exposure is a marriage share, not a population incidence rate.
exposure_counts <- affected[year %in% 2013:2017, .(
  affected_2013_2017 = sum(affected_marriages_below_16),
  total_marriages_2013_2017 = sum(total_marriages)
), by = .(uf_code, uf, region)]
exposure_counts[, prelaw_affected_marriage_share_raw :=
                  affected_2013_2017 / total_marriages_2013_2017]

beta_binomial_nll <- function(log_ab, y, n) {
  a <- exp(log_ab[1L])
  b <- exp(log_ab[2L])
  -sum(lbeta(y + a, n - y + b) - lbeta(a, b))
}
raw_mean <- with(exposure_counts,
                 sum(affected_2013_2017) / sum(total_marriages_2013_2017))
raw_var <- var(exposure_counts$prelaw_affected_marriage_share_raw)
initial_precision <- max(2, raw_mean * (1 - raw_mean) / max(raw_var, 1e-10) - 1)
eb_fit <- optim(
  log(c(max(raw_mean * initial_precision, 0.01),
        max((1 - raw_mean) * initial_precision, 0.01))),
  beta_binomial_nll,
  y = exposure_counts$affected_2013_2017,
  n = exposure_counts$total_marriages_2013_2017,
  method = "BFGS",
  control = list(maxit = 10000, reltol = 1e-12)
)
if (eb_fit$convergence != 0L) stop("Beta-binomial exposure model did not converge")
eb_alpha <- exp(eb_fit$par[1L])
eb_beta <- exp(eb_fit$par[2L])
exposure_counts[, prelaw_affected_marriage_share_eb :=
                  (affected_2013_2017 + eb_alpha) /
                  (total_marriages_2013_2017 + eb_alpha + eb_beta)]
exposure_counts[, `:=`(
  exposure_raw_z = as.numeric(scale(prelaw_affected_marriage_share_raw)),
  exposure_eb_z = as.numeric(scale(prelaw_affected_marriage_share_eb)),
  eb_alpha = eb_alpha,
  eb_beta = eb_beta,
  exposure_training_years = "2013-2017",
  exposure_is_population_rate = FALSE
)]
holdout <- affected[year == 2018L, .(
  affected_2018 = affected_marriages_below_16,
  total_marriages_2018 = total_marriages,
  affected_share_2018 = affected_marriages_below_16 / total_marriages
), by = uf_code]
exposure_counts <- merge(exposure_counts, holdout, by = "uf_code", all.x = TRUE)
setorder(exposure_counts, uf_code)
write_both(exposure_counts, "PRELAW_EXPOSURE_UF")

# Fix synthetic-age weights using training data only; 2018 remains holdout.
synthetic_source <- region_panel[
  sex == "combined" & year <= 2018L & age %in% c(15L, 17L, 18L, 19L),
  .(year, quarter, geography_value, age, formal_marriage_rate_100k, population)
]
rates_wide <- dcast(
  synthetic_source, year + quarter + geography_value ~ age,
  value.var = "formal_marriage_rate_100k"
)
pop15 <- synthetic_source[age == 15L, .(year, quarter, geography_value, population_15 = population)]
rates_wide <- merge(rates_wide, pop15,
                    by = c("year", "quarter", "geography_value"))
training <- rates_wide[year %in% 2013:2017]
objective <- function(theta) {
  weights <- c(theta, 1 - sum(theta))
  predicted <- as.matrix(training[, .(`17`, `18`, `19`)]) %*% weights
  weighted.mean((training$`15` - predicted)^2, training$population_15)
}
synthetic_fit <- constrOptim(
  theta = c(1 / 3, 1 / 3),
  f = objective,
  grad = NULL,
  ui = rbind(c(1, 0), c(0, 1), c(-1, -1)),
  ci = c(0, 0, -1),
  control = list(reltol = 1e-12, maxit = 10000)
)
synthetic_weights <- c(synthetic_fit$par, 1 - sum(synthetic_fit$par))
names(synthetic_weights) <- c("17", "18", "19")
rates_wide[, synthetic_rate :=
             `17` * synthetic_weights["17"] +
             `18` * synthetic_weights["18"] +
             `19` * synthetic_weights["19"]]
rmspe <- rates_wide[, .(
  rmspe = sqrt(weighted.mean((`15` - synthetic_rate)^2, population_15)),
  observations = .N
), by = .(sample = fifelse(year <= 2017L, "training_2013_2017", "holdout_2018"))]
weight_table <- data.table(
  donor_age = as.integer(names(synthetic_weights)),
  weight = as.numeric(synthetic_weights),
  training_period = "2013Q1-2017Q4",
  holdout_period = "2018Q1-2018Q4",
  post_information_used = FALSE,
  optimizer_convergence = synthetic_fit$convergence
)
fwrite(weight_table, file.path(data_dir, "SYNTHETIC_AGE_WEIGHTS_PRELAW.csv"))
fwrite(rmspe, file.path(audit_dir, "SYNTHETIC_AGE_PRELAW_FIT.csv"))

# Decorated union cells for the locked cell-level analysis.
union_cells <- fread(file.path(data_dir, "PNADC_UNION_CELL_ESTIMATES.csv"))
union_cells <- decorate_quarterly(union_cells)
union_cells[, `:=`(
  union_conservative_variance = union_conservative_se^2,
  union_expanded_variance = union_expanded_se^2
)]
setorder(union_cells, year, quarter, geography_level, geography_value, sex, age)
write_both(union_cells, "PNADC_UNION_ANALYTIC_CELLS")

# Machine-readable schemas and provenance.
dictionary <- rbindlist(list(
  data.table(dataset = "REGISTRY_QUARTERLY_PANEL_REGION", variable = c(
    "year", "quarter", "geography_value", "age", "sex", "persons_married",
    "population", "population_se", "formal_marriage_rate_100k", "post_full",
    "partial_2019q1", "event_time", "pandemic"
  ), unit = c(
    "year", "1-4", "IBGE region code", "completed years at registration", "category",
    "persons in registered marriages", "resident persons", "resident persons SE",
    "persons per 100,000", "indicator", "indicator", "quarters", "indicator"
  ), source = c(rep("IBGE SIDRA 4406", 6), rep("IBGE PNADC quarterly V1028", 3),
                rep("derived from legal timing", 4)),
  rule = c(
    "registration year", "registration month aggregated to quarter", "five regions",
    "exact categories 15-19", "combined/female/male", "frequency-weighted; no expansion",
    "Taylor survey total", "Taylor survey SE", "100000*persons_married/population",
    "starts 2019Q2", "equals one only in 2019Q1", "2018Q4=-1; 2019Q2=0; Q1 omitted",
    "2020-2021"
  )),
  data.table(dataset = "PRELAW_EXPOSURE_UF", variable = c(
    "prelaw_affected_marriage_share_raw", "prelaw_affected_marriage_share_eb",
    "exposure_raw_z", "exposure_eb_z"
  ), unit = c("share", "posterior mean share", "pre-period SD", "pre-period SD"),
  source = "IBGE SIDRA 4406, 2013-2017 only",
  rule = c("affected marriages / all marriages", "beta-binomial empirical Bayes",
           "standardized across 27 UFs", "standardized across 27 UFs")),
  data.table(dataset = "PNADC_UNION_ANALYTIC_CELLS", variable = c(
    "union_conservative", "union_conservative_se", "union_expanded",
    "union_expanded_se", "unweighted_n"
  ), unit = c("prevalence", "design SE", "prevalence", "design SE", "sample persons"),
  source = "IBGE PNADC quarterly V1028/Estrato/UPA",
  rule = c("head-spouse construct", "Taylor linearization", "nested-pair robustness",
           "Taylor linearization", "unweighted cell size"))
), use.names = TRUE, fill = TRUE)
fwrite(dictionary, file.path(data_dir, "ANALYTIC_DATA_DICTIONARY.csv"))

# Acceptance tests for joins, treatment, ages, totals, and pre-only tuning.
combined_identity <- region_panel[, .(
  combined_count = persons_married[sex == "combined"],
  sex_sum_count = sum(persons_married[sex %in% c("female", "male")]),
  combined_population = population[sex == "combined"],
  sex_sum_population = sum(population[sex %in% c("female", "male")])
), by = .(year, quarter, geography_value, age)]
monthly_check <- registry_monthly[, .(monthly_total = sum(persons_married)),
                                  by = .(year, sex, age)]
quarterly_check <- region_panel[, .(quarterly_total = sum(persons_married)),
                                by = .(year, sex, age)]
monthly_check <- merge(monthly_check, quarterly_check, by = c("year", "sex", "age"))

tests <- rbindlist(list(
  data.table(test = "region panel has expected 3600 cells", passed = nrow(region_panel) == 3600L, observed = as.character(nrow(region_panel))),
  data.table(test = "Brazil panel has expected 720 cells", passed = nrow(brazil_panel) == 720L, observed = as.character(nrow(brazil_panel))),
  data.table(test = "UF diagnostic panel has expected 19440 cells", passed = nrow(uf_panel) == 19440L, observed = as.character(nrow(uf_panel))),
  data.table(test = "region analytical keys unique", passed = !anyDuplicated(region_panel, by = c("year", "quarter", "geography_value", "age", "sex")), observed = as.character(anyDuplicated(region_panel, by = c("year", "quarter", "geography_value", "age", "sex")))),
  data.table(test = "no missing joined region numerator/denominator", passed = all(complete.cases(region_panel[, .(persons_married, population, population_se)])), observed = as.character(sum(!complete.cases(region_panel[, .(persons_married, population, population_se)])))),
  data.table(test = "quarter sums equal Registry month sums", passed = all(monthly_check$monthly_total == monthly_check$quarterly_total), observed = as.character(max(abs(monthly_check$monthly_total - monthly_check$quarterly_total)))),
  data.table(test = "combined Registry counts equal sex sum", passed = all(combined_identity$combined_count == combined_identity$sex_sum_count), observed = as.character(max(abs(combined_identity$combined_count - combined_identity$sex_sum_count)))),
  data.table(test = "combined population equals sex sum within tolerance", passed = max(abs(combined_identity$combined_population - combined_identity$sex_sum_population)) < 1e-4, observed = as.character(max(abs(combined_identity$combined_population - combined_identity$sex_sum_population)))),
  data.table(test = "only ages 15-19 in Registry panels", passed = identical(sort(unique(region_panel$age)), 15:19), observed = paste(sort(unique(region_panel$age)), collapse = ",")),
  data.table(test = "2019Q1 never coded full post", passed = all(region_panel[year == 2019L & quarter == 1L, post_full] == 0L), observed = paste(unique(region_panel[year == 2019L & quarter == 1L, post_full]), collapse = ",")),
  data.table(test = "2019Q2 is first full post", passed = min(region_panel[post_full == 1L, period_index]) == unique(region_panel[year == 2019L & quarter == 2L, period_index]), observed = region_panel[post_full == 1L][which.min(period_index), period]),
  data.table(test = "event baseline and first post coded -1 and 0", passed = all(region_panel[period %in% c("2018Q4", "2019Q2"), unique(event_time), by = period]$V1 == c(-1L, 0L)), observed = paste(region_panel[period %in% c("2018Q4", "2019Q2"), unique(event_time), by = period]$V1, collapse = ",")),
  data.table(test = "all rates finite and nonnegative", passed = all(is.finite(region_panel$formal_marriage_rate_100k) & region_panel$formal_marriage_rate_100k >= 0), observed = as.character(sum(!is.finite(region_panel$formal_marriage_rate_100k) | region_panel$formal_marriage_rate_100k < 0))),
  data.table(test = "exposure training years only 2013-2017", passed = all(exposure_counts$exposure_training_years == "2013-2017"), observed = paste(unique(exposure_counts$exposure_training_years), collapse = ",")),
  data.table(test = "exposure EB values within zero-one", passed = all(exposure_counts$prelaw_affected_marriage_share_eb %between% c(0, 1)), observed = as.character(range(exposure_counts$prelaw_affected_marriage_share_eb))),
  data.table(test = "synthetic weights nonnegative and sum one", passed = all(weight_table$weight >= -1e-12) & abs(sum(weight_table$weight) - 1) < 1e-10, observed = paste(signif(weight_table$weight, 8), collapse = ",")),
  data.table(test = "synthetic weights use no post information", passed = all(!weight_table$post_information_used), observed = as.character(any(weight_table$post_information_used))),
  data.table(test = "union panel covers 48 periods", passed = uniqueN(union_cells[, .(year, quarter)]) == 48L, observed = as.character(uniqueN(union_cells[, .(year, quarter)])))
), use.names = TRUE)
fwrite(tests, file.path(audit_dir, "ANALYTIC_PANEL_ACCEPTANCE_TESTS.csv"))
if (!all(tests$passed)) {
  print(tests[passed == FALSE])
  stop("Analytical panel acceptance test failed")
}

elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
artifact_sizes <- file.info(list.files(data_dir, pattern = "(PANEL|EXPOSURE|UNION_ANALYTIC|SYNTHETIC_AGE)", full.names = TRUE))$size
log_lines <- c(
  sprintf("start_time=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("region_panel_rows=%d", nrow(region_panel)),
  sprintf("brazil_panel_rows=%d", nrow(brazil_panel)),
  sprintf("uf_diagnostic_rows=%d", nrow(uf_panel)),
  sprintf("annual_panel_rows=%d", nrow(annual_panel)),
  sprintf("union_cell_rows=%d", nrow(union_cells)),
  sprintf("derived_artifact_bytes=%s", format(sum(artifact_sizes), scientific = FALSE)),
  sprintf("tests_passed=%d", sum(tests$passed)),
  sprintf("tests_total=%d", nrow(tests)),
  sprintf("synthetic_weights=%s", paste(sprintf("age%d=%.8f", weight_table$donor_age, weight_table$weight), collapse = ";")),
  sprintf("exposure_eb_alpha=%.10f", eb_alpha),
  sprintf("exposure_eb_beta=%.10f", eb_beta),
  "raw_files_modified=0",
  "gate=D_construction"
)
writeLines(log_lines, file.path(log_dir, "12_build_analysis_panels.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
