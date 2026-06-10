# ============================================================
# 02_download_pnadc.R — PNADC Contínua: download e preparação
# ============================================================
# Author: Maria Cruz, June 2026
# Source: IBGE, Pesquisa Nacional por Amostra de Domicílios
#         Contínua — visita 1 (1º trimestre anual)
# Period: 2012–2024
#         2020–2021 flagged (covid_year = 1)
#
# Output (DuckDB):
#   data/child_marriage.duckdb :: pnadc_raw
#   data/child_marriage.duckdb :: dc_pnadc_dcm
#
# Unit of observation in dc_pnadc_dcm:
#   Every girl aged 10–17 in the sample.
#   choice = "in_union" | "wait"
#   delta  = head_age − girl_age (NA for "wait")
#   rend   = household head's labor income (proxy for family wealth)
# ============================================================

library(tidyverse)
library(PNADcIBGE)
library(duckdb)
library(here)

DB_PATH <- here("data", "child_marriage.duckdb")
YEARS   <- 2012:2024

VARS <- c(
  "Ano", "UF", "UPA", "Estrato", "V1008",
  "V1032",           # calibrated survey weight
  "V2003",           # person order within household
  "V2005",           # household condition (union status)
  "V2007",           # sex
  "V2009",           # age
  "V2010",           # race/color
  "V1022",           # urban/rural
  "V3002",           # attends school
  "V4001",           # has paid work
  "V403312",         # monthly labor income (R$)
  "V4005",           # absent from work this week
  "V4006",           # reason for absence (pre-2019 label)
  "V4006A"           # reason for absence (post-2019 label, same info)
)

options(timeout = 3600)

# 1. DuckDB helpers --------------------------------------------------------

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
  message(sprintf("Salvo: %s :: %s  (%s linhas)",
                  basename(db_path), table, format(nrow(df), big.mark = ".")))
  invisible(df)
}

# 2. Download Function -----------------------------------------------------------

fetch_year_pnadc <- function(yr) {
  yr_cache <- here("data", "raw", sprintf("pnadc_%d.rds", yr))

  if (file.exists(yr_cache)) {
    message(sprintf("  %d: carregando do cache.", yr))
    return(readRDS(yr_cache))
  }

  message(sprintf("  %d: baixando ...", yr))
  df <- tryCatch(
    get_pnadc(year = yr, interview = 1, vars = VARS, design = FALSE),
    error = function(e) { warning(sprintf("  %d falhou: %s", yr, e$message)); NULL }
  )

  zips <- list.files(tempdir(), pattern = "\\.zip$", full.names = TRUE, recursive = TRUE)
  if (length(zips) > 0) unlink(zips)

  if (!is.null(df)) saveRDS(df, yr_cache, compress = "xz")
  df
}

# 3. Clean ------------------------------------------------------------------

# V4006 was renamed V4006A in 2019; unify into a single column before binding
unify_motivo_afast <- function(df) {
  col_a <- if ("V4006A" %in% names(df)) as.character(df$V4006A) else rep(NA_character_, nrow(df))
  col_0 <- if ("V4006"  %in% names(df)) as.character(df$V4006)  else rep(NA_character_, nrow(df))
  dplyr::mutate(df, motivo_afast = dplyr::coalesce(col_a, col_0))
}

tidy_pnadc_dcm <- function(pnadc_raw) {
  is_spouse <- function(x)
    str_detect(as.character(x), regex("cônjuge|companheiro", ignore_case = TRUE))

  pnadc <- pnadc_raw |>
    unify_motivo_afast() |>
    rename(
      ano          = Ano,
      uf           = UF,
      upa          = UPA,
      estrato      = Estrato,
      n_domic      = V1008,
      num_ordem    = V2003,
      pes_comcalib = V1032,
      condno_domic = V2005,
      sexo         = V2007,
      idade        = V2009,
      cor_raca     = V2010,
      sit_domic    = V1022,
      freq_esc     = V3002,
      trab_remun   = V4001,
      rend         = V403312,
      afastado     = V4005
    ) |>
    mutate(
      ano        = as.integer(as.character(ano)),
      idade      = suppressWarnings(as.integer(as.character(idade))),
      rend       = suppressWarnings(as.numeric(as.character(rend))),
      hh_id      = paste(uf, upa, n_domic, sep = "_"),
      pessoa_id  = paste(hh_id, num_ordem, sep = "_"),
      matern_bin = as.integer(
        str_detect(coalesce(motivo_afast, ""), regex("matern", ignore_case = TRUE))
      )
    )

  heads <- pnadc |>
    filter(str_detect(as.character(condno_domic),
                      regex("responsável", ignore_case = TRUE))) |>
    select(hh_id, ano, head_age = idade, head_rend = rend)

  pnadc |>
    filter(
      str_detect(as.character(sexo), regex("femini|mulher", ignore_case = TRUE)),
      idade >= 10L, idade <= 17L
    ) |>
    left_join(heads, by = c("hh_id", "ano")) |>
    mutate(
      choice     = if_else(is_spouse(condno_domic), "in_union", "wait"),
      a          = idade,
      delta      = if_else(choice == "in_union",
                           as.numeric(head_age) - as.numeric(idade),
                           NA_real_),
      rend       = coalesce(head_rend, NA_real_),
      covid_year = as.integer(ano %in% 2020:2021)
    ) |>
    select(
      upa, estrato, pes_comcalib,
      hh_id, pessoa_id, ano,
      uf, sit_domic,
      choice, a, delta, rend, matern_bin,
      cor_raca, freq_esc, trab_remun,
      head_age, head_rend,
      covid_year
    )
}

# 4. Build Panel -----------------------------------------------------------------

build_pnadc_dcm <- function(years, db_path) {
  pnadc_list <- purrr::map(years, fetch_year_pnadc)
  failed     <- years[purrr::map_lgl(pnadc_list, is.null)]

  if (length(failed) > 0)
    warning("Anos não baixados: ", paste(failed, collapse = ", "))

  pnadc_raw    <- bind_rows(purrr::compact(pnadc_list))
  dc_pnadc_dcm <- tidy_pnadc_dcm(pnadc_raw)

  write_duckdb_table(pnadc_raw,    "pnadc_raw",    db_path)
  write_duckdb_table(dc_pnadc_dcm, "dc_pnadc_dcm", db_path)

  if (length(failed) == 0) {
    file.remove(here("data", "raw", sprintf("pnadc_%d.rds", years)))
    message("Caches por ano removidos.")
  }

  dc_pnadc_dcm
}

get_pnadc_dcm <- function(years, db_path) {
  if (duckdb_has_table("dc_pnadc_dcm", db_path)) {
    message("Carregando dc_pnadc_dcm do DuckDB...")
    return(read_duckdb_table("dc_pnadc_dcm", db_path))
  }
  build_pnadc_dcm(years, db_path)
}

# 5. Summary ------------------------------------------------------------------

dc_pnadc_dcm <- get_pnadc_dcm(YEARS, DB_PATH)

n_in_union <- sum(dc_pnadc_dcm$choice == "in_union", na.rm = TRUE)
n_wait     <- sum(dc_pnadc_dcm$choice == "wait",     na.rm = TRUE)

message(sprintf(
  "\ndc_pnadc_dcm: %s obs | in_union = %s | wait = %s | anos %d–%d",
  format(nrow(dc_pnadc_dcm), big.mark = "."),
  format(n_in_union,         big.mark = "."),
  format(n_wait,             big.mark = "."),
  min(dc_pnadc_dcm$ano), max(dc_pnadc_dcm$ano)
))

dc_pnadc_dcm |>
  filter(choice == "in_union") |>
  summarise(
    age_mean   = round(mean(a, na.rm = TRUE), 1),
    delta_mean = round(mean(delta, na.rm = TRUE), 1),
    delta_na   = sum(is.na(delta))
  ) |>
  print()
