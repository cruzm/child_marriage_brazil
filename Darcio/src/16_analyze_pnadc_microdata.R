#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(fixest)
  library(survey)
})

started <- Sys.time()
set.seed(13811)
setFixest_nthreads(1)
setFixest_notes(FALSE)
options(survey.lonely.psu = "adjust")
warning_messages <- character()
globalCallingHandlers(warning = function(w) {
  warning_messages <<- c(warning_messages, conditionMessage(w))
  tryInvokeRestart("muffleWarning")
})

project_root <- normalizePath(getwd(), mustWork = TRUE)
root <- file.path(project_root, "Darcio")
input_dir <- file.path(root, "outputs", "data", "pnadc_quarterly_adolescents")
table_dir <- file.path(root, "outputs", "tables")
audit_dir <- file.path(root, "outputs", "audit")
log_dir <- file.path(root, "outputs", "logs")

files <- list.files(input_dir, pattern = "part-0\\.parquet$", recursive = TRUE,
                    full.names = TRUE)
file_period <- data.table(path = files)
file_period[, year := as.integer(sub(".*year=([0-9]{4}).*", "\\1", path))]
file_period[, quarter := as.integer(sub(".*quarter=([1-4]).*", "\\1", path))]
file_period <- file_period[year <= 2018L | (year == 2019L & quarter >= 2L)]
if (nrow(file_period) != 27L) stop("Expected 27 short-run quarterly partitions")

columns <- c(
  "year", "quarter", "region", "uf", "upa", "stratum", "household_cluster",
  "person_order", "quarterly_calibrated_weight", "age", "sex_code",
  "union_conservative", "union_expanded"
)
parts <- lapply(file_period$path, function(path) {
  x <- as.data.table(read_parquet(path, col_select = tidyselect::all_of(columns)))
  x[age %in% c(15L, 17L, 18L, 19L)]
})
d <- rbindlist(parts, use.names = TRUE)
rm(parts)
invisible(gc())
d[, `:=`(
  period = sprintf("%dQ%d", year, quarter),
  trend_2018q4 = (year - 2018L) * 4L + quarter - 4L,
  post_full = as.integer(year == 2019L & quarter >= 2L),
  treated_age = as.integer(age == 15L)
)]
d[, treat_post := treated_age * post_full]
d[, normalized_weight := quarterly_calibrated_weight /
    mean(quarterly_calibrated_weight), by = period]
d[, `:=`(
  trend_age_15 = trend_2018q4 * as.integer(age == 15L),
  trend_age_17 = trend_2018q4 * as.integer(age == 17L),
  trend_age_18 = trend_2018q4 * as.integer(age == 18L),
  psu_period = factor(paste(period, upa, sep = "-")),
  stratum_period = factor(paste(period, stratum, sep = "-"))
)]
setorder(d, year, quarter, uf, upa, household_cluster, person_order)

micro_formula <- union_conservative ~ treat_post + trend_age_15 +
  trend_age_17 + trend_age_18 | age^quarter + period
expanded_formula <- union_expanded ~ treat_post + trend_age_15 +
  trend_age_17 + trend_age_18 | age^quarter + period

fit_fixest <- function(formula, family = "linear") {
  if (family == "linear") {
    model <- feols(formula, weights = ~normalized_weight, data = d, warn = FALSE)
  } else {
    model <- feglm(formula, weights = ~normalized_weight, data = d,
                   family = binomial(link = "logit"), warn = FALSE)
  }
  ct <- coeftable(model, vcov = ~household_cluster + period)
  beta <- unname(ct["treat_post", "Estimate"])
  se <- unname(ct["treat_post", "Std. Error"])
  data.table(
    estimate = beta, std_error = se, statistic = beta / se,
    p_value = 2 * pnorm(-abs(beta / se)),
    ci_lower = beta - qnorm(0.975) * se,
    ci_upper = beta + qnorm(0.975) * se,
    observations = nobs(model),
    dropped_observations = nrow(d) - nobs(model),
    household_clusters = uniqueN(d$household_cluster),
    period_clusters = uniqueN(d$period),
    collinear_variables = paste(model$collin.var, collapse = ";"),
    model_family = family
  )
}

fixest_conservative <- fit_fixest(micro_formula, "linear")
cat(sprintf("checkpoint=fixest_conservative elapsed_seconds=%.1f\n",
            as.numeric(difftime(Sys.time(), started, units = "secs"))))
fixest_conservative[, `:=`(
  outcome = "union_conservative",
  estimator = "weighted microdata LPM; two-way dwelling and period clusters",
  effect_percentage_points = 100 * estimate
)]
fixest_expanded <- fit_fixest(expanded_formula, "linear")
cat(sprintf("checkpoint=fixest_expanded elapsed_seconds=%.1f\n",
            as.numeric(difftime(Sys.time(), started, units = "secs"))))
fixest_expanded[, `:=`(
  outcome = "union_expanded",
  estimator = "weighted microdata LPM; two-way dwelling and period clusters",
  effect_percentage_points = 100 * estimate
)]
fixest_logit <- fit_fixest(micro_formula, "logit")
cat(sprintf("checkpoint=fixest_logit elapsed_seconds=%.1f\n",
            as.numeric(difftime(Sys.time(), started, units = "secs"))))
fixest_logit[, `:=`(
  outcome = "union_conservative",
  estimator = "weighted fixed-effects logit robustness; two-way clusters",
  odds_ratio = exp(estimate),
  effect_percentage_points = NA_real_
)]

# Exact linear-regression sufficient statistics by UPA x design cell.
# Predictors are constant within age x period, so sum(w) and sum(w*y)
# preserve both the WLS normal equations and each PSU score contribution.
collapsed <- d[, .(
  sum_weight = sum(normalized_weight),
  sum_weight_outcome = sum(normalized_weight * union_conservative),
  persons = .N
), by = .(
  psu_period, stratum_period, age, quarter, period, treat_post,
  trend_age_15, trend_age_17, trend_age_18
)]
collapsed[, outcome_mean := sum_weight_outcome / sum_weight]
survey_formula <- outcome_mean ~ treat_post + trend_age_15 +
  trend_age_17 + trend_age_18 + factor(period) + factor(age) +
  factor(age):factor(quarter)
X_full <- model.matrix(survey_formula, data = collapsed)
wls <- lm.wfit(X_full, collapsed$outcome_mean, w = collapsed$sum_weight)
keep <- !is.na(wls$coefficients)
X <- X_full[, keep, drop = FALSE]
beta_vector <- wls$coefficients[keep]
if (!"treat_post" %in% names(beta_vector)) stop("Collapsed design lost treatment coefficient")
predicted <- as.numeric(X %*% beta_vector)
score_scalar <- collapsed$sum_weight_outcome - collapsed$sum_weight * predicted
score_group <- X * score_scalar

psu_key <- as.character(collapsed$psu_period)
score_psu <- rowsum(score_group, psu_key, reorder = FALSE)
psu_first <- !duplicated(psu_key)
psu_map <- data.table(
  psu_key = psu_key[psu_first],
  stratum = as.character(collapsed$stratum_period[psu_first])
)
if (!identical(rownames(score_psu), psu_map$psu_key)) stop("PSU score order mismatch")
stratum_factor <- factor(psu_map$stratum)
stratum_sums <- rowsum(score_psu, stratum_factor, reorder = TRUE)
stratum_n <- as.integer(table(stratum_factor)[rownames(stratum_sums)])
stratum_means <- stratum_sums / stratum_n
mean_for_psu <- stratum_means[
  match(as.character(stratum_factor), rownames(stratum_means)), , drop = FALSE
]
centered_scores <- score_psu - mean_for_psu
correction <- stratum_n[as.integer(stratum_factor)] /
  pmax(1, stratum_n[as.integer(stratum_factor)] - 1L)
lonely <- stratum_n[as.integer(stratum_factor)] == 1L
if (any(lonely)) {
  # survey.lonely.psu='adjust': center a lonely PSU on the grand score mean.
  centered_scores[lonely, ] <- score_psu[lonely, , drop = FALSE] -
    matrix(colMeans(score_psu), nrow = sum(lonely), ncol = ncol(score_psu), byrow = TRUE)
  correction[lonely] <- 1
}
meat <- crossprod(centered_scores * sqrt(correction))
xtwx <- crossprod(X, X * collapsed$sum_weight)
bread <- solve(xtwx)
design_vcov <- bread %*% meat %*% bread
treat_index <- match("treat_post", colnames(X))
survey_beta <- unname(beta_vector[treat_index])
survey_se <- sqrt(design_vcov[treat_index, treat_index])
cat(sprintf("checkpoint=stratified_psu_scores elapsed_seconds=%.1f collapsed_rows=%d psus=%d\n",
            as.numeric(difftime(Sys.time(), started, units = "secs")),
            nrow(collapsed), nrow(score_psu)))
survey_result <- data.table(
  estimate = survey_beta, std_error = survey_se,
  statistic = survey_beta / survey_se,
  p_value = 2 * pnorm(-abs(survey_beta / survey_se)),
  ci_lower = survey_beta - qnorm(0.975) * survey_se,
  ci_upper = survey_beta + qnorm(0.975) * survey_se,
  observations = nrow(d), dropped_observations = 0L,
  household_clusters = uniqueN(d$household_cluster),
  period_clusters = uniqueN(d$period),
  collapsed_sufficient_statistic_rows = nrow(collapsed),
  psu_clusters = nrow(score_psu),
  strata = length(stratum_n),
  lonely_strata = sum(stratum_n == 1L),
  model_family = "linear",
  outcome = "union_conservative",
  estimator = "exact WLS sufficient statistics; Taylor scores centered by period-Estrato and clustered by period-UPA",
  effect_percentage_points = 100 * survey_beta
)
survey_result[, point_difference_from_individual_lpm :=
                estimate - fixest_conservative$estimate]

results <- rbindlist(list(
  fixest_conservative, fixest_expanded, fixest_logit, survey_result
), use.names = TRUE, fill = TRUE)
results[, `:=`(
  weight = "V1028 normalized to mean one within quarter; never divided by four",
  sample = "ages 15 and 17-19; 2013Q1-2018Q4 plus 2019Q2-Q4",
  treatment = "age 15 x 2019Q2-Q4",
  age_specific_trends = TRUE
)]
fwrite(results, file.path(table_dir, "PNADC_UNION_MICRODATA_ROBUSTNESS.csv"))
rm(X_full, X, score_group, score_psu, centered_scores, meat, xtwx, bread,
   design_vcov, collapsed)
invisible(gc())

# Rotation/repetition diagnostics without claiming a person panel.
dwelling_period <- unique(d[, .(household_cluster, period)])
dwelling_repetition <- dwelling_period[, .(periods_observed = .N),
                                       by = household_cluster]
row_repetition <- merge(
  d[, .N, by = household_cluster], dwelling_repetition,
  by = "household_cluster"
)
rotation <- data.table(
  analytical_rows = nrow(d),
  unique_dwellings = uniqueN(d$household_cluster),
  unique_psu_period = uniqueN(d$psu_period),
  unique_stratum_period = uniqueN(d$stratum_period),
  periods = uniqueN(d$period),
  dwellings_multiple_periods = sum(dwelling_repetition$periods_observed > 1L),
  share_dwellings_multiple_periods = mean(dwelling_repetition$periods_observed > 1L),
  share_rows_in_repeated_dwellings = sum(row_repetition[periods_observed > 1L, N]) /
    sum(row_repetition$N),
  maximum_periods_per_dwelling = max(dwelling_repetition$periods_observed),
  person_transition_estimated = FALSE,
  note = "dwelling hash is stable; person_order is not treated as a longitudinal person key"
)
fwrite(rotation, file.path(audit_dir, "PNADC_ROTATION_MICRODATA_DIAGNOSTICS.csv"))

period_counts <- d[, .(
  unweighted_n = .N,
  union_conservative_cases = sum(union_conservative),
  union_expanded_cases = sum(union_expanded),
  weighted_population = sum(quarterly_calibrated_weight),
  normalized_weight_sum = sum(normalized_weight),
  male_n = sum(sex_code == 1L), female_n = sum(sex_code == 2L)
), by = .(year, quarter, period)]
fwrite(period_counts, file.path(audit_dir, "PNADC_MICRODATA_ANALYSIS_COUNTS.csv"))

tests <- rbindlist(list(
  data.table(test = "microdata sample has 27 periods", passed = uniqueN(d$period) == 27L, observed = as.character(uniqueN(d$period))),
  data.table(test = "2019Q1 excluded", passed = !any(d$year == 2019L & d$quarter == 1L), observed = as.character(sum(d$year == 2019L & d$quarter == 1L))),
  data.table(test = "post starts 2019Q2", passed = all(d[post_full == 1L, year == 2019L & quarter %in% 2:4]), observed = paste(unique(d[post_full == 1L, period]), collapse = ",")),
  data.table(test = "only locked ages retained", passed = identical(sort(unique(d$age)), c(15L, 17L, 18L, 19L)), observed = paste(sort(unique(d$age)), collapse = ",")),
  data.table(test = "V1028 positive", passed = all(d$quarterly_calibrated_weight > 0), observed = as.character(sum(d$quarterly_calibrated_weight <= 0))),
  data.table(test = "normalized weights mean one by period", passed = max(abs(d[, mean(normalized_weight), by = period]$V1 - 1)) < 1e-12, observed = as.character(max(abs(d[, mean(normalized_weight), by = period]$V1 - 1)))),
  data.table(test = "both sexes present each period", passed = all(d[, uniqueN(sex_code), by = period]$V1 == 2L), observed = as.character(min(d[, uniqueN(sex_code), by = period]$V1))),
  data.table(test = "four microdata estimators completed", passed = nrow(results) == 4L, observed = as.character(nrow(results))),
  data.table(test = "all treatment estimates finite", passed = all(is.finite(results$estimate)), observed = as.character(sum(is.finite(results$estimate)))),
  data.table(test = "collapsed WLS point equals individual WLS", passed = abs(survey_result$point_difference_from_individual_lpm) < 1e-10, observed = as.character(survey_result$point_difference_from_individual_lpm)),
  data.table(test = "transition analysis not estimated", passed = !rotation$person_transition_estimated, observed = as.character(rotation$person_transition_estimated))
), use.names = TRUE)
fwrite(tests, file.path(audit_dir, "PNADC_MICRODATA_ACCEPTANCE_TESTS.csv"))
if (!all(tests$passed)) {
  print(tests[passed == FALSE])
  stop("PNADC microdata acceptance test failed")
}

warning_audit <- if (length(warning_messages)) {
  out <- as.data.table(table(message = warning_messages))
  setnames(out, "N", "occurrences")
  setorder(out, -occurrences, message)
  out
} else {
  data.table(message = character(), occurrences = integer())
}
fwrite(warning_audit, file.path(audit_dir, "PNADC_MICRODATA_WARNINGS.csv"))

status <- readLines("/proc/self/status", warn = FALSE)
vm_hwm <- grep("^VmHWM:", status, value = TRUE)
elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("analytical_rows=%d", nrow(d)),
  sprintf("unique_dwellings=%d", uniqueN(d$household_cluster)),
  sprintf("periods=%d", uniqueN(d$period)),
  sprintf("fixest_lpm_effect_pp=%.10f", 100 * fixest_conservative$estimate),
  sprintf("survey_lpm_effect_pp=%.10f", 100 * survey_result$estimate),
  sprintf("warnings_total=%d", length(warning_messages)),
  sprintf("warning_types=%d", nrow(warning_audit)),
  sprintf("process_peak_memory=%s", ifelse(length(vm_hwm), vm_hwm, "unavailable")),
  sprintf("tests_passed=%d", sum(tests$passed)),
  sprintf("tests_total=%d", nrow(tests)),
  "raw_files_modified=0",
  "gate=D_pnadc_microdata"
)
writeLines(log_lines, file.path(log_dir, "16_analyze_pnadc_microdata.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
