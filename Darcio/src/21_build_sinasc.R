#!/usr/bin/env Rscript
# 21_build_sinasc.R — build SINASC monthly status cells per the frozen SINASC
# extension lock (config/sinasc_extension_lock.yml, v1.0.0, 2026-09-02).
# Streams the official CSVs from the cached zips; no persistent expansion.

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(yaml)
})

started <- Sys.time()
set.seed(13811)
project_root <- normalizePath(getwd(), mustWork = TRUE)
root <- file.path(project_root, "Darcio")
sinasc_dir <- file.path(root, "data", "raw_external", "sinasc")
data_dir <- file.path(root, "outputs", "data")
log_dir <- file.path(root, "outputs", "logs")
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
log_file <- file.path(log_dir, "21_build_sinasc.log")
lock <- read_yaml(file.path(root, "config", "sinasc_extension_lock.yml"))

log_line <- function(...) {
  msg <- sprintf("[%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), paste0(...))
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}
rss_mb <- function() {
  as.numeric(strsplit(readLines("/proc/self/status")[grep("VmRSS", readLines("/proc/self/status"))], "\\s+")[[1]][2]) / 1024
}
log_line("start | host=", Sys.info()[["nodename"]], " | cores=", parallel::detectCores(),
         " | free_mem=", round(as.numeric(system("awk '/MemAvailable/{print $2}' /proc/meminfo", intern = TRUE)) / 1024 / 1024, 1), "GiB")

years <- 2013:2024
zip_for_year <- function(y) {
  if (y <= 2015) file.path(sinasc_dir, sprintf("DNBR%d_csv.zip", y))
  else file.path(sinasc_dir, sprintf("SINASC_%d_csv.zip", y))
}
audited_totals <- c(`2015` = 2786525L, `2019` = 2849146L)

need_cols <- c("IDADEMAE", "ESTCIVMAE", "DTNASC", "DTNASCMAE", "CODMUNRES")

cells_list <- vector("list", length(years))
exact_list <- vector("list", length(years))
valid_list <- vector("list", length(years))

for (i in seq_along(years)) {
  y <- years[i]
  zp <- zip_for_year(y)
  stopifnot(file.exists(zp))
  inner <- unzip(zp, list = TRUE)$Name[1]
  t0 <- Sys.time()
  dt <- fread(cmd = sprintf("unzip -p %s %s", shQuote(zp), shQuote(inner)),
              sep = ";", header = TRUE, fill = TRUE, quote = "\"",
              colClasses = "character", showProgress = FALSE)
  setnames(dt, toupper(names(dt)))
  missing_cols <- setdiff(need_cols, names(dt))
  if (length(missing_cols) > 0) stop(sprintf("year %d missing columns: %s", y, paste(missing_cols, collapse = ",")))
  dt <- dt[, ..need_cols]
  n_raw <- nrow(dt)

  # Validation against audited totals (frozen rule: fail on mismatch).
  if (as.character(y) %in% names(audited_totals)) {
    stopifnot(n_raw == audited_totals[[as.character(y)]])
  }

  # Month of birth from DTNASC (ddmmyyyy). Zero-pad if leading zero was lost.
  dt[, DTNASC := trimws(DTNASC)]
  dt[nchar(DTNASC) == 7L, DTNASC := paste0("0", DTNASC)]
  dt[, birth_month := suppressWarnings(as.integer(substr(DTNASC, 3, 4)))]
  dt[, birth_year := suppressWarnings(as.integer(substr(DTNASC, 5, 8)))]
  bad_date <- dt[is.na(birth_month) | birth_month < 1L | birth_month > 12L | birth_year != y, .N]
  dt <- dt[!is.na(birth_month) & birth_month >= 1L & birth_month <= 12L & birth_year == y]

  # Region of residence: first digit of CODMUNRES in 1..5.
  dt[, region := suppressWarnings(as.integer(substr(trimws(CODMUNRES), 1, 1)))]
  bad_region <- dt[is.na(region) | region < 1L | region > 5L, .N]

  # Mother age in completed years.
  dt[, age := suppressWarnings(as.integer(IDADEMAE))]
  n_age_8_9 <- dt[age %in% c(8L, 9L), .N]
  dt <- dt[age >= 10L & age <= 19L]

  # Status recode.
  dt[, status := fifelse(ESTCIVMAE %chin% c("1", "2", "3", "4", "5"), ESTCIVMAE, "9")]

  # Exact age (robustness): (DTNASC - DTNASCMAE)/365.25, floored.
  dt[, DTNASCMAE := trimws(DTNASCMAE)]
  dt[nchar(DTNASCMAE) == 7L, DTNASCMAE := paste0("0", DTNASCMAE)]
  dt[, d_birth := as.IDate(DTNASC, format = "%d%m%Y")]
  dt[, d_mae := as.IDate(DTNASCMAE, format = "%d%m%Y")]
  dt[, exact_age := as.numeric(d_birth - d_mae) / 365.25]
  dt[, exact_valid := !is.na(exact_age) & exact_age >= 8 & exact_age < 60]
  dt[, exact_floor := fifelse(exact_valid, as.integer(floor(exact_age)), NA_integer_)]
  n_exact_missing <- dt[exact_valid == FALSE, .N]

  agg_status <- function(d, by_cols) {
    d[, .(
      n_births = .N,
      n_valid_status = sum(status != "9"),
      n_single = sum(status == "1"),
      n_married = sum(status == "2"),
      n_widowed = sum(status == "3"),
      n_separated = sum(status == "4"),
      n_uniao_estavel = sum(status == "5"),
      n_unknown = sum(status == "9"),
      n_dtnascmae_invalid = sum(!exact_valid)
    ), by = by_cols]
  }

  reg <- agg_status(dt[region >= 1L & region <= 5L],
                    c("birth_year", "birth_month", "region", "age"))
  bra <- agg_status(dt, c("birth_year", "birth_month", "age"))
  bra[, region := 0L]  # 0 = Brazil (includes invalid-region rows, per lock)
  cells_list[[i]] <- rbindlist(list(reg, bra), use.names = TRUE, fill = TRUE)

  de <- dt[exact_valid == TRUE & exact_floor >= 10L & exact_floor <= 19L]
  rege <- agg_status(de[region >= 1L & region <= 5L],
                     c("birth_year", "birth_month", "region", "exact_floor"))
  brae <- agg_status(de, c("birth_year", "birth_month", "exact_floor"))
  brae[, region := 0L]
  ex <- rbindlist(list(rege, brae), use.names = TRUE, fill = TRUE)
  setnames(ex, "exact_floor", "age")
  exact_list[[i]] <- ex

  valid_list[[i]] <- data.table(
    year = y, n_raw = n_raw, n_bad_date = bad_date, n_bad_region = bad_region,
    n_age_8_9 = n_age_8_9, n_kept_10_19 = nrow(dt), n_exact_invalid = n_exact_missing
  )
  rm(dt, de, reg, bra, rege, brae, ex); gc(verbose = FALSE)
  log_line(sprintf("year %d | raw=%d | bad_date=%d | bad_region=%d | kept 10-19=%d | %.1fs | RSS=%.0fMB",
                   y, n_raw, bad_date, bad_region, valid_list[[i]]$n_kept_10_19,
                   as.numeric(difftime(Sys.time(), t0, units = "secs")), rss_mb()))
}

cells <- rbindlist(cells_list, use.names = TRUE)
exact <- rbindlist(exact_list, use.names = TRUE)
validation <- rbindlist(valid_list, use.names = TRUE)
setorder(cells, birth_year, birth_month, region, age)
setorder(exact, birth_year, birth_month, region, age)

fwrite(cells, file.path(data_dir, "SINASC_MONTHLY_STATUS_CELLS.csv"))
write_parquet(cells, file.path(data_dir, "SINASC_MONTHLY_STATUS_CELLS.parquet"))
fwrite(exact, file.path(data_dir, "SINASC_MONTHLY_STATUS_CELLS_EXACT.csv"))
write_parquet(exact, file.path(data_dir, "SINASC_MONTHLY_STATUS_CELLS_EXACT.parquet"))
fwrite(validation, file.path(data_dir, "SINASC_BUILD_VALIDATION.csv"))

log_line(sprintf("done | cells=%d rows | exact=%d rows | total births kept=%s | %.1f min",
                 nrow(cells), nrow(exact),
                 format(validation[, sum(n_kept_10_19)], big.mark = ","),
                 as.numeric(difftime(Sys.time(), started, units = "mins"))))
