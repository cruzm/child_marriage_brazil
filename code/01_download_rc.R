# ============================================================
# 01_download_rc.R — Registro Civil: download from IBGE SIDRA
# ============================================================
# Author: Maria Cruz, June 2026
# Source: IBGE, Estatísticas do Registro Civil
#         SIDRA Table 4406 – Casamentos realizados
#         Level: State (Unidade da Federação, n3)
# Period: 2003–2024
#
# Output (DuckDB):
#   data/child_marriage.duckdb :: rc_raw
#   data/child_marriage.duckdb :: rc_panel
# ============================================================

library(tidyverse)
library(sidrar)
library(duckdb)
library(here)

DB_PATH <- here("data", "child_marriage.duckdb")
RAW_DIR <- here("data", "raw")
YEARS   <- 2003:2024

dir.create(RAW_DIR, showWarnings = FALSE, recursive = TRUE)

# SIDRA T4406, v221 = casamentos realizados, n3 = state level
# c667 codes: bride's age group (Menos de 15 → 25 a 29 anos)
SIDRA_TPL <- paste0(
  "/t/4406/n3/all/v/221/p/%d",
  "/c667/113742,113743,113744,113745,113746,113747,113748,113749"
)

uf_lookup <- c(
  "11"="RO","12"="AC","13"="AM","14"="RR","15"="PA","16"="AP","17"="TO",
  "21"="MA","22"="PI","23"="CE","24"="RN","25"="PB","26"="PE",
  "27"="AL","28"="SE","29"="BA",
  "31"="MG","32"="ES","33"="RJ","35"="SP",
  "41"="PR","42"="SC","43"="RS",
  "50"="MS","51"="MT","52"="GO","53"="DF"
)

# ---- DuckDB helpers --------------------------------------------------------

duckdb_has_table <- function(table, db_path) {
  if (!file.exists(db_path)) return(FALSE)
  con <- dbConnect(duckdb(), db_path, read_only = TRUE)
  on.exit(dbDisconnect(con, shutdown = TRUE))
  dbExistsTable(con, table)
}

read_duckdb_table <- function(table, db_path) {
  con <- dbConnect(duckdb(), db_path, read_only = TRUE)
  on.exit(dbDisconnect(con, shutdown = TRUE))
  dbReadTable(con, table)
}

write_duckdb_table <- function(df, table, db_path, overwrite = TRUE) {
  con <- dbConnect(duckdb(), db_path)
  on.exit(dbDisconnect(con, shutdown = TRUE))
  dbWriteTable(con, table, df, overwrite = overwrite)
  message(sprintf("Saved: %s :: %s  (%s rows)",
                  basename(db_path), table, format(nrow(df), big.mark = ",")))
  invisible(df)
}

# ---- Download --------------------------------------------------------------

fetch_year_rc <- function(yr) {
  yr_cache <- file.path(RAW_DIR, sprintf("rc_sidra_%d.rds", yr))

  if (file.exists(yr_cache)) {
    message(sprintf("  %d: loading from cache.", yr))
    return(readRDS(yr_cache))
  }

  message(sprintf("  %d: querying SIDRA ...", yr))

  df <- tryCatch(
    sidrar::get_sidra(api = sprintf(SIDRA_TPL, yr), format = 3),
    error = function(e) {
      warning(sprintf("  %d failed: %s", yr, e$message))
      NULL
    }
  )

  if (!is.null(df)) saveRDS(df, yr_cache, compress = "xz")
  df
}

# ---- Tidy ------------------------------------------------------------------
# sidrar column names vary; detect by partial match so the function stays
# robust across SIDRA output format changes.

tidy_rc_panel <- function(rc_raw) {
  nms <- names(rc_raw)

  find_col <- function(pattern)
    nms[grepl(pattern, nms, ignore.case = TRUE, perl = TRUE)][1]

  col_uf_cd <- find_col("Unidade.*Federa.*(C.d|ódigo)|C.d.*Unidade.*Federa")
  col_uf_nm <- find_col("Unidade.*Federa")  # picks first; code col matched above
  # Prefer name col that is NOT the code col
  uf_nm_candidates <- nms[grepl("Unidade.*Federa", nms, ignore.case = TRUE, perl = TRUE)]
  col_uf_nm <- uf_nm_candidates[uf_nm_candidates != col_uf_cd][1]

  col_ano   <- find_col("^Ano$|^Per.odo$")
  col_age   <- find_col("[Ii]dade|cônjuge|conjuge|c667")
  col_val   <- find_col("^Valor$|Casamentos")

  missing <- c(uf_cd = col_uf_cd, uf_nm = col_uf_nm,
               ano = col_ano, age = col_age, val = col_val)
  if (any(is.na(missing)))
    stop("Could not detect SIDRA columns: ",
         paste(names(missing)[is.na(missing)], collapse = ", "),
         "\nActual column names: ", paste(nms, collapse = ", "))

  minor_ages <- c("Menos de 15 anos", "15 anos", "16 anos", "17 anos")
  treat_ages <- c("Menos de 15 anos", "15 anos")
  ctrl_ages  <- c("16 anos", "17 anos")

  rc_raw |>
    transmute(
      uf_cod      = str_pad(as.character(.data[[col_uf_cd]]), 2, "left", "0"),
      uf_nome     = as.character(.data[[col_uf_nm]]),
      ano         = as.integer(as.character(.data[[col_ano]])),
      idade_m     = as.character(.data[[col_age]]),
      n_total_row = suppressWarnings(as.integer(as.character(.data[[col_val]])))
    ) |>
    mutate(
      uf          = uf_lookup[uf_cod],
      is_minor_w  = idade_m %in% minor_ages,
      below_16    = case_when(
        idade_m %in% treat_ages ~ 1L,
        idade_m %in% ctrl_ages  ~ 0L,
        TRUE                    ~ NA_integer_
      ),
      pos_lei2019 = as.integer(ano >= 2019L),
      n_total_row = replace_na(n_total_row, 0L)
    ) |>
    filter(!is.na(uf))
}

# ---- Build -----------------------------------------------------------------

build_rc_panel <- function(years, db_path) {
  rc_list <- purrr::map(years, fetch_year_rc)
  failed  <- years[purrr::map_lgl(rc_list, is.null)]

  if (length(failed) > 0)
    warning("Years not downloaded: ", paste(failed, collapse = ", "))

  good <- purrr::compact(rc_list)
  if (length(good) == 0L)
    stop("No year was successfully downloaded. Check warnings above.")

  rc_raw   <- bind_rows(good)
  rc_panel <- tidy_rc_panel(rc_raw)

  write_duckdb_table(rc_raw,   "rc_raw",   db_path)
  write_duckdb_table(rc_panel, "rc_panel", db_path)

  if (length(failed) == 0) {
    file.remove(list.files(RAW_DIR,
      pattern = "^rc_sidra_\\d{4}\\.rds$", full.names = TRUE))
    message("Year caches removed.")
  }

  rc_panel
}

get_rc_panel <- function(years, db_path) {
  if (duckdb_has_table("rc_panel", db_path)) {
    message("Loading rc_panel from DuckDB...")
    return(read_duckdb_table("rc_panel", db_path))
  }
  build_rc_panel(years, db_path)
}

# ---- Main ------------------------------------------------------------------

rc_panel <- get_rc_panel(YEARS, DB_PATH)

message(sprintf(
  "\nFinal panel: %d obs | %d UFs | years %d–%d",
  nrow(rc_panel),
  n_distinct(rc_panel$uf_cod),
  min(rc_panel$ano),
  max(rc_panel$ano)
))

rc_panel |>
  filter(!is.na(below_16)) |>
  group_by(pos_lei2019, below_16) |>
  summarise(
    years_obs = n_distinct(ano),
    total_obs = n(),
    mean_n    = round(mean(n_total_row, na.rm = TRUE), 1),
    .groups   = "drop"
  ) |>
  mutate(period = if_else(pos_lei2019 == 1L, "post-2019", "pre-2019")) |>
  select(period, below_16, years_obs, total_obs, mean_n) |>
  print()
