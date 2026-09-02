#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(digest)
  library(readxl)
  library(DBI)
  library(duckdb)
})

start_time <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
darcio_root <- file.path(project_root, "Darcio")
audit_dir <- file.path(darcio_root, "outputs", "audit")
log_dir <- file.path(darcio_root, "outputs", "logs")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

all_paths <- list.files(
  project_root,
  recursive = TRUE,
  full.names = TRUE,
  all.files = TRUE,
  include.dirs = FALSE,
  no.. = TRUE
)
rel_paths <- substring(all_paths, nchar(project_root) + 2L)
keep <- !startsWith(rel_paths, ".git/") & !startsWith(rel_paths, "Darcio/")
paths <- all_paths[keep]
rel_paths <- rel_paths[keep]

doc_summary_path <- file.path(audit_dir, "DOCUMENTATION_WORKBOOK_SUMMARY.csv")
doc_summary <- if (file.exists(doc_summary_path)) fread(doc_summary_path) else data.table()

format_label <- function(path) {
  ext <- tolower(tools::file_ext(path))
  switch(ext,
    rds = "R serialized object",
    duckdb = "DuckDB database",
    csv = "CSV text",
    txt = "plain text",
    md = "Markdown",
    rmd = "R Markdown",
    r = "R source",
    tex = "LaTeX source",
    bib = "BibTeX",
    pdf = "PDF",
    xls = "Excel 97-2003 workbook",
    xlsx = "Excel workbook",
    docx = "Word Open XML document",
    zip = "ZIP archive",
    png = "PNG image",
    html = "HTML",
    htm = "HTML",
    rproj = "RStudio project",
    aux = "LaTeX auxiliary",
    log = "log text",
    out = "LaTeX auxiliary",
    nav = "Beamer navigation auxiliary",
    snm = "Beamer auxiliary",
    toc = "table-of-contents auxiliary",
    if (nzchar(ext)) paste0(toupper(ext), " file") else "unknown"
  )
}

compression_label <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "zip") return("ZIP/deflate")
  if (ext == "rds") return("RDS internal compression not encoded in filename")
  if (ext %in% c("docx", "xlsx")) return("ZIP container")
  "none/unknown"
}

text_info <- function(path) {
  ext <- tolower(tools::file_ext(path))
  text_ext <- c("csv", "txt", "md", "rmd", "r", "tex", "bib", "html", "htm", "log", "out", "aux", "nav", "snm", "toc", "rproj")
  if (!ext %in% text_ext) return(list(encoding = NA_character_, delimiter = NA_character_, lines = NA_real_))
  enc <- tryCatch(
    system2("file", c("-b", "--mime-encoding", shQuote(path)), stdout = TRUE, stderr = FALSE),
    error = function(e) NA_character_
  )
  delim <- switch(ext,
    csv = "comma",
    tex = "LaTeX syntax",
    bib = "BibTeX syntax",
    r = "R syntax",
    rmd = "Markdown + R chunks",
    md = "Markdown",
    "not tabular/unknown"
  )
  lines <- tryCatch(length(readLines(path, warn = FALSE, encoding = "UTF-8")), error = function(e) NA_real_)
  list(encoding = paste(enc, collapse = ";"), delimiter = delim, lines = lines)
}

apparent_years_from_text <- function(x) {
  hits <- regmatches(x, gregexpr("(?<![0-9])(19|20)[0-9]{2}(?![0-9])", x, perl = TRUE))[[1L]]
  if (!length(hits) || identical(hits, character(0)) || identical(hits, "")) return(NA_character_)
  vals <- sort(unique(as.integer(hits)))
  vals <- vals[vals >= 1900L & vals <= 2100L]
  if (!length(vals)) NA_character_ else paste(vals, collapse = ";")
}

rds_metadata <- function(path) {
  out <- list(rows = NA_real_, years = NA_character_, note = NA_character_)
  obj <- tryCatch(readRDS(path), error = function(e) e)
  if (inherits(obj, "error")) {
    out$note <- paste("blocked:", conditionMessage(obj))
    return(out)
  }
  out$rows <- if (!is.null(dim(obj))) nrow(obj) else length(obj)
  if (is.data.frame(obj)) {
    year_candidates <- intersect(names(obj), c("Ano", "ano", "ANO", "year", "Year"))
    if (length(year_candidates)) {
      vals <- suppressWarnings(as.integer(as.character(obj[[year_candidates[[1L]]]])))
      vals <- sort(unique(vals[is.finite(vals) & vals >= 1900L & vals <= 2100L]))
      if (length(vals)) out$years <- if (length(vals) > 12L) {
        sprintf("%d-%d", min(vals), max(vals))
      } else paste(vals, collapse = ";")
    }
    out$note <- sprintf("class=%s; columns=%d", paste(class(obj), collapse = "/"), ncol(obj))
  } else {
    out$note <- paste("class=", paste(class(obj), collapse = "/"), sep = "")
  }
  rm(obj)
  gc(verbose = FALSE)
  out
}

workbook_metadata <- function(rel_path) {
  hit <- doc_summary[path == rel_path & status == "read"]
  if (!nrow(hit)) return(list(rows = NA_real_, note = NA_character_))
  list(
    rows = sum(hit$rows, na.rm = TRUE),
    note = sprintf("%d sheet(s); maximum %d columns", nrow(hit), max(hit$columns, na.rm = TRUE))
  )
}

pdf_metadata <- function(path) {
  info <- tryCatch(system2("pdfinfo", shQuote(path), stdout = TRUE, stderr = FALSE), error = function(e) character())
  pages <- suppressWarnings(as.numeric(sub("^Pages:[[:space:]]+", "", grep("^Pages:", info, value = TRUE))))
  list(rows = if (length(pages)) pages[[1L]] else NA_real_, note = "row_count field reports PDF pages")
}

duckdb_metadata <- function(path) {
  con <- tryCatch(dbConnect(duckdb(), path, read_only = TRUE), error = function(e) e)
  if (inherits(con, "error")) return(list(rows = NA_real_, years = NA_character_, note = paste("blocked:", conditionMessage(con))))
  on.exit(try(dbDisconnect(con, shutdown = TRUE), silent = TRUE), add = TRUE)
  tabs <- dbListTables(con)
  counts <- vapply(tabs, function(tb) {
    dbGetQuery(con, paste("SELECT COUNT(*) AS n FROM", dbQuoteIdentifier(con, tb)))$n[[1L]]
  }, numeric(1))
  list(
    rows = sum(counts),
    years = NA_character_,
    note = paste(sprintf("%s=%s", tabs, format(counts, scientific = FALSE, trim = TRUE)), collapse = "; ")
  )
}

probable_content <- function(rel_path) {
  if (grepl("^data/raw/rc_sidra_", rel_path)) return("IBGE SIDRA Registry Civil age cells by UF and year")
  if (rel_path == "data/cache/rc_raw_cache.rds") return("Registry Civil complete-table marriage cells by registration municipality and joint spouse ages")
  if (rel_path == "data/cache/didc_pnadc_cache.rds") return("Filtered PNADC annual-by-first-visit sample: females ages 13-19")
  if (rel_path == "data/processed/dc_rc_dcm.rds") return("Legacy derived Registry Civil structural-model panel")
  if (rel_path == "data/processed/dc_pnadc_dcm.rds") return("Legacy selected PNADC discrete-choice sample")
  if (rel_path == "data/child_marriage.duckdb") return("DuckDB with cached Registry Civil tables")
  if (grepl("^notes/data dictionary/", rel_path)) return("Local data dictionary or methodological documentation")
  if (rel_path == "notes/data_structure.xlsx") return("Project-level variable and dataset map")
  if (grepl("^code/old/", rel_path)) return("Archived legacy code")
  if (grepl("^code/", rel_path)) return("Active or legacy project analysis code")
  if (grepl("^literature/", rel_path)) return("Research literature or institutional report")
  if (grepl("^notes/literature notes/", rel_path)) return("Literature notes or bibliography")
  if (grepl("^output/|^presentation/", rel_path)) return("Preexisting generated result or presentation artifact")
  if (rel_path == "README.md") return("Repository documentation")
  "unknown"
}

dictionary_for <- function(rel_path) {
  if (grepl("rc_|registro|Registro", rel_path)) return("notes/data dictionary/glossario_registro_civil.pdf; IBGE Registry Civil notes")
  if (grepl("pnadc|PNADC|PNAD_Continua", rel_path)) return("notes/data dictionary/Dicionario_e_input_20221031.zip; annual/trimestral PNADC dictionaries")
  if (grepl("PNS|pns", rel_path)) return("PNS 2013/2019 dictionaries in notes/data dictionary")
  if (grepl("POF|pof", rel_path)) return("Documentacao_20230713.zip (POF)")
  NA_character_
}

initial_status <- function(rel_path) {
  if (grepl("^code/old/", rel_path)) return("obsoleto")
  if (grepl("^output/|^presentation/", rel_path)) return("obsoleto")
  if (grepl("^literature/|^notes/literature notes/", rel_path)) return("desconhecido")
  if (grepl("^data/|^code/|^notes/data|^README.md$|^\\.gitattributes$|^LICENSE$", rel_path)) return("usado")
  "desconhecido"
}

records <- vector("list", length(paths))
for (i in seq_along(paths)) {
  path <- paths[[i]]
  rel <- rel_paths[[i]]
  info <- file.info(path)
  txt <- text_info(path)
  ext <- tolower(tools::file_ext(path))
  meta <- list(rows = txt$lines, years = apparent_years_from_text(rel), note = NA_character_)

  if (ext == "rds") meta <- rds_metadata(path)
  if (ext %in% c("xls", "xlsx")) {
    wb <- workbook_metadata(rel)
    meta$rows <- wb$rows
    meta$note <- wb$note
  }
  if (ext == "pdf") {
    pdf <- pdf_metadata(path)
    meta$rows <- pdf$rows
    meta$note <- pdf$note
  }
  if (ext == "duckdb") meta <- duckdb_metadata(path)
  if (is.null(meta$years) || is.na(meta$years)) meta$years <- apparent_years_from_text(rel)

  records[[i]] <- data.table(
    relative_path = rel,
    size_bytes = as.numeric(info$size),
    format = format_label(path),
    compression = compression_label(path),
    encoding = txt$encoding,
    delimiter = txt$delimiter,
    apparent_years = meta$years,
    row_count_or_pages = meta$rows,
    associated_dictionary = dictionary_for(rel),
    probable_content = probable_content(rel),
    sha256 = digest(path, algo = "sha256", file = TRUE),
    modified_time = format(info$mtime, "%Y-%m-%dT%H:%M:%S%z"),
    status = initial_status(rel),
    duplicate_of = NA_character_,
    integrity_note = meta$note
  )
}

inventory <- rbindlist(records, fill = TRUE)

duplicate_groups <- inventory[, .N, by = sha256][N > 1L]
if (nrow(duplicate_groups)) {
  for (hash in duplicate_groups$sha256) {
    idx <- which(inventory$sha256 == hash)
    rank_order <- order(
      grepl("/old/|^output/|^presentation/", inventory$relative_path[idx]),
      nchar(inventory$relative_path[idx]),
      inventory$relative_path[idx]
    )
    canonical <- idx[rank_order[[1L]]]
    dup_idx <- setdiff(idx, canonical)
    inventory[dup_idx, `:=`(
      status = "duplicado",
      duplicate_of = inventory$relative_path[canonical]
    )]
  }
}

setorder(inventory, relative_path)
fwrite(inventory, file.path(audit_dir, "DATA_INVENTORY.csv"), na = "")

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(start_time, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("files_inventoried=%d", nrow(inventory)),
  sprintf("total_bytes=%s", format(sum(inventory$size_bytes), scientific = FALSE)),
  sprintf("duplicate_files=%d", sum(inventory$status == "duplicado")),
  sprintf("blocked_files=%d", sum(grepl("^blocked:", inventory$integrity_note)))
)
writeLines(log_lines, file.path(log_dir, "00_inventory.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
