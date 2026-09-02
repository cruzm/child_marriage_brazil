#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(digest)
})

start_time <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
darcio_root <- file.path(project_root, "Darcio")
raw_dir <- file.path(darcio_root, "data", "raw_external", "pnadc_visita1")
audit_dir <- file.path(darcio_root, "outputs", "audit")
log_dir <- file.path(darcio_root, "outputs", "logs")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

base_url <- paste0(
  "https://ftp.ibge.gov.br/Trabalho_e_Rendimento/",
  "Pesquisa_Nacional_por_Amostra_de_Domicilios_continua/",
  "Anual/Microdados/Visita/Visita_1/Dados/"
)
directory_cache <- file.path(darcio_root, "references", "ibge_pnadc_visita1_data_directory.html")
if (!file.exists(directory_cache)) {
  stop("Official directory listing is missing: ", directory_cache)
}

html <- iconv(
  paste(readLines(directory_cache, warn = FALSE, encoding = "latin1"), collapse = "\n"),
  from = "latin1",
  to = "UTF-8"
)
hrefs <- unique(regmatches(
  html,
  gregexpr('PNADC_[0-9]{4}_visita1_[0-9]{8}\\.zip', html, perl = TRUE)
)[[1L]])
if (!length(hrefs)) stop("No PNADC annual first-visit ZIP names found in the official directory listing")

available <- data.table(file_name = hrefs)
available[, year := as.integer(sub("^PNADC_([0-9]{4}).*$", "\\1", file_name))]
analysis_years <- c(2012:2019, 2022:2024)
selected <- available[year %in% analysis_years]
if (!setequal(selected$year, analysis_years)) {
  stop("Official listing does not contain every requested year: ",
       paste(setdiff(analysis_years, selected$year), collapse = ", "))
}
setorder(selected, year)

zip_listing <- function(path) {
  info <- suppressWarnings(utils::unzip(path, list = TRUE))
  if (nrow(info) != 1L || !grepl("\\.txt$", info$Name[[1L]], ignore.case = TRUE)) {
    stop("Expected exactly one TXT member in ", path)
  }
  info
}

download_one <- function(file_name) {
  destination <- file.path(raw_dir, file_name)
  part <- paste0(destination, ".part")
  if (file.exists(destination)) {
    zip_listing(destination)
    return(invisible(destination))
  }
  if (file.exists(part)) file.remove(part)
  url <- paste0(base_url, file_name)
  status <- system2(
    "curl",
    args = c(
      "-L", "--fail", "--retry", "3", "--max-time", "900",
      shQuote(url), "-o", shQuote(part)
    )
  )
  if (!identical(status, 0L)) stop("curl download failed for ", file_name)
  zip_listing(part)
  if (!file.rename(part, destination)) stop("Could not atomically finalize ", destination)
  invisible(destination)
}

for (file_name in selected$file_name) download_one(file_name)

manifest <- rbindlist(lapply(seq_len(nrow(selected)), function(i) {
  file_name <- selected$file_name[[i]]
  path <- file.path(raw_dir, file_name)
  member <- zip_listing(path)
  compressed_bytes <- file.info(path)$size
  data.table(
    year = selected$year[[i]],
    relative_path = file.path("Darcio", "data", "raw_external", "pnadc_visita1", file_name),
    official_url = paste0(base_url, file_name),
    compressed_bytes = compressed_bytes,
    member_name = member$Name[[1L]],
    uncompressed_bytes = member$Length[[1L]],
    expansion_ratio = member$Length[[1L]] / compressed_bytes,
    sha256 = digest(path, algo = "sha256", file = TRUE),
    zip_valid = TRUE,
    acquired_or_checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
}))
fwrite(manifest, file.path(audit_dir, "PNADC_EXTERNAL_ACQUISITION_MANIFEST.csv"))

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(start_time, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("files=%d", nrow(manifest)),
  sprintf("compressed_bytes=%s", format(sum(manifest$compressed_bytes), scientific = FALSE)),
  sprintf("uncompressed_bytes=%s", format(sum(manifest$uncompressed_bytes), scientific = FALSE)),
  sprintf("max_expansion_ratio=%.3f", max(manifest$expansion_ratio)),
  "source=IBGE PNADC annual first visit official FTP",
  "raw_local_project_files_modified=0",
  "max_parallel_processes=1"
)
writeLines(log_lines, file.path(log_dir, "01_acquire_pnadc.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
