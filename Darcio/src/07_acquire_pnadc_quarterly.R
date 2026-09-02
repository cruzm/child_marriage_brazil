#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(digest)
})

start_time <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
darcio_root <- file.path(project_root, "Darcio")
raw_dir <- file.path(darcio_root, "data", "raw_external", "pnadc_quarterly")
audit_dir <- file.path(darcio_root, "outputs", "audit")
log_dir <- file.path(darcio_root, "outputs", "logs")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

base_url <- paste0(
  "https://ftp.ibge.gov.br/Trabalho_e_Rendimento/",
  "Pesquisa_Nacional_por_Amostra_de_Domicilios_continua/",
  "Trimestral/Microdados/"
)
years <- 2013:2024

listing_rows <- rbindlist(lapply(years, function(year) {
  listing_path <- file.path(darcio_root, "references", sprintf("ibge_pnadc_quarterly_%d_directory.html", year))
  if (!file.exists(listing_path)) stop("Missing official quarterly directory listing: ", listing_path)
  html <- iconv(
    paste(readLines(listing_path, warn = FALSE, encoding = "latin1"), collapse = "\n"),
    from = "latin1", to = "UTF-8"
  )
  files <- unique(regmatches(html, gregexpr('PNADC_[0-9]{6}_[0-9]{8}\\.zip', html, perl = TRUE))[[1L]])
  data.table(year = year, file_name = files)
}))
listing_rows[, `:=`(
  quarter = as.integer(sub("^PNADC_([0-9]{2}).*$", "\\1", file_name)),
  file_year = as.integer(sub("^PNADC_[0-9]{2}([0-9]{4}).*$", "\\1", file_name))
)]
if (nrow(listing_rows) != 48L || any(listing_rows$file_year != listing_rows$year) ||
    any(listing_rows[, uniqueN(quarter), by = year]$V1 != 4L)) {
  stop("Official quarterly listings do not provide exactly four files per year for 2013-2024")
}
setorder(listing_rows, year, quarter)

zip_listing <- function(path) {
  info <- suppressWarnings(utils::unzip(path, list = TRUE))
  if (nrow(info) != 1L || !grepl("\\.txt$", info$Name[[1L]], ignore.case = TRUE)) {
    stop("Expected exactly one fixed-width TXT member in ", path)
  }
  info
}

download_if_missing <- function(year, file_name) {
  destination <- file.path(raw_dir, file_name)
  if (file.exists(destination)) {
    zip_listing(destination)
    return(invisible(FALSE))
  }
  part <- paste0(destination, ".part")
  if (file.exists(part)) file.remove(part)
  url <- paste0(base_url, year, "/", file_name)
  status <- system2(
    "curl",
    args = c("-L", "--fail", "--retry", "3", "--max-time", "900",
             shQuote(url), "-o", shQuote(part))
  )
  if (!identical(status, 0L)) stop("curl download failed: ", url)
  zip_listing(part)
  if (!file.rename(part, destination)) stop("Could not finalize ", destination)
  invisible(TRUE)
}

for (i in seq_len(nrow(listing_rows))) {
  download_if_missing(listing_rows$year[[i]], listing_rows$file_name[[i]])
}

manifest <- rbindlist(lapply(seq_len(nrow(listing_rows)), function(i) {
  row <- listing_rows[i]
  path <- file.path(raw_dir, row$file_name)
  member <- zip_listing(path)
  compressed_bytes <- file.info(path)$size
  data.table(
    year = row$year,
    quarter = row$quarter,
    relative_path = file.path("Darcio", "data", "raw_external", "pnadc_quarterly", row$file_name),
    official_url = paste0(base_url, row$year, "/", row$file_name),
    compressed_bytes = compressed_bytes,
    member_name = member$Name[[1L]],
    uncompressed_bytes = member$Length[[1L]],
    expansion_ratio = member$Length[[1L]] / compressed_bytes,
    sha256 = digest(path, algo = "sha256", file = TRUE),
    zip_valid = TRUE,
    checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
}))
fwrite(manifest, file.path(audit_dir, "PNADC_QUARTERLY_ACQUISITION_MANIFEST.csv"))

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(start_time, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("files=%d", nrow(manifest)),
  sprintf("compressed_bytes=%s", format(sum(manifest$compressed_bytes), scientific = FALSE)),
  sprintf("uncompressed_bytes=%s", format(sum(manifest$uncompressed_bytes), scientific = FALSE)),
  sprintf("maximum_expansion_ratio=%.3f", max(manifest$expansion_ratio)),
  "source=IBGE PNADC quarterly official FTP",
  "raw_local_project_files_modified=0",
  "download_parallelism_in_script=1"
)
writeLines(log_lines, file.path(log_dir, "07_acquire_pnadc_quarterly.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
