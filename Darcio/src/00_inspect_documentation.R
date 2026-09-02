#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(digest)
  library(readxl)
})

project_root <- normalizePath(file.path(getwd()), mustWork = TRUE)
darcio_root <- file.path(project_root, "Darcio")
audit_dir <- file.path(darcio_root, "outputs", "audit")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

workbooks <- c(
  file.path(project_root, "notes", "data_structure.xlsx"),
  list.files(
    file.path(project_root, "notes", "data dictionary"),
    pattern = "\\.(xls|xlsx)$",
    full.names = TRUE,
    ignore.case = TRUE
  )
)

row_records <- list()
sheet_records <- list()
row_i <- 0L
sheet_i <- 0L

for (path in workbooks) {
  rel_path <- substring(path, nchar(project_root) + 2L)
  sha256 <- digest(path, algo = "sha256", file = TRUE)
  sheets <- tryCatch(excel_sheets(path), error = function(e) character())

  if (!length(sheets)) {
    sheet_i <- sheet_i + 1L
    sheet_records[[sheet_i]] <- data.table(
      path = rel_path,
      sha256 = sha256,
      sheet = NA_character_,
      rows = NA_integer_,
      columns = NA_integer_,
      status = "blocked",
      note = "readxl could not enumerate workbook sheets"
    )
    next
  }

  for (sheet in sheets) {
    dat <- tryCatch(
      read_excel(path, sheet = sheet, col_names = FALSE, .name_repair = "unique_quiet"),
      error = function(e) e
    )

    if (inherits(dat, "error")) {
      sheet_i <- sheet_i + 1L
      sheet_records[[sheet_i]] <- data.table(
        path = rel_path,
        sha256 = sha256,
        sheet = sheet,
        rows = NA_integer_,
        columns = NA_integer_,
        status = "blocked",
        note = conditionMessage(dat)
      )
      next
    }

    dat <- as.data.table(dat)
    sheet_i <- sheet_i + 1L
    sheet_records[[sheet_i]] <- data.table(
      path = rel_path,
      sha256 = sha256,
      sheet = sheet,
      rows = nrow(dat),
      columns = ncol(dat),
      status = "read",
      note = NA_character_
    )

    if (!nrow(dat)) next
    dat[, row_number := .I]
    value_cols <- setdiff(names(dat), "row_number")
    dat[, row_text := apply(.SD, 1L, function(x) {
      x <- trimws(as.character(x))
      x <- x[!is.na(x) & nzchar(x) & x != "NA"]
      paste(x, collapse = " | ")
    }), .SDcols = value_cols]
    dat <- dat[nzchar(row_text), .(row_number, row_text)]
    if (!nrow(dat)) next

    row_i <- row_i + 1L
    row_records[[row_i]] <- dat[, .(
      path = rel_path,
      sheet = sheet,
      row_number,
      row_text
    )]
  }
}

sheets_out <- rbindlist(sheet_records, fill = TRUE)
rows_out <- rbindlist(row_records, fill = TRUE)

relevant_pattern <- paste(
  c(
    "ano", "trimestre", "visita", "unidade da federa", "\\buf\\b", "regi[aã]o",
    "dom[ií]nio", "domic[ií]lio", "pessoa", "upa", "estrato", "peso", "calibra",
    "idade", "nascimento", "sexo", "cor ou ra[cç]a", "condi[cç][aã]o no domic",
    "c[oô]njuge", "companhe", "genro", "nora", "filho", "enteado", "escola",
    "instru[cç][aã]o", "trabal", "hora", "rendimento", "urbano", "rural",
    "V1008", "V1014", "V1016", "V1022", "V1023", "V1027", "V1028", "V1029",
    "V1033", "V2003", "V2005", "V2007", "V2008", "V20081", "V20082", "V2009",
    "V2010", "V3002", "VD2002", "VD3004", "VD3005", "VD400"
  ),
  collapse = "|"
)
relevant_out <- rows_out[grepl(relevant_pattern, row_text, ignore.case = TRUE, perl = TRUE)]

fwrite(sheets_out, file.path(audit_dir, "DOCUMENTATION_WORKBOOK_SUMMARY.csv"))
fwrite(rows_out, file.path(audit_dir, "DOCUMENTATION_ALL_ROWS.csv.gz"), compress = "gzip")
fwrite(relevant_out, file.path(audit_dir, "DOCUMENTATION_RELEVANT_ROWS.csv"))

cat(sprintf("Read %d workbooks, %d sheets, and %d non-empty rows.\n",
            length(workbooks), nrow(sheets_out), nrow(rows_out)))
cat(sprintf("Relevant crosswalk rows: %d.\n", nrow(relevant_out)))
if (any(sheets_out$status != "read")) {
  print(sheets_out[status != "read"])
}
