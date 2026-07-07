# =============================================================================
# 01_importacao.R — Importação de dados brutos
# =============================================================================
# Ordem:
#   Seção 1 – Registro Civil (RC): lê xlsx e padroniza
#   Seção 2 – PNADC principal (visita 1): baixa via API, categoriza domicílios
#   Seção 3 – PNADC mercado de trabalho (visita 1): variáveis de formalidade
#   Seção 4 – PNADC Educação (2º trimestre): módulo educacional sem cache
#
# A comparação RC × PNADC (sub-registro) é feita em 04_analises_PNADC.R,
# pois depende de resultados processados de ambas as fontes.
# =============================================================================

source(here::here("00_setup.R"))

# =============================================================================
# SEÇÃO 1 – REGISTRO CIVIL (RC)
# =============================================================================

rc_years <- 2003:2022
rc_files <- file.path(RC_DIR, paste0("RCIVIL_", rc_years, ".xlsx"))

message("Lendo arquivos do Registro Civil...")
rc_raw <- map2_dfr(rc_years, rc_files, function(yr, fp) {
  if (!file.exists(fp)) {
    warning(sprintf("Arquivo RC não encontrado: %s", fp)); return(NULL)
  }
  read_xlsx(fp) |> mutate(ano = yr)
})

# ── 1.0  Padronização de nomes de colunas ────────────────────────────────────
rc_raw <- rc_raw |>
  rename_if_exists("^[Cc]od",              "cod_mun") |>
  rename_if_exists("^[Mm]unic",            "nome_mun") |>
  rename_if_exists("[Ii]dade.*[Mm]ulher",  "idade_m") |>
  rename_if_exists("h.*<.*15|h.*men.*15",  "h_men15")

# Tabela IBGE: primeiros 2 dígitos do código → sigla da UF
uf_lookup <- c(
  "11"="RO","12"="AC","13"="AM","14"="RR","15"="PA","16"="AP","17"="TO",
  "21"="MA","22"="PI","23"="CE","24"="RN","25"="PB","26"="PE",
  "27"="AL","28"="SE","29"="BA",
  "31"="MG","32"="ES","33"="RJ","35"="SP",
  "41"="PR","42"="SC","43"="RS",
  "50"="MS","51"="MT","52"="GO","53"="DF"
)

rc_raw <- rc_raw |>
  mutate(
    uf = dplyr::coalesce(
      if ("nome_mun" %in% names(pick(everything())))
        stringr::str_extract(nome_mun, "(?<=\\()[A-Z]{2}(?=\\))")
      else
        NA_character_,
      uf_lookup[stringr::str_pad(substr(as.character(cod_mun), 1, 2), 2, pad = "0")]
    ),
    regiao = get_regiao(uf)
  )

# ── Rótulos de faixas etárias (usados como filtros nas análises) ──────────────
idade_menor_m <- c("Menos de 15 anos", "15 anos", "16 anos", "17 anos")
idade_maior_m <- c("18 anos", "19 anos", "20 a 24 anos", "25 a 29 anos",
                   "30 a 34 anos", "35 a 39 anos", "40 a 44 anos", "45 a 49 anos",
                   "50 a 54 anos", "55 a 59 anos", "60 a 64 anos", "65 anos ou mais")

cols_h_menor  <- c("h_men15", "h_15", "h_16", "h_17")
cols_h_18plus <- c("h_18", "h_19", "h_20_24", "h_25_29",
                   "h_30_34", "h_35_39", "h_40_44", "h_45_49",
                   "h_50_54", "h_55_59", "h_60_64", "h_65+")
cols_h_all    <- c(cols_h_menor, cols_h_18plus)

# Coerce para numérico (Excel pode ler "-" ou em branco como character)
rc_raw <- rc_raw |>
  mutate(across(any_of(cols_h_all), ~ suppressWarnings(as.numeric(.)))) |>
  mutate(
    is_minor_w  = idade_m %in% idade_menor_m,
    n_h_minor   = rowSums(across(any_of(cols_h_menor)),  na.rm = TRUE),
    n_h_adult   = rowSums(across(any_of(cols_h_18plus)), na.rm = TRUE),
    n_total_row = n_h_minor + n_h_adult
  )

message(sprintf("rc_raw: %d linhas | anos: %d–%d",
                nrow(rc_raw), min(rc_raw$ano), max(rc_raw$ano)))

# Cache rc_raw para uso em 08_didc.R quando executado de forma independente
rc_raw_cache <- file.path(CACHE_DIR, "rc_raw_cache.rds")
if (!file.exists(rc_raw_cache)) {
  message("Salvando cache de rc_raw...")
  saveRDS(rc_raw, rc_raw_cache, compress = TRUE)
}


# =============================================================================
# SEÇÃO 2 – PNADC PRINCIPAL (visita 1)
# =============================================================================
# Produto final: pnadc_categ — um registro por pessoa (chefe ou cônjuge)
# com categ_domic (A/B/C/D) e variáveis demográficas e de renda.
# Cache: pnadc_categ_cache.rds (skip download se já existir)
# =============================================================================

PNADC_VARS <- c(
  "Ano", "UF",
  "UPA",           # Unidade Primária de Amostragem
  "V1008",         # Número do domicílio
  "V1022",         # Situação do domicílio (urbano/rural)
  "V1031",         # Peso sem calibração
  "V1032",         # Peso calibrado (usar para inferência)
  "V2001",         # Tamanho do domicílio
  "V2003",         # Número de ordem da pessoa
  "V2005",         # Condição no domicílio
  "V2007",         # Sexo
  "V2009",         # Idade
  "V2010",         # Cor/raça
  "V3001",         # Sabe ler e escrever
  "V3002",         # Frequenta escola
  "V4001",         # Tem trabalho remunerado
  "V4005",         # Afastado do trabalho
  "V4006",         # Motivo do afastamento (renomeado para V4006A pós-2016)
  "V403312",       # Rendimento mensal do trabalho principal (R$)
  "V4039",         # Horas efetivamente trabalhadas na semana
  "V4074",         # Motivo de não buscar trabalho
  "V4078"          # Motivo de não querer trabalho
)

import_pnadc_year <- function(yr) {
  message(sprintf("  Importando PNADC %d (visita 1)...", yr))
  df <- tryCatch(
    get_pnadc(year = yr, interview = 1, vars = PNADC_VARS, design = FALSE),
    error = function(e) { warning(sprintf("  Falhou %d: %s", yr, e$message)); NULL }
  )
  if (is.null(df)) return(NULL)

  df <- df |>
    rename(any_of(c(
      pes_semcalib            = "V1031",
      pes_comcalib            = "V1032",
      num_pessoas             = "V2001",
      num_ordem               = "V2003",
      condno_domic            = "V2005",
      sexo                    = "V2007",
      idade                   = "V2009",
      cor_raca                = "V2010",
      ler_escrever            = "V3001",
      freq_esc                = "V3002",
      trab_remun              = "V4001",
      afastd                  = "V4005",
      rend                    = "V403312",
      horas_trabalhadas_seman = "V4039",
      motivo_nao_provid       = "V4074",
      motivo_nao_trab         = "V4078",
      sit_domic               = "V1022",
      n_domic                 = "V1008"
    )))

  # V4006 renomeada para V4006A a partir de 2019
  if ("V4006" %in% names(df)) {
    df <- rename(df, motivo_afast = V4006)
  } else if ("V4006A" %in% names(df)) {
    df <- rename(df, motivo_afast = V4006A)
  } else {
    df <- mutate(df, motivo_afast = NA_character_)
  }

  df |>
    mutate(
      sexo = case_when(
        sexo %in% c("Mulher", "Feminino")  ~ "Feminino",
        sexo %in% c("Homem",  "Masculino") ~ "Masculino",
        TRUE ~ sexo
      ),
      domic_id  = paste(UF, UPA, n_domic, sep = "_"),
      pessoa_id = paste(domic_id, num_ordem, sep = "_"),
      regiao    = get_regiao(as.character(UF))
    ) |>
    # UPA e Estrato são mantidos — necessários para o desenho amostral (Parte 3)
    select(-any_of(c("V4006", "V4006A", "Trimestre")))
}

# ── Download / cache da PNADC principal ──────────────────────────────────────
cache_file  <- file.path(CACHE_DIR, "pnadc_anual_cache.rds")
categ_cache <- file.path(CACHE_DIR, "pnadc_categ_cache.rds")

if (file.exists(categ_cache)) {
  message("Cache do pnadc_categ encontrado — pnadc_anual não será carregado.")
  pnadc_anual <- NULL
} else if (file.exists(cache_file)) {
  message("Carregando PNADC do cache local...")
  pnadc_anual <- readRDS(cache_file)
} else {
  message("Baixando PNADC ano a ano (pode demorar ~20 min)...")
  pnadc_list <- vector("list", length(PNADC_YEARS))
  names(pnadc_list) <- as.character(PNADC_YEARS)

  for (yr in PNADC_YEARS) {
    yr_cache <- file.path(CACHE_DIR, sprintf("pnadc_%d.rds", yr))
    if (file.exists(yr_cache)) {
      message(sprintf("  Ano %d: carregando do cache.", yr))
      pnadc_list[[as.character(yr)]] <- readRDS(yr_cache)
    } else {
      df_yr <- import_pnadc_year(yr)
      if (!is.null(df_yr)) {
        saveRDS(df_yr, yr_cache, compress = "xz")
        message(sprintf("  Ano %d: salvo em cache.", yr))
      } else {
        message(sprintf("  Ano %d: falhou — será ignorado.", yr))
      }
      pnadc_list[[as.character(yr)]] <- df_yr
    }
  }

  anos_ok   <- Filter(Negate(is.null), pnadc_list)
  anos_fail <- names(Filter(is.null, pnadc_list))
  if (length(anos_fail) > 0)
    warning("Anos não importados: ", paste(anos_fail, collapse = ", "))

  pnadc_anual <- bind_rows(anos_ok)

  if (length(anos_fail) == 0) {
    saveRDS(pnadc_anual, cache_file, compress = "xz")
    message("Cache consolidado salvo em: ", cache_file)
    yr_caches <- file.path(CACHE_DIR, sprintf("pnadc_%d.rds", PNADC_YEARS))
    file.remove(yr_caches[file.exists(yr_caches)])
    message("Caches individuais por ano removidos.")
  } else {
    message("Cache consolidado NÃO salvo — anos faltando: ",
            paste(anos_fail, collapse = ", "))
  }
}

# ── 2.1  Categorização dos domicílios ────────────────────────────────────────
# Categorias:
#   A = ambos < 18   B = chefe < 18, cônjuge adulto
#   C = chefe adulto, cônjuge < 18 (foco)   D = ambos adultos (controle)
#
# CACHE: se pnadc_categ_cache.rds existir, pula todo o processamento.
# Para regenerar: file.remove(file.path(CACHE_DIR, "pnadc_categ_cache.rds"))

if (file.exists(categ_cache)) {
  message("Carregando pnadc_categ do cache (pulando processamento 2.1)...")
  pnadc_categ <- readRDS(categ_cache)

} else {
  message("Processando categorização dos domicílios...")
  gc()

  roles_casal <- c("Pessoa responsável pelo domicílio",
                   "Cônjuge ou companheiro(a) de sexo diferente")

  pnadc_casal <- pnadc_anual |> filter(condno_domic %in% roles_casal)

  message(sprintf("  pnadc_casal: %d linhas | %d domicílios únicos | anos: %s",
                  nrow(pnadc_casal),
                  n_distinct(paste(pnadc_casal$domic_id, pnadc_casal$Ano)),
                  paste(sort(unique(pnadc_casal$Ano)), collapse = ", ")))

  rm(pnadc_anual); gc()

  chefes <- pnadc_casal |>
    filter(condno_domic == "Pessoa responsável pelo domicílio") |>
    group_by(domic_id, Ano) |> slice(1) |> ungroup() |>
    select(domic_id, Ano, idade_chefe = idade)

  conjuges <- pnadc_casal |>
    filter(condno_domic == "Cônjuge ou companheiro(a) de sexo diferente") |>
    group_by(domic_id, Ano) |> slice(1) |> ungroup() |>
    select(domic_id, Ano, idade_conjuge = idade)

  categ_table <- inner_join(chefes, conjuges,
                            by = c("domic_id", "Ano"),
                            relationship = "one-to-one") |>
    mutate(
      categ_domic = case_when(
        idade_chefe <  18 & idade_conjuge <  18 ~ "A",
        idade_chefe <  18 & idade_conjuge >= 18 ~ "B",
        idade_chefe >= 18 & idade_conjuge <  18 ~ "C",
        idade_chefe >= 18 & idade_conjuge >= 18 ~ "D"
      ),
      dif_idade = abs(idade_chefe - idade_conjuge)
    ) |>
    select(domic_id, Ano, categ_domic, dif_idade)

  message(sprintf("  categ_table: %d domicílios | A=%d B=%d C=%d D=%d NA=%d",
                  nrow(categ_table),
                  sum(categ_table$categ_domic == "A", na.rm = TRUE),
                  sum(categ_table$categ_domic == "B", na.rm = TRUE),
                  sum(categ_table$categ_domic == "C", na.rm = TRUE),
                  sum(categ_table$categ_domic == "D", na.rm = TRUE),
                  sum(is.na(categ_table$categ_domic))))

  rm(chefes, conjuges); gc()

  pnadc_categ <- pnadc_casal |>
    inner_join(categ_table, by = c("domic_id", "Ano")) |>
    mutate(
      sexo_bin           = as.integer(sexo == "Feminino"),
      parda_preta_bin    = as.integer(cor_raca %in% c("Preta","Parda")),
      ler_escrever_bin   = as.integer(ler_escrever == "Sim"),
      trab_remun_bin     = as.integer(trab_remun  == "Sim"),
      afastd_bin         = as.integer(afastd      == "Sim"),
      matern_bin         = as.integer(
        motivo_afast %in% c("Licença maternidade",
                            "Licença maternidade ou paternidade")),
      cuidado_provid_bin = as.integer(
        motivo_nao_provid %in% c(
          "Tinha que cuidar de filho(s), de outro(s) dependente(s) ou dos afazeres domésticos",
          "Tinha que cuidar dos afazeres domésticos, do(s) filho(s) ou de outro(s) parente(s)",
          "Por problema de saúde ou gravidez"
        )),
      cuidado_trab_bin   = as.integer(
        motivo_nao_trab %in% c(
          "Tinha que cuidar de filho(s), de outro(s) dependente(s) ou dos afazeres domésticos",
          "Tinha que cuidar dos afazeres domésticos, do(s) filho(s) ou de outro(s) parente(s)",
          "Por problema de saúde ou gravidez"
        )),
      rend     = if_else(trab_remun == "Não" | is.na(trab_remun), NA_real_, rend),
      freq_esc = if_else(idade > 18, NA_character_, freq_esc)
    )

  rm(pnadc_casal, categ_table); gc()

  message(sprintf("  pnadc_categ: %d linhas | %d variáveis | anos: %s",
                  nrow(pnadc_categ), ncol(pnadc_categ),
                  paste(sort(unique(pnadc_categ$Ano)), collapse = ", ")))

  saveRDS(pnadc_categ, categ_cache, compress = "xz")
  message("Cache do pnadc_categ salvo em: ", categ_cache)
}


# =============================================================================
# SEÇÃO 3 – PNADC MERCADO DE TRABALHO (visita 1)
# =============================================================================
# Variáveis: V4029 (INSS) e V4012 (posição na ocupação).
# VD4004 não é usada — é derivada do suplemento anual (visita 5) e gera
# erro "not present in microdata" ao tentar com visita 1.
# Cache: pnadc_lm_cache.rds
# =============================================================================

LM_VARS <- c(
  "Ano", "UF", "UPA",
  "V1008",   # número do domicílio
  "V2003",   # número de ordem
  "V1032",   # peso calibrado
  "V2005",   # condição no domicílio
  "V2007",   # sexo
  "V2009",   # idade
  "V4029",   # contribuição ao INSS (formalidade)
  "V4012"    # posição na ocupação (raw, visita 1)
)

import_pnadc_lm <- function(yr) {
  message(sprintf("  Importando mercado de trabalho %d ...", yr))
  df <- tryCatch(
    get_pnadc(year = yr, interview = 1, vars = LM_VARS, design = FALSE),
    error = function(e) { warning(sprintf("  Falhou %d: %s", yr, e$message)); NULL }
  )
  if (is.null(df)) return(NULL)

  df2 <- df |>
    rename(any_of(c(
      pes_comcalib = "V1032",
      n_domic      = "V1008",
      num_ordem    = "V2003",
      condno_domic = "V2005",
      sexo         = "V2007",
      idade        = "V2009",
      inss         = "V4029",
      pos_ocup     = "V4012"
    )))

  if (!"inss"     %in% names(df2)) df2$inss     <- NA_character_
  if (!"pos_ocup" %in% names(df2)) df2$pos_ocup <- NA_character_

  df2 |>
    mutate(
      domic_id     = paste(UF, UPA, n_domic, sep = "_"),
      pessoa_id    = paste(domic_id, num_ordem, sep = "_"),
      pos_ocup_lbl = as.character(pos_ocup),
      inss_lbl     = as.character(inss),
      formal_bin   = as.integer(inss_lbl == "Sim"),
      pos_simples  = case_when(
        is.na(pos_ocup_lbl)                                                     ~ NA_character_,
        str_detect(pos_ocup_lbl, "(?i)dom.stico|domestico")                     ~ "Doméstico",
        str_detect(pos_ocup_lbl, "(?i)p.blico|publico|militar")                 ~ "Setor público",
        str_detect(pos_ocup_lbl, "(?i)privado") & inss_lbl == "Sim"             ~ "Privado c/ carteira",
        str_detect(pos_ocup_lbl, "(?i)privado")                                 ~ "Privado s/ carteira",
        str_detect(pos_ocup_lbl, "(?i)conta pr.pria|conta propria|conta-pr")    ~ "Conta própria",
        str_detect(pos_ocup_lbl, "(?i)empregador")                              ~ "Empregador",
        TRUE                                                                     ~ "Outro"
      )
    ) |>
    # Filtra apenas chefe e cônjuge — únicos papéis usados no merge com pnadc_categ.
    # Reduz ~70% das linhas antes de salvar, sem perda de informação para análise.
    filter(as.character(condno_domic) %in% c(
      "Pessoa responsável pelo domicílio",
      "Cônjuge ou companheiro(a) de sexo diferente"
    )) |>
    select(pessoa_id, domic_id, Ano, pes_comcalib, formal_bin, pos_simples)
}

lm_cache <- file.path(CACHE_DIR, "pnadc_lm_cache.rds")

if (file.exists(lm_cache)) {
  message("Carregando dados de mercado de trabalho do cache...")
  pnadc_lm <- readRDS(lm_cache)
} else {
  message("Baixando variáveis de mercado de trabalho (~20 min)...")
  # Acúmulo incremental: bind + gc a cada ano — evita estouro de RAM.
  # Caches individuais por ano permitem retomar download interrompido.
  pnadc_lm     <- NULL
  anos_ok_lm   <- character(0)
  anos_fail_lm <- character(0)

  for (yr in PNADC_YEARS) {
    yr_cache <- file.path(CACHE_DIR, sprintf("lm_%d.rds", yr))
    if (file.exists(yr_cache)) {
      message(sprintf("  Ano %d: carregando do cache.", yr))
      yr_data <- readRDS(yr_cache)
    } else {
      yr_data <- import_pnadc_lm(yr)
      if (!is.null(yr_data)) {
        saveRDS(yr_data, yr_cache, compress = "xz")
        message(sprintf("  Ano %d: salvo em cache.", yr))
      }
    }

    if (is.null(yr_data)) {
      anos_fail_lm <- c(anos_fail_lm, as.character(yr))
    } else {
      pnadc_lm   <- bind_rows(pnadc_lm, yr_data)
      anos_ok_lm <- c(anos_ok_lm, as.character(yr))
      rm(yr_data); gc()
    }
  }

  if (length(anos_fail_lm) > 0)
    warning("Anos LM não importados: ", paste(anos_fail_lm, collapse = ", "))

  if (length(anos_fail_lm) == 0) {
    saveRDS(pnadc_lm, lm_cache, compress = "xz")
    message("Cache consolidado de mercado de trabalho salvo em: ", lm_cache)
    # Remove caches individuais (redundantes após consolidação)
    file.remove(Filter(file.exists,
      file.path(CACHE_DIR, sprintf("lm_%d.rds", PNADC_YEARS))))
    message("Caches individuais por ano removidos.")
  } else {
    message("Cache consolidado NÃO salvo — anos faltando: ",
            paste(anos_fail_lm, collapse = ", "))
  }
}

message(sprintf("pnadc_lm: %d linhas (%.1f MB)",
                nrow(pnadc_lm),
                as.numeric(object.size(pnadc_lm)) / 1e6))


# =============================================================================
# SEÇÃO 4 – PNADC EDUCAÇÃO (2º trimestre)
# =============================================================================
# O questionário de educação da PNADC é aplicado no 2º trimestre de cada ano.
# quarter = 2 dá acesso às variáveis brutas do módulo: V3002 (frequência),
# V3003 (curso), V3004 (rede de ensino), V3007 (motivo de não frequentar) e
# V3009A (nível concluído, disponível a partir de 2016).
#
# Cache: pnadc_educ_cache.rds — contém apenas chefe, cônjuge e filhos/parentes
# 14–17 anos (papéis relevantes para análise). Se existir, pula o download.
# Para forçar re-download: file.remove(file.path(CACHE_DIR, "pnadc_educ_cache.rds"))
# =============================================================================

educ_cache <- file.path(CACHE_DIR, "pnadc_educ_cache.rds")

EDUC_V2_VARS <- c(
  "Ano", "UF", "UPA", "Estrato",
  "V1008",   # número do domicílio
  "V2003",   # número de ordem
  "V1029",   # peso calibrado (trimestral — diferente da anual que usa V1032)
  "V2005",   # condição no domicílio
  "V2007",   # sexo
  "V2009",   # idade
  "V2010",   # cor/raça
  "V1022",   # situação do domicílio (urbano/rural)
  "V3001",   # sabe ler e escrever
  "V3002",   # frequenta escola
  "V3003",   # curso que frequenta
  "V3004",   # rede de ensino (pública/privada)
  "V3007",   # motivo de não frequentar
  "V3009A"   # nível concluído mais elevado (a partir de 2016)
)

import_pnadc_educ_v2 <- function(yr) {
  message(sprintf("  Importando educação %d (2º trimestre)...", yr))
  df <- tryCatch(
    get_pnadc(year = yr, quarter = 2, vars = EDUC_V2_VARS, design = FALSE),
    error = function(e) { warning(sprintf("  Falhou %d: %s", yr, e$message)); NULL }
  )
  if (is.null(df)) return(NULL)

  df |>
    rename(any_of(c(
      pes_comcalib    = "V1029",   # trimestral usa V1029 (anual usa V1032)
      n_domic         = "V1008",
      num_ordem       = "V2003",
      condno_domic    = "V2005",
      sexo            = "V2007",
      idade           = "V2009",
      cor_raca        = "V2010",
      sit_domic       = "V1022",
      sabe_ler        = "V3001",
      freq_escola     = "V3002",
      curso_freq      = "V3003",
      rede_ensino     = "V3004",
      motivo_nao_freq = "V3007",
      nivel_concluido = "V3009A"
    ))) |>
    mutate(
      domic_id  = paste(UF, UPA, n_domic, sep = "_"),
      pessoa_id = paste(domic_id, num_ordem, sep = "_"),

      freq_esc_bin = as.integer(as.character(freq_escola) == "Sim"),

      nivel_lbl  = as.character(nivel_concluido),
      anos_estudo = case_when(
        is.na(nivel_lbl)                                                 ~ NA_real_,
        str_detect(nivel_lbl, "(?i)sem instru")                          ~ 0,
        str_detect(nivel_lbl, "(?i)fundamental.*incompleto")             ~ 4,
        str_detect(nivel_lbl, "(?i)fundamental.*completo")               ~ 9,
        str_detect(nivel_lbl, "(?i)médio.*incompleto|medio.*incompleto") ~ 10,
        str_detect(nivel_lbl, "(?i)médio.*completo|medio.*completo")     ~ 12,
        str_detect(nivel_lbl, "(?i)superior.*incompleto")                ~ 14,
        str_detect(nivel_lbl, "(?i)superior.*completo|gradua")           ~ 16,
        TRUE ~ NA_real_
      ),

      serie_freq_lbl = as.character(curso_freq),
      serie_num      = suppressWarnings(
        as.integer(str_extract(serie_freq_lbl, "\\d+"))
      ),
      serie_esperada = pmax(1L, idade - 6L),
      defasagem      = if_else(freq_esc_bin == 1L,
                               pmax(0L, serie_esperada - serie_num),
                               NA_integer_),
      defasagem_bin  = if_else(freq_esc_bin == 1L,
                               as.integer(defasagem >= 2L),
                               NA_integer_),

      mot_lbl = as.character(motivo_nao_freq),
      motivo_simpl = case_when(
        is.na(mot_lbl)                                                                  ~ NA_character_,
        str_detect(mot_lbl, "(?i)trabal")                                               ~ "Trabalho",
        str_detect(mot_lbl, "(?i)cuidad|filho|domést|domest")                          ~ "Cuidado doméstico / filhos",
        str_detect(mot_lbl, "(?i)gravid|grávid|gestaç")                                ~ "Gravidez",
        str_detect(mot_lbl, "(?i)interesse|não quer|nao quer|desinter")                ~ "Falta de interesse",
        str_detect(mot_lbl, "(?i)conclu")                                              ~ "Concluiu os estudos",
        str_detect(mot_lbl, "(?i)distância|distancia|acesso|escola.*longe|transp")     ~ "Acesso / distância",
        TRUE ~ "Outro"
      )
    )
}

if (file.exists(educ_cache)) {
  message("Carregando educação do cache local (pulando download)...")
  pnadc_educ   <- readRDS(educ_cache)
  anos_ok_v2   <- as.character(sort(unique(pnadc_educ$Ano)))
  anos_fail_v2 <- character(0)
  message(sprintf("pnadc_educ: %d linhas | %d anos", nrow(pnadc_educ), length(anos_ok_v2)))

} else {
  # Acúmulo incremental: bind + gc a cada ano para não manter todos em memória
  # simultaneamente. Evita estouro de RAM com ~10 anos de dados trimestrais.
  message("Baixando módulo de educação — 2º trimestre (pode demorar)...")
  pnadc_educ   <- NULL
  anos_ok_v2   <- character(0)
  anos_fail_v2 <- character(0)

  papeis_relevantes <- c(
    "Pessoa responsável pelo domicílio",
    "Cônjuge ou companheiro(a) de sexo diferente"
  )

  for (yr in PNADC_YEARS) {
    yr_educ_cache <- file.path(CACHE_DIR, sprintf("educ_%d.rds", yr))

    if (file.exists(yr_educ_cache)) {
      message(sprintf("  Ano %d: carregando do cache.", yr))
      yr_data <- readRDS(yr_educ_cache)
    } else {
      yr_data <- import_pnadc_educ_v2(yr)

      # ── Limpa zips do temp IMEDIATAMENTE após o download de cada ano ──────
      # get_pnadc() salva ~230 MB por ano em tempdir() sem limpar.
      # 10 anos × 230 MB = ~2.3 GB acumulados. Remover aqui evita o erro
      # "No space left on device" / "fwrite error" a partir do 5º ano.
      temp_zips <- list.files(tempdir(), pattern = "\\.zip$",
                              full.names = TRUE, recursive = TRUE)
      if (length(temp_zips) > 0) {
        unlink(temp_zips)
        message(sprintf("  Temp limpo: %d zip(s) removidos.", length(temp_zips)))
      }

      if (!is.null(yr_data)) {
        # Filtra já no cache individual para economizar disco
        yr_data <- yr_data |>
          filter(
            condno_domic %in% papeis_relevantes |
            (idade >= 14L & idade <= 17L &
             str_detect(as.character(condno_domic), "(?i)filho|enteado|parente"))
          )
        saveRDS(yr_data, yr_educ_cache, compress = "xz")
        message(sprintf("  Ano %d: salvo em cache (%d linhas).", yr, nrow(yr_data)))
      }
    }

    if (is.null(yr_data)) {
      anos_fail_v2 <- c(anos_fail_v2, as.character(yr))
    } else {
      pnadc_educ <- bind_rows(pnadc_educ, yr_data)
      anos_ok_v2 <- c(anos_ok_v2, as.character(yr))
      rm(yr_data); gc()
    }
  }

  if (length(anos_fail_v2) > 0)
    warning("Anos educação não importados: ", paste(anos_fail_v2, collapse = ", "))

  message(sprintf("pnadc_educ (filtrado): %d linhas | %d anos (%.1f MB)",
                  nrow(pnadc_educ), length(anos_ok_v2),
                  as.numeric(object.size(pnadc_educ)) / 1e6))
  gc()

  message("Salvando cache consolidado pnadc_educ (compress = 'xz', pode demorar)...")
  saveRDS(pnadc_educ, educ_cache, compress = "xz")
  message("Cache salvo em: ", educ_cache)

  # Remove caches individuais por ano (redundantes após consolidação)
  if (length(anos_fail_v2) == 0) {
    file.remove(Filter(file.exists,
      file.path(CACHE_DIR, sprintf("educ_%d.rds", PNADC_YEARS))))
    message("Caches individuais de educação por ano removidos.")
  }
}

message("01_importacao.R concluído.")
