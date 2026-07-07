# ============================================================
# 01_download_rc.R — Registro Civil: download from IBGE SIDRA
# ============================================================
# Author: Maria Cruz, June 2026
# Source: IBGE, Estatísticas do Registro Civil
#         SIDRA Table 4406 – Casamentos realizados
#         Level: Municipality (Município, n6)
# Period: 2013-2018, 2021-2024
#   Table 4406 only has data from 2013 onward (confirmed via SIDRA
#   metadata API), at every geographic level. 2003-2012 is not
#   available through this table.
#
# Output (DuckDB):
#   data/child_marriage.duckdb :: rc_raw
# ============================================================

library(tidyverse)
library(sidrar)
library(duckdb)
library(here)

DB_PATH <- here("data", "child_marriage.duckdb")
RAW_DIR <- here("data", "raw")
YEARS   <- c(2013:2018,2021:2024)


dir.create(RAW_DIR, showWarnings = FALSE, recursive = TRUE)

# SIDRA T4406, v221 = casamentos realizados, n6 = municipality level
# c667 = "Grupo de idade do segundo cônjuge" (bride's age group).
# Codes verified against /api/v3/agregados/4406/metadados — the
# table also exposes "primeiro cônjuge" (c666) and a 15-19 aggregate
# (33007) which we skip in favor of single-year ages.
AGE_CODES <- c(
  "33006" = "Menos de 15 anos",
  "33008" = "15 anos",
  "33009" = "16 anos",
  "33010" = "17 anos",
  "33011" = "18 anos",
  "33012" = "19 anos",
  "33013" = "20 a 24 anos",
  "33019" = "25 a 29 anos"
)

SIDRA_TPL <- paste0(
  "/t/4406/n6/all/v/221/p/%d",
  "/c667/", paste(names(AGE_CODES), collapse = ",")
)

uf_lookup <- c(
  "11"="RO","12"="AC","13"="AM","14"="RR","15"="PA","16"="AP","17"="TO",
  "21"="MA","22"="PI","23"="CE","24"="RN","25"="PB","26"="PE",
  "27"="AL","28"="SE","29"="BA",
  "31"="MG","32"="ES","33"="RJ","35"="SP",
  "41"="PR","42"="SC","43"="RS",
  "50"="MS","51"="MT","52"="GO","53"="DF"
)

# 1.  DuckDB helpers --------------------------------------------------------

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

# 2. Clean column names -----------------------------------------------------

RC_COL_MAP <- c(
  "Nível Territorial (Código)"                  = "nivel_territorial_cod",
  "Nível Territorial"                           = "nivel_territorial",
  "Unidade de Medida (Código)"                  = "unidade_medida_cod",
  "Unidade de Medida"                            = "unidade_medida",
  "Valor"                                        = "valor",
  "Município (Código)"                           = "municipio_cod",
  "Município"                                     = "municipio_nome",
  "Variável (Código)"                            = "variavel_cod",
  "Variável"                                     = "variavel",
  "Ano (Código)"                                 = "ano_cod",
  "Ano"                                          = "ano",
  "Grupo de idade do segundo cônjuge (Código)"   = "idade_conjuge2_cod",
  "Grupo de idade do segundo cônjuge"            = "idade_conjuge2",
  "Mês do registro (Código)"                     = "mes_registro_cod",
  "Mês do registro"                              = "mes_registro",
  "Estado civil do primeiro cônjuge (Código)"    = "estado_civil_conjuge1_cod",
  "Estado civil do primeiro cônjuge"             = "estado_civil_conjuge1",
  "Estado civil do segundo cônjuge (Código)"     = "estado_civil_conjuge2_cod",
  "Estado civil do segundo cônjuge"               = "estado_civil_conjuge2",
  "Grupo de idade do primeiro cônjuge (Código)"  = "idade_conjuge1_cod",
  "Grupo de idade do primeiro cônjuge"           = "idade_conjuge1"
)

clean_rc_raw <- function(df) {
  matched <- RC_COL_MAP[names(df)]
  hit <- !is.na(matched)
  names(df)[hit] <- matched[hit]
  df$valor <- suppressWarnings(as.double(df$valor))
  df
}

# 3. Download --------------------------------------------------------------

fetch_year_rc <- function(yr) {
  yr_cache <- file.path(RAW_DIR, sprintf("rc_sidra_%d.rds", yr))

  df <- if (file.exists(yr_cache)) {
    message(sprintf("  %d: loading from cache.", yr))
    readRDS(yr_cache)
  } else {
    message(sprintf("  %d: querying SIDRA ...", yr))
    out <- tryCatch(
      sidrar::get_sidra(api = sprintf(SIDRA_TPL, yr), format = 3),
      error = function(e) {
        warning(sprintf("  %d failed: %s", yr, e$message))
        NULL
      }
    )
    if (!is.null(out)) saveRDS(out, yr_cache, compress = "xz")
    out
  }

  if (!is.null(df)) df <- clean_rc_raw(df)
  df
}

rc_list <- purrr::map(YEARS, fetch_year_rc)

# 4. Build -----------------------------------------------------------------
rc_raw <- dplyr::bind_rows(rc_list)
  
write_duckdb_table(rc_raw, "rc_raw", DB_PATH)
