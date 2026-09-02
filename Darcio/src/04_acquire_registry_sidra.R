#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(digest)
})

start_time <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
darcio_root <- file.path(project_root, "Darcio")
raw_dir <- file.path(darcio_root, "data", "raw_external")
audit_dir <- file.path(darcio_root, "outputs", "audit")
log_dir <- file.path(darcio_root, "outputs", "logs")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

base_url <- "https://apisidra.ibge.gov.br/values/t/4406/n3/all/v/221,4373,4374"
years <- 2013:2024
specs <- data.table(
  query_type = c(
    "first_age_annual", "second_age_annual", "joint_under16_annual",
    "total_annual", "first_age_monthly", "second_age_monthly"
  ),
  suffix = c(
    "c666/32968,32970,32971,32972,32973,32974,33005",
    "c667/33006,33008,33009,33010,33011,33012,33043",
    "c666/32968,32970/c667/33006,33008",
    "",
    "c666/32970,32971,32972,32973,32974/c236/5337,5338,5339,5340,5341,5342,5343,5344,5345,5346,5347,5348",
    "c667/33008,33009,33010,33011,33012/c236/5337,5338,5339,5340,5341,5342,5343,5344,5345,5346,5347,5348"
  ),
  expected_rows = c(567L, 567L, 324L, 81L, 4860L, 4860L)
)

queries <- CJ(year = years, query_type = specs$query_type)
queries <- specs[queries, on = "query_type"]
queries[, file_name := sprintf("sidra_4406_%s_%d.json", query_type, year)]
queries[, url := sprintf("%s/p/%d%s%s?formato=json", base_url, year,
                         fifelse(nzchar(suffix), "/", ""), suffix)]

validate_sidra_json <- function(path, expected_year, expected_rows) {
  parsed <- as.data.table(fromJSON(path, simplifyDataFrame = TRUE))
  if (!nrow(parsed) || !all(c("V", "D1C", "D2C", "D3C") %in% names(parsed))) {
    stop("Invalid SIDRA response schema: ", path)
  }
  if (!identical(parsed$V[[1L]], "Valor")) stop("SIDRA header row is missing: ", path)
  data <- parsed[-1L]
  if (nrow(data) != expected_rows) {
    stop(sprintf("Unexpected row count in %s: got %d, expected %d", path, nrow(data), expected_rows))
  }
  if (!identical(unique(data$D3C), as.character(expected_year))) stop("Unexpected period in ", path)
  if (uniqueN(data$D1C) != 27L) stop("Expected all 27 UFs in ", path)
  if (!setequal(unique(data$D2C), c("221", "4373", "4374"))) stop("Unexpected variables in ", path)
  list(
    rows = nrow(data),
    zero_symbols = sum(data$V == "-"),
    missing_symbols = sum(data$V %in% c("...", "..", "X", ""))
  )
}

download_if_missing <- function(url, destination) {
  if (file.exists(destination)) return(invisible(FALSE))
  part <- paste0(destination, ".part")
  if (file.exists(part)) file.remove(part)
  status <- system2(
    "curl",
    args = c("-L", "--fail", "--retry", "3", "--max-time", "120",
             shQuote(url), "-o", shQuote(part))
  )
  if (!identical(status, 0L)) stop("curl download failed: ", url)
  if (!file.rename(part, destination)) stop("Could not finalize download: ", destination)
  invisible(TRUE)
}

manifest <- rbindlist(lapply(seq_len(nrow(queries)), function(i) {
  q <- queries[i]
  path <- file.path(raw_dir, q$file_name)
  acquired <- download_if_missing(q$url, path)
  check <- validate_sidra_json(path, q$year, q$expected_rows)
  data.table(
    year = q$year,
    query_type = q$query_type,
    relative_path = file.path("Darcio", "data", "raw_external", q$file_name),
    official_url = q$url,
    size_bytes = file.info(path)$size,
    rows = check$rows,
    zero_symbols = check$zero_symbols,
    missing_symbols = check$missing_symbols,
    sha256 = digest(path, algo = "sha256", file = TRUE),
    status = "used",
    acquired_this_run = acquired,
    acquired_or_checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
}))

duplicate_all_period_files <- list.files(
  raw_dir,
  pattern = "^sidra_4406_(first_age_annual|second_age_annual|joint_under16_annual|total_annual)\\.json$",
  full.names = TRUE
)
if (length(duplicate_all_period_files)) {
  duplicates <- rbindlist(lapply(duplicate_all_period_files, function(path) {
    parsed <- as.data.table(fromJSON(path, simplifyDataFrame = TRUE))
    data.table(
      year = NA_integer_,
      query_type = sub("^sidra_4406_(.*)\\.json$", "\\1", basename(path)),
      relative_path = file.path("Darcio", "data", "raw_external", basename(path)),
      official_url = "Initial all-period API query; same cells are retained in validated year-specific files",
      size_bytes = file.info(path)$size,
      rows = max(0L, nrow(parsed) - 1L),
      zero_symbols = if ("V" %in% names(parsed)) sum(parsed$V[-1L] == "-") else NA_integer_,
      missing_symbols = if ("V" %in% names(parsed)) sum(parsed$V[-1L] %in% c("...", "..", "X", "")) else NA_integer_,
      sha256 = digest(path, algo = "sha256", file = TRUE),
      status = "duplicate",
      acquired_this_run = FALSE,
      acquired_or_checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    )
  }))
  manifest <- rbindlist(list(manifest, duplicates), use.names = TRUE)
}
setorder(manifest, status, query_type, year)
fwrite(manifest, file.path(audit_dir, "REGISTRY_EXTERNAL_ACQUISITION_MANIFEST.csv"))

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(start_time, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("validated_query_files=%d", sum(manifest$status == "used")),
  sprintf("duplicate_all_period_files=%d", sum(manifest$status == "duplicate")),
  sprintf("data_rows=%s", format(sum(manifest[status == "used"]$rows), scientific = FALSE)),
  sprintf("size_bytes=%s", format(sum(manifest[status == "used"]$size_bytes), scientific = FALSE)),
  "source=IBGE SIDRA API table 4406",
  "territorial_level=UF (n3)",
  "raw_local_project_files_modified=0",
  "max_parallel_processes=1"
)
writeLines(log_lines, file.path(log_dir, "04_acquire_registry_sidra.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
