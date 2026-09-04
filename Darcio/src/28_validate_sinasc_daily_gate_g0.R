#!/usr/bin/env Rscript
# Read-only acceptance checks for Gate G0. This validator consumes only the
# aggregated G0 artifacts and never estimates an outcome contrast.

options(stringsAsFactors = FALSE)
cwd <- normalizePath(getwd(), mustWork = TRUE)
root <- if (file.exists(file.path(cwd, "config", "sinasc_daily_lock.yml"))) {
  cwd
} else {
  file.path(cwd, "Darcio")
}
if (!dir.exists(root)) stop("Cannot locate the Darcio project directory")

.libPaths(c(file.path(root, "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(digest)
  library(yaml)
})

audit_dir <- file.path(root, "outputs", "audit")
paths <- c(
  annual = file.path(audit_dir, "SINASC_DAILY_G0_ANNUAL.csv"),
  monthly = file.path(audit_dir, "SINASC_DAILY_G0_MONTHLY_PROFILE.csv"),
  quality_status = file.path(audit_dir, "SINASC_DAILY_G0_DATE_QUALITY_BY_STATUS.csv"),
  side_quality = file.path(audit_dir, "SINASC_DAILY_G0_SIDE_QUALITY.csv"),
  side_era = file.path(audit_dir, "SINASC_DAILY_G0_ERA_SIDE_QUALITY.csv"),
  band_counts = file.path(audit_dir, "SINASC_DAILY_G0_BAND_COUNTS.csv"),
  anchors = file.path(audit_dir, "SINASC_DAILY_G0_ANCHOR_RECONCILIATION.csv"),
  gate = file.path(audit_dir, "SINASC_DAILY_GATE_STATUS.csv"),
  report = file.path(root, "outputs", "analysis", "SINASC_DAILY_GATE_G0.md"),
  manifest = file.path(audit_dir, "SINASC_DAILY_G0_OUTPUT_MANIFEST.csv")
)
if (!all(file.exists(paths))) {
  stop("Missing G0 artifact(s): ", paste(names(paths)[!file.exists(paths)],
                                         collapse = ", "))
}

annual <- fread(paths[["annual"]])
monthly <- fread(paths[["monthly"]])
quality_status <- fread(paths[["quality_status"]])
side_quality <- fread(paths[["side_quality"]])
side_era <- fread(paths[["side_era"]])
band_counts <- fread(paths[["band_counts"]])
anchors <- fread(paths[["anchors"]])
gate <- fread(paths[["gate"]])
output_manifest <- fread(paths[["manifest"]])
report_lines <- readLines(paths[["report"]], warn = FALSE)
source_lines <- readLines(file.path(root, "src", "27_sinasc_daily_gate_g0.R"),
                          warn = FALSE)
lock <- read_yaml(file.path(root, "config", "sinasc_daily_lock.yml"))

test <- function(name, condition, observed) {
  data.table(test = name, passed = isTRUE(condition), observed = as.character(observed))
}

expected_years <- c(2016:2018, 2022:2024)
thresholds <- lock$gates$G0_data$pass_requirements
h90_side <- side_era[bandwidth_days == 90L]
h90_band <- band_counts[aggregation == "era" & bandwidth_days == 90L]

monthly_check <- monthly[, .(monthly_plus_invalid = sum(n_records)), by = year]
monthly_check <- merge(monthly_check, annual[, .(year, n_raw)], by = "year")

band_year <- band_counts[aggregation == "year"]
band_era <- band_counts[aggregation == "era"]
birth_sums <- band_year[, .(year_sum_births = sum(n_births)),
                         by = .(era, bandwidth_days, side)]
birth_sums <- merge(birth_sums, band_era[, .(era, bandwidth_days, side,
                                              era_births = n_births)],
                    by = c("era", "bandwidth_days", "side"))

manifest_full_paths <- file.path(root, output_manifest$artifact)
manifest_actual <- vapply(manifest_full_paths, digest, character(1),
                          algo = "sha256", file = TRUE)

mandatory <- gate[criterion != "G0_OVERALL"]
expected_overall <- if (any(mandatory$status == "FAIL")) {
  "FAIL"
} else if (any(mandatory$status == "QUALIFIED")) {
  "QUALIFIED"
} else {
  "PASS"
}
actual_overall <- gate[criterion == "G0_OVERALL", status]

forbidden_fields <- c("estimate", "coefficient", "std_error", "p_value",
                      "ci_low", "ci_high", "tau", "jump", "effect")
objects <- list(annual, monthly, quality_status, side_quality, side_era,
                band_counts, anchors, gate)
forbidden_call <- any(grepl(
  "\\b(feols|rdrobust|rddensity|lm|glm)\\s*\\(", source_lines,
  perl = TRUE
))

small_band <- band_counts$privacy_suppressed_married == TRUE
small_quality <- quality_status$privacy_suppressed == TRUE

tests <- rbindlist(list(
  test("all ten G0 artifacts exist", all(file.exists(paths)), length(paths)),
  test("primary years exactly match the lock",
       identical(as.integer(annual$year), expected_years),
       paste(annual$year, collapse = ",")),
  test("raw archives match cached SHA-256 manifest",
       all(annual$manifest_sha256_match),
       sum(annual$manifest_sha256_match)),
  test("required six-column schema is complete",
       all(annual$required_schema_complete),
       sum(annual$required_schema_complete)),
  test("six designated annual anchors match exactly",
       nrow(annual) == 6L & all(annual$official_total_exact_match) &
         all(annual$raw_minus_official == 0),
       sprintf("%d/6", sum(annual$official_total_exact_match))),
  test("monthly profiles plus invalid dates recover raw totals",
       all(monthly_check$monthly_plus_invalid == monthly_check$n_raw),
       max(abs(monthly_check$monthly_plus_invalid - monthly_check$n_raw))),
  test("each annual exact-date share passes frozen threshold",
       all(annual$exact_date_valid_share >=
             as.numeric(thresholds$exact_date_valid_share_each_primary_year_min)),
       min(annual$exact_date_valid_share)),
  test("each annual age-agreement share passes frozen threshold",
       all(annual$completed_age_agreement_share >=
             as.numeric(thresholds$completed_age_agreement_among_valid_dates_min)),
       min(annual$completed_age_agreement_share)),
  test("h90 contains all four era-side quality cells",
       nrow(h90_side) == 4L &
         setequal(paste(h90_side$era, h90_side$side),
                  c("pre below", "pre above", "post below", "post above")),
       nrow(h90_side)),
  test("each h90 era-side valid-status share passes threshold",
       all(h90_side$valid_status_share >=
             as.numeric(thresholds$valid_status_share_each_era_side_min)),
       min(h90_side$valid_status_share)),
  test("each h90 era-side birth count passes threshold",
       all(h90_band$n_births >=
             as.numeric(thresholds$births_each_era_side_at_h90_min)),
       min(h90_band$n_births)),
  test("each h90 era-side married-event count passes threshold",
       all(h90_band$n_married_events >=
             as.numeric(thresholds$married_events_each_era_side_at_h90_min)),
       min(h90_band$n_married_events)),
  test("era birth counts equal sums of annual cells",
       all(birth_sums$year_sum_births == birth_sums$era_births),
       max(abs(birth_sums$year_sum_births - birth_sums$era_births))),
  test("small married-event cells are suppressed",
       all(is.na(band_counts$n_married_events[small_band])) &
         !any(band_counts$n_married_events %between% c(1, 9), na.rm = TRUE),
       sum(small_band)),
  test("small status-code audit cells are suppressed",
       all(is.na(quality_status$n_candidates[small_quality])),
       sum(small_quality)),
  test("no effect-estimation field is exported",
       !any(vapply(objects, function(z) any(names(z) %chin% forbidden_fields),
                   logical(1))),
       paste(unique(unlist(lapply(objects, names)))[
         unique(unlist(lapply(objects, names))) %chin% forbidden_fields
       ], collapse = ",")),
  test("G0 source contains no estimator call", !forbidden_call, forbidden_call),
  test("output manifest hashes all listed artifacts",
       all(file.exists(manifest_full_paths)) &
         identical(unname(manifest_actual), unname(output_manifest$sha256)),
       sprintf("%d/%d", sum(manifest_actual == output_manifest$sha256),
               nrow(output_manifest))),
  test("reported overall status follows mandatory rows",
       length(actual_overall) == 1L && identical(actual_overall, expected_overall),
       actual_overall),
  test("report explicitly excludes later gates and estimation",
       any(grepl("No later gate was run", report_lines, fixed = TRUE)) &&
         any(grepl("contains no regression", report_lines, fixed = TRUE)),
       "scope declaration present")
), use.names = TRUE)

print(tests)
if (!all(tests$passed)) {
  stop(sprintf("SINASC daily G0 validation failed %d/%d checks",
               sum(!tests$passed), nrow(tests)))
}
cat(sprintf("sinasc_daily_g0_validation_ok checks=%d status=%s\n",
            nrow(tests), actual_overall))
