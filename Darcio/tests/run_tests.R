#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(digest)
  library(yaml)
})
Sys.setenv(TZ = "America/Sao_Paulo")

started <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
root <- file.path(project_root, "Darcio")
audit_dir <- file.path(root, "outputs", "audit")
analysis_dir <- file.path(root, "outputs", "analysis")
data_dir <- file.path(root, "outputs", "data")
table_dir <- file.path(root, "outputs", "tables")
figure_dir <- file.path(root, "outputs", "figures")
log_dir <- file.path(root, "outputs", "logs")

checks <- list()
add_check <- function(category, test, passed, observed, source = "final") {
  checks[[length(checks) + 1L]] <<- data.table(
    category = as.character(category), test = as.character(test),
    passed = isTRUE(passed), observed = as.character(observed),
    source = as.character(source)
  )
}

# Every script must parse before any semantic test is accepted.
source_scripts <- sort(list.files(file.path(root, "src"), pattern = "\\.R$",
                                  full.names = TRUE))
parse_errors <- character()
for (script in source_scripts) {
  tryCatch(parse(file = script), error = function(e) {
    parse_errors <<- c(parse_errors, paste(basename(script), conditionMessage(e), sep = ": "))
  })
}
add_check("code", "all R source scripts parse", !length(parse_errors),
          if (length(parse_errors)) paste(parse_errors, collapse = " | ") else length(source_scripts))

critical_scripts <- c(
  "00_check_dependencies.R", "00_inspect_documentation.R", "00_inventory.R",
  "01_audit_sources.R", "01_acquire_pnadc.R", "02_build_pnadc.R",
  "03_build_denominators.R", "03b_build_total_population.R",
  "04_acquire_registry_sidra.R", "05_build_registry.R", "06_finalize_audit.R",
  "07_acquire_pnadc_quarterly.R", "08_build_pnadc_quarterly.R",
  "09_build_quarterly_cells.R", "10_finalize_gate_b.R",
  "11_validate_specification_lock.R", "12_build_analysis_panels.R",
  "13_analyze_registry.R", "14_analyze_delay_exposure.R",
  "15_analyze_pnadc_cells.R", "16_analyze_pnadc_microdata.R",
  "17_analyze_registry_monthly.R", "18_diagnostics_power.R",
  "19_export_results.R", "20_write_reports.R"
)
missing_scripts <- critical_scripts[!file.exists(file.path(root, "src", critical_scripts))]
add_check("code", "all pipeline modules exist", !length(missing_scripts),
          if (length(missing_scripts)) paste(missing_scripts, collapse = ";") else length(critical_scripts))

# Import every component-level acceptance test rather than silently replacing it.
acceptance_files <- sort(unique(c(
  list.files(audit_dir, pattern = "ACCEPTANCE_TESTS\\.csv$", full.names = TRUE),
  file.path(audit_dir, "REGISTRY_BUILD_TESTS.csv")
)))
acceptance_files <- acceptance_files[file.exists(acceptance_files)]
for (path in acceptance_files) {
  x <- fread(path)
  if (!"passed" %in% names(x)) {
    add_check("component", paste("passed column exists in", basename(path)), FALSE,
              paste(names(x), collapse = ";"), basename(path))
    next
  }
  pass <- as.logical(x$passed)
  for (i in seq_len(nrow(x))) {
    observed <- if ("observed" %in% names(x)) x$observed[i] else if ("failures" %in% names(x)) x$failures[i] else NA
    add_check("component", x$test[i], !is.na(pass[i]) && pass[i], observed,
              basename(path))
  }
}
add_check("component", "component acceptance files discovered",
          length(acceptance_files) >= 11L, length(acceptance_files))

# Specification lock integrity and chronology.
lock_path <- file.path(root, "config", "specification_lock.yml")
estimands_path <- file.path(analysis_dir, "ESTIMANDS_AND_SPECIFICATIONS.md")
hash_path <- file.path(analysis_dir, "SPECIFICATION_LOCK_SHA256.txt")
hash_lines <- readLines(hash_path, warn = FALSE)
expected_lock <- sub(" .*", "", grep("specification_lock.yml$", hash_lines, value = TRUE))
expected_estimands <- sub(" .*", "", grep("ESTIMANDS_AND_SPECIFICATIONS.md$", hash_lines, value = TRUE))
actual_lock <- digest(file = lock_path, algo = "sha256", serialize = FALSE)
actual_estimands <- digest(file = estimands_path, algo = "sha256", serialize = FALSE)
add_check("lock", "specification lock SHA-256 unchanged",
          identical(actual_lock, expected_lock), actual_lock)
add_check("lock", "estimands document SHA-256 unchanged",
          identical(actual_estimands, expected_estimands), actual_estimands)
lock <- read_yaml(lock_path)
add_check("lock", "lock predates effect estimation",
          isTRUE(lock$frozen_before_post_reform_estimation) &&
            identical(lock$effect_estimates_seen_before_lock, FALSE),
          paste(lock$frozen_at, lock$effect_estimates_seen_before_lock))
amendments <- readLines(file.path(analysis_dir, "SPECIFICATION_AMENDMENTS.md"), warn = FALSE)
add_check("lock", "all four technical amendments documented",
          sum(grepl("^## Amendment [1-4]", amendments)) == 4L,
          sum(grepl("^## Amendment [1-4]", amendments)))

# Treatment timing, age, denominators, and rate identities.
registry_panel <- fread(file.path(data_dir, "REGISTRY_QUARTERLY_PANEL_REGION.csv"))
union_cells <- fread(file.path(data_dir, "PNADC_UNION_ANALYTIC_CELLS.csv"))
add_check("timing", "2019Q1 is partial and never full post in Registry",
          all(registry_panel[year == 2019L & quarter == 1L,
                             partial_2019q1 == 1L & post_full == 0L]),
          registry_panel[year == 2019L & quarter == 1L, uniqueN(post_full)])
add_check("timing", "full Registry post begins in 2019Q2",
          all(registry_panel[year == 2019L & quarter %in% 2:4, post_full == 1L]),
          paste(registry_panel[post_full == 1L, min(period)], registry_panel[post_full == 1L, max(period)]))
add_check("timing", "2019Q1 is partial and never full post in PNADC",
          all(union_cells[year == 2019L & quarter == 1L,
                          partial_2019q1 == 1L & post_full == 0L]),
          union_cells[year == 2019L & quarter == 1L, uniqueN(post_full)])
add_check("treatment", "only age 15 is marked treated",
          all(registry_panel[, (age == 15L) == (treated_age == 1L)]) &&
            all(union_cells[, (age == 15L) == (treated_age == 1L)]),
          paste(sort(unique(registry_panel[treated_age == 1L, age])), collapse = ","))
add_check("geography", "primary Registry panel is regional",
          identical(unique(registry_panel$geography_level), "region") &&
            uniqueN(registry_panel$geography_value) == 5L,
          paste(uniqueN(registry_panel$geography_value), "regions"))
rate_error <- registry_panel[, max(abs(formal_marriage_rate_100k -
                                         1e5 * persons_married / population), na.rm = TRUE)]
add_check("construction", "Registry incidence rate identity holds",
          rate_error < 1e-10, format(rate_error, scientific = TRUE))
add_check("construction", "all offsets have positive denominators",
          all(is.finite(registry_panel$offset_log_population)) &&
            all(registry_panel$population > 0),
          registry_panel[!is.finite(offset_log_population) | population <= 0, .N])
add_check("construction", "union prevalences remain probabilities",
          all(union_cells$union_conservative >= 0 & union_cells$union_conservative <= 1) &&
            all(union_cells$union_expanded >= 0 & union_cells$union_expanded <= 1),
          paste(range(union_cells$union_conservative), collapse = ","))

# Official Registry reconciliation and PNADC build coverage.
registry_validation <- fread(file.path(audit_dir, "REGISTRY_LOCAL_OFFICIAL_VALIDATION.csv"))
registry_total_validation <- fread(file.path(audit_dir, "REGISTRY_TOTALS_LOCAL_OFFICIAL_VALIDATION.csv"))
add_check("validation", "all local Registry age-sex cells match official SIDRA",
          all(registry_validation$exact_match) && all(registry_validation$difference == 0),
          paste(nrow(registry_validation), "cells"))
add_check("validation", "all local Registry totals match official SIDRA",
          all(registry_total_validation$exact_match) && all(registry_total_validation$difference == 0),
          paste(nrow(registry_total_validation), "annual totals"))
pnadc_build <- fread(file.path(audit_dir, "PNADC_QUARTERLY_BUILD_VALIDATION.csv"))
add_check("validation", "PNADC quarterly build covers 48 periods",
          nrow(pnadc_build) == 48L && uniqueN(pnadc_build[, .(year, quarter)]) == 48L,
          nrow(pnadc_build))
add_check("validation", "PNADC weights and person keys validate",
          all(pnadc_build$weight_missing == 0L) &&
            all(pnadc_build$weight_nonpositive == 0L) &&
            all(pnadc_build$duplicate_person_keys == 0L),
          paste(sum(pnadc_build$weight_missing), sum(pnadc_build$weight_nonpositive),
                sum(pnadc_build$duplicate_person_keys), sep = "/"))

# Primary estimates must be finite, retain their predeclared sample, and remain distinct outcomes.
primary <- fread(file.path(table_dir, "REGISTRY_PRIMARY_EFFECT.csv"))
union_primary <- fread(file.path(table_dir, "PNADC_UNION_PRIMARY_EFFECT.csv"))
add_check("results", "Registry primary estimate is finite and uses 27 time clusters",
          nrow(primary) == 1L && all(is.finite(unlist(primary[, .(
            beta_log_rate_ratio, beta_se_period_cluster, rate_ratio,
            effect_points_per_100k, estimated_events_avoided
          )]))) && primary$time_clusters == 27L,
          paste(primary$percent_change, primary$time_clusters, sep = "/"))
add_check("results", "PNADC primary has combined temporal/design uncertainty",
          nrow(union_primary) == 1L && union_primary$design_draws == 999L &&
            union_primary$combined_se_quadrature > union_primary$period_cluster_se,
          paste(union_primary$combined_se_quadrature, union_primary$design_draws, sep = "/"))
add_check("results", "PNADC reports age-15-specific unweighted counts",
          all(c("age15_unweighted_people", "age15_unweighted_union_cases",
                "post_age15_unweighted_people", "post_age15_unweighted_union_cases") %in%
                names(union_primary)) && union_primary$age15_unweighted_people > 0,
          union_primary$age15_unweighted_people)
add_check("results", "Registry flow and PNADC stock are never subtracted",
          !any(grepl("subtract|difference_between_registry_and_pnadc",
                     names(primary), ignore.case = TRUE)) &&
            !any(grepl("subtract|difference_between_registry_and_pnadc",
                       names(union_primary), ignore.case = TRUE)),
          "separate result objects")

# Required reports, tables, figures, and their provenance manifest.
required_analysis <- c(
  "TECHNICAL_REPORT.md", "EXECUTIVE_SUMMARY.md", "RESULTS_MANIFEST.csv",
  "SPECIFICATION_AMENDMENTS.md", "session_info.txt",
  "GATE_D_CONSTRUCTION_AND_ESTIMATION.md", "GATE_E_VALIDATION_AND_REPORTING.md"
)
missing_analysis <- required_analysis[!file.exists(file.path(analysis_dir, required_analysis))]
add_check("outputs", "all required analysis reports exist", !length(missing_analysis),
          if (length(missing_analysis)) paste(missing_analysis, collapse = ";") else length(required_analysis))
executive_words <- length(strsplit(paste(readLines(file.path(analysis_dir, "EXECUTIVE_SUMMARY.md"),
                                                warn = FALSE), collapse = " "),
                                   "[[:space:]]+")[[1L]])
add_check("outputs", "executive summary stays within two-page proxy",
          executive_words <= 1000L, executive_words)
technical_text <- paste(readLines(file.path(analysis_dir, "TECHNICAL_REPORT.md"),
                                  warn = FALSE), collapse = "\n")
add_check("outputs", "technical report rejects false conventional RD",
          grepl("não RD convencional|Não se apresenta uma RD convencional", technical_text),
          "explicitly documented")
add_check("outputs", "technical report separates Registry flow and PNADC stock",
          grepl("Registro Civil mede fluxo", technical_text) &&
            grepl("PNADC mede estoque", technical_text), "explicitly documented")

pngs <- list.files(figure_dir, pattern = "\\.png$", full.names = TRUE)
pdfs <- list.files(figure_dir, pattern = "\\.pdf$", full.names = TRUE)
add_check("outputs", "ten nonempty PNG figures exist",
          length(pngs) == 10L && all(file.info(pngs)$size > 0), length(pngs))
add_check("outputs", "ten nonempty PDF figures exist",
          length(pdfs) == 10L && all(file.info(pdfs)$size > 0), length(pdfs))
latex_tables <- list.files(table_dir, pattern = "\\.tex$", full.names = TRUE)
add_check("outputs", "at least ten nonempty LaTeX tables exist",
          length(latex_tables) >= 10L && all(file.info(latex_tables)$size > 0),
          length(latex_tables))

manifest <- fread(file.path(analysis_dir, "RESULTS_MANIFEST.csv"))
artifact_paths <- file.path(root, manifest$artifact)
add_check("provenance", "manifest covers every current analysis CSV and figure format",
          sum(manifest$type == "table_csv") == length(list.files(table_dir, pattern = "\\.csv$")) &&
            sum(manifest$type == "png") == 10L && sum(manifest$type == "pdf") == 10L,
          paste(nrow(manifest), "manifest rows"))
add_check("provenance", "every manifest artifact exists and is nonempty",
          all(file.exists(artifact_paths)) && all(file.info(artifact_paths)$size > 0),
          sum(file.exists(artifact_paths)))
add_check("provenance", "key numbers carry script, source, and specification",
          all(nzchar(manifest[type == "key_number", script])) &&
            all(nzchar(manifest[type == "key_number", source_data])) &&
            all(nzchar(manifest[type == "key_number", specification])),
          manifest[type == "key_number", .N])

# Official-source register and privacy/isolation safeguards.
sources <- fread(file.path(root, "references", "SOURCES.csv"))
required_source_ids <- c("law_13811_2019", "civil_code_compiled", "ibge_registry_page",
                         "ibge_sidra_4406", "ibge_pnadc_page",
                         "ibge_pnadc_quarterly_documentation")
add_check("sources", "all mandatory official sources were opened and registered",
          all(required_source_ids %in% sources$source_id) &&
            all(nzchar(sources[source_id %in% required_source_ids, verification_note])),
          paste(sources[source_id %in% required_source_ids, source_id], collapse = ";"))
add_check("sources", "source URLs are clean HTTPS links with access dates",
          all(grepl("^https://", sources$url)) && all(nzchar(sources$access_date)),
          nrow(sources))

dictionary <- fread(file.path(data_dir, "ANALYTIC_DATA_DICTIONARY.csv"))
sensitive_tokens <- "(^|_)(cpf|nome|name|address|endereco|telefone|email)(_|$)"
add_check("privacy", "analytic data dictionary contains no direct identifier fields",
          !any(grepl(sensitive_tokens, dictionary$variable, ignore.case = TRUE)),
          paste(dictionary[grepl(sensitive_tokens, variable, ignore.case = TRUE), variable],
                collapse = ";"))
git_status <- tryCatch(system2("git", c("status", "--short"), stdout = TRUE, stderr = TRUE),
                       error = function(e) paste0("ERROR: ", conditionMessage(e)))
status_paths <- if (length(git_status)) trimws(sub("^..", "", git_status)) else character()
add_check("isolation", "workspace changes are confined to Darcio",
          !length(status_paths) || all(grepl("^Darcio(/|$)", status_paths)),
          if (length(git_status)) paste(git_status, collapse = " | ") else "clean")
part_files <- list.files(root, pattern = "\\.part$", recursive = TRUE, full.names = TRUE)
add_check("safety", "no partial-download files remain", !length(part_files), length(part_files))
add_check("replication", "single-command runner is executable",
          file.exists(file.path(root, "run_all.sh")) &&
            file.access(file.path(root, "run_all.sh"), mode = 1L) == 0L,
          file.info(file.path(root, "run_all.sh"))$mode)

results <- rbindlist(checks, use.names = TRUE, fill = TRUE)
setorder(results, category, source, test)
fwrite(results, file.path(audit_dir, "FINAL_TEST_SUMMARY.csv"))

failed <- results[passed == FALSE]
status <- if (nrow(failed)) "FAIL" else "PASS"
acceptance_md <- c(
  "# Final acceptance status",
  "",
  paste0("**Status: ", status, "**  "),
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), "  "),
  paste0("Checks passed: ", sum(results$passed), "/", nrow(results), "  "),
  paste0("Imported component checks: ", results[category == "component" &
                                                  test != "component acceptance files discovered", .N], "  "),
  "",
  "Replication command from repository root:",
  "",
  "```bash",
  "./Darcio/run_all.sh",
  "```",
  "",
  "Full machine-readable results: `outputs/audit/FINAL_TEST_SUMMARY.csv`.",
  "",
  if (nrow(failed)) "## Failures" else "No unexplained acceptance-test failure remains.",
  if (nrow(failed)) paste0("- ", failed$category, ": ", failed$test,
                           " — observed: ", failed$observed) else character()
)
writeLines(acceptance_md, file.path(analysis_dir, "FINAL_ACCEPTANCE.md"))

elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
writeLines(c(
  sprintf("started=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("finished=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("checks_passed=%d", sum(results$passed)),
  sprintf("checks_total=%d", nrow(results)),
  sprintf("checks_failed=%d", nrow(failed)),
  sprintf("component_files=%d", length(acceptance_files)),
  sprintf("component_checks=%d", results[category == "component" &
                                           test != "component acceptance files discovered", .N]),
  paste0("status=", status)
), file.path(log_dir, "final_tests.log"))

cat(sprintf("final_acceptance=%s passed=%d total=%d component_files=%d elapsed_seconds=%.1f\n",
            status, sum(results$passed), nrow(results), length(acceptance_files), elapsed))
if (nrow(failed)) {
  print(failed)
  stop("Final acceptance tests failed: ", nrow(failed))
}
