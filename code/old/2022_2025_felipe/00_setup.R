# =============================================================================
# 00_setup.R — Configuração global: pacotes, caminhos, helpers e constantes
# =============================================================================
# Carregado automaticamente por todos os outros scripts via:
#   source(here::here("00_setup.R"))
# =============================================================================

library(tidyverse)
library(readxl)
library(writexl)
library(srvyr)
library(survey)
library(PNADcIBGE)
library(scales)
library(ggplot2)
library(patchwork)
library(broom)      # tidy() para coeficientes do svyglm (Mincer)
library(here)

# Reprodutibilidade e opções globais
set.seed(42)
options(survey.lonely.psu = "adjust")   # padrão para estratos com PSU único
options(timeout = 3600)                  # timeout de download: 1 hora

# ── Caminhos (relativos à raiz do .Rproj — funciona em qualquer máquina) ─────
RC_DIR    <- here("PIBIC", "Iniciação Científica - Registro Civil", "RCivil")
OUT_DIR   <- here("PIBIC", "outputs")
CACHE_DIR <- here("data", "cache")

dir.create(OUT_DIR,   showWarnings = FALSE, recursive = TRUE)
dir.create(CACHE_DIR, showWarnings = FALSE, recursive = TRUE)

# =============================================================================
# HELPERS
# =============================================================================

# ── Mapeia código ou nome completo de UF → sigla de 2 letras ─────────────────
uf_to_sigla <- function(uf) {
  uf <- as.character(uf)
  lookup <- c(
    "11"="RO","12"="AC","13"="AM","14"="RR","15"="PA","16"="AP","17"="TO",
    "21"="MA","22"="PI","23"="CE","24"="RN","25"="PB","26"="PE",
    "27"="AL","28"="SE","29"="BA",
    "31"="MG","32"="ES","33"="RJ","35"="SP",
    "41"="PR","42"="SC","43"="RS",
    "50"="MS","51"="MT","52"="GO","53"="DF",
    "Rondônia"="RO","Acre"="AC","Amazonas"="AM","Roraima"="RR",
    "Pará"="PA","Amapá"="AP","Tocantins"="TO",
    "Maranhão"="MA","Piauí"="PI","Ceará"="CE",
    "Rio Grande do Norte"="RN","Paraíba"="PB","Pernambuco"="PE",
    "Alagoas"="AL","Sergipe"="SE","Bahia"="BA",
    "Minas Gerais"="MG","Espírito Santo"="ES",
    "Rio de Janeiro"="RJ","São Paulo"="SP",
    "Paraná"="PR","Santa Catarina"="SC","Rio Grande do Sul"="RS",
    "Mato Grosso do Sul"="MS","Mato Grosso"="MT","Goiás"="GO",
    "Distrito Federal"="DF"
  )
  sigla <- lookup[uf]
  ifelse(is.na(sigla) & nchar(uf) == 2L, uf, sigla)
}

# ── Mapeia UF → macrorregião ──────────────────────────────────────────────────
get_regiao <- function(uf) {
  sigla <- uf_to_sigla(uf)
  norte      <- c("RO","AC","AM","RR","PA","AP","TO")
  nordeste   <- c("MA","PI","CE","RN","PB","PE","AL","SE","BA")
  sudeste    <- c("MG","ES","RJ","SP")
  sul        <- c("PR","SC","RS")
  centroeste <- c("MS","MT","GO","DF")
  dplyr::case_when(
    sigla %in% norte      ~ "Norte",
    sigla %in% nordeste   ~ "Nordeste",
    sigla %in% sudeste    ~ "Sudeste",
    sigla %in% sul        ~ "Sul",
    sigla %in% centroeste ~ "Centro-Oeste",
    TRUE                  ~ NA_character_
  )
}

# ── Renomeia coluna por padrão regex (se existir); trata encoding Windows ─────
rename_if_exists <- function(df, pattern, new_name) {
  nomes_norm <- iconv(names(df), to = "ASCII//TRANSLIT")
  hit_idx <- grep(pattern, nomes_norm, ignore.case = TRUE)[1]
  hit <- if (!is.na(hit_idx)) names(df)[hit_idx] else NA_character_
  if (!is.na(hit) && hit != new_name) dplyr::rename(df, !!new_name := !!hit) else df
}

# =============================================================================
# CONSTANTES
# =============================================================================

# Anos da PNADC utilizados (2020–2021 excluídos por mudanças COVID)
PNADC_YEARS <- c(2012:2019, 2022:2023)

# Salário mínimo nominal vigente em 1º de janeiro de cada ano.
# Normalizar a renda pelo SM elimina o efeito da inflação.
sm_lookup <- c(
  "2012" = 622,  "2013" = 678,  "2014" = 724,  "2015" = 788,
  "2016" = 880,  "2017" = 937,  "2018" = 954,  "2019" = 998,
  "2022" = 1212, "2023" = 1320
)

# =============================================================================
# TEMA E PALETAS PARA GRÁFICOS
# =============================================================================

theme_paper <- theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold", hjust = 0.5, size = 13),
    plot.subtitle    = element_text(hjust = 0.5, size = 11, color = "gray40"),
    legend.position  = "bottom",
    panel.grid.minor = element_blank(),
    axis.text        = element_text(size = 10)
  )

# Paleta de cores consistente para as categorias de domicílio (A/B/C/D)
cores_categ <- c("A" = "#8E44AD", "B" = "#E67E22",
                 "C" = "#C0392B", "D" = "#2980B9")

# Eixo-x padrão para anos da PNADC (sem 2020–2021)
anos_pnadc <- c(2012:2019, 2022, 2023)

message("00_setup.R carregado.")
