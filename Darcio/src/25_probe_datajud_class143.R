#!/usr/bin/env Rscript

# Optional, network-dependent feasibility probe. This script is deliberately not part
# of run_all.sh: the CNJ rotates its public API key and the resulting snapshot can
# change as tribunals refresh DataJud. It exports aggregate diagnostics only; no case
# identifiers or individual-level records are retained.

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(digest)
  library(httr2)
  library(jsonlite)
})

Sys.setenv(TZ = "America/Sao_Paulo")
started <- Sys.time()
cwd <- normalizePath(getwd(), mustWork = TRUE)
root <- if (dir.exists(file.path(cwd, "outputs", "audit"))) {
  cwd
} else if (dir.exists(file.path(cwd, "Darcio", "outputs", "audit"))) {
  file.path(cwd, "Darcio")
} else {
  stop("Run from the Darcio directory or its parent")
}

audit_dir <- file.path(root, "outputs", "audit")
log_dir <- file.path(root, "outputs", "logs")
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

access_url <- "https://datajud-wiki.cnj.jus.br/api-publica/acesso/"
endpoint_base <- "https://api-publica.datajud.cnj.jus.br"
probe_date <- Sys.Date()
probe_end <- format(probe_date + 1L, "%Y-%m-%d")
study_start <- "2013-01-01"
study_end <- "2025-01-01"

tribunals <- data.table(
  uf = c(
    "AC", "AL", "AM", "AP", "BA", "CE", "DF", "ES", "GO",
    "MA", "MG", "MS", "MT", "PA", "PB", "PE", "PI", "PR",
    "RJ", "RN", "RO", "RR", "RS", "SC", "SE", "SP", "TO"
  ),
  alias = c(
    "tjac", "tjal", "tjam", "tjap", "tjba", "tjce", "tjdft", "tjes", "tjgo",
    "tjma", "tjmg", "tjms", "tjmt", "tjpa", "tjpb", "tjpe", "tjpi", "tjpr",
    "tjrj", "tjrn", "tjro", "tjrr", "tjrs", "tjsc", "tjse", "tjsp", "tjto"
  )
)
tribunals[, endpoint := sprintf("%s/api_publica_%s/_search", endpoint_base, alias)]

extract_public_key <- function() {
  key <- Sys.getenv("DATAJUD_PUBLIC_API_KEY", unset = "")
  if (nzchar(key)) return(key)

  response <- request(access_url) |>
    req_user_agent("child-marriage-brazil/feasibility-audit") |>
    req_timeout(60) |>
    req_retry(max_tries = 3) |>
    req_perform()
  html <- gsub("[\r\n]", " ", resp_body_string(response))
  match <- regexec(
    "Authorization: APIKey[[:space:]]*<strong>([A-Za-z0-9+/=]+)</strong>",
    html
  )
  captured <- regmatches(html, match)[[1L]]
  if (length(captured) != 2L || !nzchar(captured[2L])) {
    stop(
      "Could not extract the current public key. Set DATAJUD_PUBLIC_API_KEY ",
      "from the official DataJud access page."
    )
  }
  captured[2L]
}

filter_range <- function(gte = NULL, gt = NULL, lt = NULL, lte = NULL) {
  bounds <- Filter(Negate(is.null), list(gte = gte, gt = gt, lt = lt, lte = lte))
  list(filter = list(range = list(dataAjuizamento = bounds)))
}

query <- list(
  size = 0L,
  track_total_hits = TRUE,
  query = list(term = list("classe.codigo" = 143L)),
  aggs = list(
    date_exists = list(filter = list(exists = list(field = "dataAjuizamento"))),
    date_missing = list(
      filter = list(bool = list(must_not = list(list(exists = list(field = "dataAjuizamento")))))
    ),
    date_plausible = filter_range(gte = "1900-01-01", lt = probe_end),
    date_before_1900 = filter_range(lt = "1900-01-01"),
    date_after_snapshot = filter_range(gte = probe_end),
    pre_2013_2018 = filter_range(gte = "2013-01-01", lt = "2019-01-01"),
    transition_2019 = filter_range(gte = "2019-01-01", lt = "2020-01-01"),
    post_2020_2024 = filter_range(gte = "2020-01-01", lt = "2025-01-01"),
    after_2024_to_snapshot = filter_range(gte = "2025-01-01", lt = probe_end),
    by_year = list(
      date_histogram = list(
        field = "dataAjuizamento", calendar_interval = "year", format = "yyyy",
        min_doc_count = 1L
      )
    ),
    study_months = list(
      filter = list(range = list(
        dataAjuizamento = list(gte = study_start, lt = study_end)
      )),
      aggs = list(by_month = list(date_histogram = list(
        field = "dataAjuizamento", calendar_interval = "month", format = "yyyy-MM",
        min_doc_count = 1L
      )))
    ),
    by_sigilo = list(terms = list(field = "nivelSigilo", size = 20L)),
    by_degree = list(terms = list(field = "grau.keyword", size = 20L)),
    municipalities = list(cardinality = list(
      field = "orgaoJulgador.codigoMunicipioIBGE", precision_threshold = 40000L
    )),
    has_procedencia_219 = list(filter = list(term = list("movimentos.codigo" = 219L))),
    has_improcedencia_220 = list(filter = list(term = list("movimentos.codigo" = 220L))),
    has_procedencia_parcial_221 = list(filter = list(term = list("movimentos.codigo" = 221L))),
    has_any_merit_flag = list(filter = list(bool = list(
      should = list(
        list(term = list("movimentos.codigo" = 219L)),
        list(term = list("movimentos.codigo" = 220L)),
        list(term = list("movimentos.codigo" = 221L))
      ),
      minimum_should_match = 1L
    )))
  )
)

query_json <- toJSON(query, auto_unbox = TRUE, null = "null", digits = NA)
query_hash <- digest(query_json, algo = "sha256", serialize = FALSE)
api_key <- extract_public_key()

doc_count <- function(aggregations, name) {
  value <- aggregations[[name]]$doc_count
  if (is.null(value)) return(NA_integer_)
  as.integer(value)
}

bucket_count <- function(buckets, key) {
  if (!length(buckets)) return(0L)
  keys <- vapply(buckets, function(x) as.character(x$key), character(1L))
  index <- match(as.character(key), keys)
  if (is.na(index)) 0L else as.integer(buckets[[index]]$doc_count)
}

court_rows <- vector("list", nrow(tribunals))
year_rows <- list()
month_rows <- list()

for (i in seq_len(nrow(tribunals))) {
  tribunal <- tribunals[i]
  message(sprintf("[%02d/%02d] %s", i, nrow(tribunals), tribunal$alias))

  result <- tryCatch({
    response <- request(tribunal$endpoint) |>
      req_headers(
        Authorization = paste("APIKey", api_key),
        `Content-Type` = "application/json"
      ) |>
      req_user_agent("child-marriage-brazil/feasibility-audit") |>
      req_body_raw(query_json, type = "application/json") |>
      req_timeout(90) |>
      req_retry(max_tries = 4) |>
      req_perform()
    resp_body_json(response, simplifyVector = FALSE)
  }, error = function(e) e)

  if (inherits(result, "error")) {
    court_rows[[i]] <- data.table(
      uf = tribunal$uf, alias = tribunal$alias, endpoint = tribunal$endpoint,
      probe_date = as.character(probe_date), status = "error",
      error = conditionMessage(result), query_sha256 = query_hash
    )
    next
  }

  aggs <- result$aggregations
  total <- as.integer(result$hits$total$value)
  years <- aggs$by_year$buckets
  months <- aggs$study_months$by_month$buckets
  sigilo <- aggs$by_sigilo$buckets
  degrees <- aggs$by_degree$buckets

  plausible <- doc_count(aggs, "date_plausible")
  missing <- doc_count(aggs, "date_missing")
  before_1900 <- doc_count(aggs, "date_before_1900")
  after_snapshot <- doc_count(aggs, "date_after_snapshot")
  outside_plausible <- total - plausible

  court_rows[[i]] <- data.table(
    uf = tribunal$uf,
    alias = tribunal$alias,
    endpoint = tribunal$endpoint,
    probe_date = as.character(probe_date),
    status = "ok",
    error = NA_character_,
    class_code = 143L,
    total_public_records = total,
    filing_date_exists = doc_count(aggs, "date_exists"),
    filing_date_missing = missing,
    filing_date_plausible = plausible,
    filing_date_before_1900 = before_1900,
    filing_date_after_snapshot = after_snapshot,
    filing_date_outside_plausible = outside_plausible,
    pre_2013_2018 = doc_count(aggs, "pre_2013_2018"),
    transition_2019 = doc_count(aggs, "transition_2019"),
    post_2020_2024 = doc_count(aggs, "post_2020_2024"),
    after_2024_to_snapshot = doc_count(aggs, "after_2024_to_snapshot"),
    public_level_0 = bucket_count(sigilo, "0"),
    other_sigilo_levels = total - bucket_count(sigilo, "0"),
    distinct_municipalities = as.integer(aggs$municipalities$value),
    has_procedencia_219 = doc_count(aggs, "has_procedencia_219"),
    has_improcedencia_220 = doc_count(aggs, "has_improcedencia_220"),
    has_procedencia_parcial_221 = doc_count(aggs, "has_procedencia_parcial_221"),
    has_any_merit_flag = doc_count(aggs, "has_any_merit_flag"),
    degree_buckets = if (length(degrees)) {
      paste(vapply(degrees, function(x) {
        sprintf("%s:%s", x$key, x$doc_count)
      }, character(1L)), collapse = ";")
    } else NA_character_,
    query_sha256 = query_hash
  )

  if (length(years)) {
    year_rows[[length(year_rows) + 1L]] <- rbindlist(lapply(years, function(x) {
      year <- suppressWarnings(as.integer(x$key_as_string))
      data.table(
        uf = tribunal$uf, alias = tribunal$alias,
        filing_year = year, records = as.integer(x$doc_count),
        plausible_year = !is.na(year) && year >= 1900L && year <= as.integer(format(probe_date, "%Y")),
        probe_date = as.character(probe_date), query_sha256 = query_hash
      )
    }))
  }

  month_grid <- data.table(
    filing_month = format(
      seq(as.Date(study_start), as.Date(study_end) - 1L, by = "month"), "%Y-%m"
    )
  )
  observed_months <- if (length(months)) {
    rbindlist(lapply(months, function(x) data.table(
      filing_month = as.character(x$key_as_string),
      records = as.integer(x$doc_count)
    )))
  } else {
    data.table(filing_month = character(), records = integer())
  }
  month_grid <- merge(month_grid, observed_months, by = "filing_month", all.x = TRUE)
  month_grid[is.na(records), records := 0L]
  month_grid[, `:=`(
    uf = tribunal$uf, alias = tribunal$alias,
    probe_date = as.character(probe_date), query_sha256 = query_hash
  )]
  setcolorder(month_grid, c(
    "uf", "alias", "filing_month", "records", "probe_date", "query_sha256"
  ))
  month_rows[[length(month_rows) + 1L]] <- month_grid

  Sys.sleep(0.2)
}

courts <- rbindlist(court_rows, fill = TRUE)
years <- if (length(year_rows)) rbindlist(year_rows) else data.table()
months <- if (length(month_rows)) rbindlist(month_rows) else data.table()

court_path <- file.path(audit_dir, "DATAJUD_CLASS_143_PUBLIC_PROBE.csv")
year_path <- file.path(audit_dir, "DATAJUD_CLASS_143_PUBLIC_BY_YEAR.csv")
month_path <- file.path(audit_dir, "DATAJUD_CLASS_143_PUBLIC_BY_MONTH.csv")
fwrite(courts, court_path)
fwrite(years, year_path)
fwrite(months, month_path)

ok <- courts[status == "ok"]
totals <- if (nrow(ok)) {
  ok[, lapply(.SD, sum, na.rm = TRUE), .SDcols = c(
    "total_public_records", "filing_date_missing", "filing_date_before_1900",
    "filing_date_after_snapshot", "filing_date_outside_plausible",
    "pre_2013_2018", "transition_2019", "post_2020_2024",
    "after_2024_to_snapshot", "has_procedencia_219", "has_improcedencia_220",
    "has_procedencia_parcial_221", "has_any_merit_flag"
  )]
} else data.table()

log_lines <- c(
  sprintf("started=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("finished=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("probe_date=%s", probe_date),
  "source=CNJ DataJud Public API",
  "class_code=143",
  "class_label=Suprimento de Idade e/ou Consentimento",
  sprintf("query_sha256=%s", query_hash),
  sprintf("tribunals_ok=%d", nrow(ok)),
  sprintf("tribunals_error=%d", courts[status == "error", .N]),
  if (nrow(totals)) paste(names(totals), totals[1L], sep = "=", collapse = "\n") else "no_totals=true",
  "privacy=no process identifiers or individual-level records retained",
  "interpretation=diagnostic public-process snapshot; not a secrecy-inclusive census"
)
writeLines(log_lines, file.path(log_dir, "25_probe_datajud_class143.log"))

print(courts[, .(
  uf, status, total_public_records, filing_date_outside_plausible,
  pre_2013_2018, transition_2019, post_2020_2024, has_any_merit_flag
)])
if (nrow(totals)) print(totals)
cat(sprintf("Wrote %s\nWrote %s\nWrote %s\n", court_path, year_path, month_path))
