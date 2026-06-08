# =============================================================================
# 02_preparacao.R — Preparação dos dados para análise
# =============================================================================
# Depende de: 01_importacao.R (pnadc_categ, pnadc_lm, pnadc_educ)
#
# Produz:
#   pnadc_categ_slim  — versão enxuta de pnadc_categ (só colunas de análise)
#   pnadc_srvyr       — objeto de survey para análises PNADC principais
#   pnadc_categ_lm    — pnadc_categ + variáveis de mercado de trabalho
#   pnadc_lm_srvyr    — objeto de survey para análises de mercado de trabalho
#   pnadc_educ        — pnadc_educ com categ_domic reconstruída (2º trimestre)
#   educ_srvyr        — objeto de survey para análises educacionais
# =============================================================================

source(here::here("00_setup.R"))

# =============================================================================
# 2A – DESIGN AMOSTRAL PRINCIPAL (pnadc_srvyr)
# =============================================================================
# Reduz para colunas necessárias antes de criar o objeto de survey,
# o que evita dobrar o uso de memória com 248 variáveis.

gc()

cols_survey <- c(
  "UPA", "Estrato", "pes_comcalib",
  "domic_id", "pessoa_id", "Ano", "regiao",
  "condno_domic", "categ_domic", "dif_idade",
  "sexo_bin", "parda_preta_bin", "ler_escrever_bin",
  "trab_remun_bin", "afastd_bin", "matern_bin",
  "cuidado_provid_bin", "cuidado_trab_bin",
  "rend", "horas_trabalhadas_seman", "freq_esc",
  "idade", "trab_remun",
  "sit_domic"
)

pnadc_categ_slim <- pnadc_categ |>
  select(all_of(cols_survey)) |>
  mutate(
    sm      = as.numeric(sm_lookup[as.character(Ano)]),
    rend_sm = if_else(!is.na(rend) & sm > 0, rend / sm, NA_real_)
  )

message(sprintf("pnadc_categ_slim: %d linhas x %d variáveis (era %d variáveis)",
                nrow(pnadc_categ_slim), ncol(pnadc_categ_slim), ncol(pnadc_categ)))
gc()

# A PNADC é amostra complexa: ids (UPA) e strata (Estrato) são obrigatórios
# para erros padrão e IC corretos. Usar só pesos subestima a variância.
pnadc_srvyr <- pnadc_categ_slim |>
  as_survey_design(
    ids     = UPA,
    strata  = Estrato,
    weights = pes_comcalib,
    nest    = TRUE
  )

message("pnadc_srvyr criado.")

# =============================================================================
# 2B – DESIGN AMOSTRAL DE MERCADO DE TRABALHO (pnadc_lm_srvyr)
# =============================================================================

message("Cruzando mercado de trabalho com pnadc_categ...")
pnadc_categ_lm <- pnadc_categ |>
  left_join(
    pnadc_lm |> select(pessoa_id, Ano, formal_bin, pos_simples),
    by = c("pessoa_id", "Ano")
  )

message(sprintf("  cobertura formal_bin: %.1f%%",
                mean(!is.na(pnadc_categ_lm$formal_bin)) * 100))

pnadc_lm_srvyr <- pnadc_categ_lm |>
  filter(!is.na(categ_domic)) |>
  select(UPA, Estrato, pes_comcalib, Ano, categ_domic, condno_domic,
         regiao, sexo_bin, idade, rend, trab_remun, trab_remun_bin,
         horas_trabalhadas_seman, cuidado_trab_bin, cuidado_provid_bin,
         parda_preta_bin, formal_bin, pos_simples) |>
  as_survey_design(
    ids     = UPA,
    strata  = Estrato,
    weights = pes_comcalib,
    nest    = TRUE
  )

message("pnadc_lm_srvyr criado.")

# =============================================================================
# 2C – RECONSTRUÇÃO DE categ_domic PARA EDUCAÇÃO (2º trimestre)
# =============================================================================
# O 2º trimestre não garante simultaneamente chefe + cônjuge em todos os
# domicílios. Verificamos a completude antes de reconstruir categ_domic.
#
# CACHE: pnadc_educ_prep_cache.rds — armazena pnadc_educ já com categ_domic
# e grupo_educ. Evita refazer as operações pesadas a cada execução.
# Para regenerar: file.remove(file.path(CACHE_DIR, "pnadc_educ_prep_cache.rds"))

educ_prep_cache <- file.path(CACHE_DIR, "pnadc_educ_prep_cache.rds")

if (file.exists(educ_prep_cache)) {
  message("Carregando pnadc_educ preparado do cache (pulando reconstrução)...")
  pnadc_educ <- readRDS(educ_prep_cache)

} else {
  # ── Completude: usa distinct + semi_join (vetorizado) em vez de
  # group_by + summarise — evita criar milhões de grupos, ~20× mais rápido ──
  message("Verificando completude do par chefe/cônjuge (educação)...")

  conj_menor_ids <- pnadc_educ |>
    filter(
      str_detect(as.character(condno_domic), "(?i)cônjuge|conjuge|companhe"),
      idade < 18L
    ) |>
    distinct(domic_id, Ano)

  chefe_ids <- pnadc_educ |>
    filter(condno_domic == "Pessoa responsável pelo domicílio") |>
    distinct(domic_id, Ano)

  n_conj_menor <- nrow(conj_menor_ids)
  n_com_chefe  <- nrow(semi_join(conj_menor_ids, chefe_ids,
                                 by = c("domic_id", "Ano")))
  prop_chefe   <- if (n_conj_menor == 0) 0 else n_com_chefe / n_conj_menor

  message(sprintf("  Domicílios com cônjuge menor: %d | com chefe: %d (%.1f%%)",
                  n_conj_menor, n_com_chefe, prop_chefe * 100))

  if (prop_chefe >= 0.90) {
    message("Completude OK (>=90%). Reconstruindo categ_domic via chefe + cônjuge.")

    # distinct(domic_id, Ano, .keep_all = TRUE) após select é ~10× mais rápido
    # que group_by(domic_id, Ano) |> slice(1) — evita criar grupos por linha
    chefes_v2 <- pnadc_educ |>
      filter(condno_domic == "Pessoa responsável pelo domicílio") |>
      select(domic_id, Ano, idade_chefe = idade) |>
      distinct(domic_id, Ano, .keep_all = TRUE)

    conjuges_v2 <- pnadc_educ |>
      filter(str_detect(as.character(condno_domic),
                        "(?i)cônjuge|conjuge|companhe")) |>
      select(domic_id, Ano, idade_conjuge = idade) |>
      distinct(domic_id, Ano, .keep_all = TRUE)

    categ_v2 <- inner_join(chefes_v2, conjuges_v2,
                           by = c("domic_id", "Ano"),
                           relationship = "one-to-one") |>
      mutate(
        categ_domic = case_when(
          idade_chefe <  18 & idade_conjuge <  18 ~ "A",
          idade_chefe <  18 & idade_conjuge >= 18 ~ "B",
          idade_chefe >= 18 & idade_conjuge <  18 ~ "C",
          idade_chefe >= 18 & idade_conjuge >= 18 ~ "D"
        )
      ) |>
      select(domic_id, Ano, categ_domic)

    rm(chefes_v2, conjuges_v2, conj_menor_ids, chefe_ids); gc()

    pnadc_educ <- pnadc_educ |>
      left_join(categ_v2, by = c("domic_id", "Ano"))

    rm(categ_v2); gc()

  } else {
    warning(sprintf(
      "Completude do chefe = %.1f%% (<90%%). Usando proxy conjuge_menor_bin.",
      prop_chefe * 100))
    rm(conj_menor_ids, chefe_ids); gc()
    pnadc_educ <- pnadc_educ |>
      mutate(
        conjuge_menor_bin = as.integer(
          str_detect(as.character(condno_domic),
                     "(?i)cônjuge|conjuge|companhe") & idade < 18),
        categ_domic = if_else(conjuge_menor_bin == 1L, "C", NA_character_)
      )
  }

  # Grupo controle: filhos/parentes adolescentes (14–17 anos)
  pnadc_educ <- pnadc_educ |>
    mutate(
      filho_adolesc_bin = as.integer(
        str_detect(as.character(condno_domic),
                   "(?i)filho|enteado|outro parente|parente") &
        idade >= 14 & idade <= 17
      ),
      grupo_educ = case_when(
        categ_domic == "C"      ~ "Cônjuge < 18",
        filho_adolesc_bin == 1L ~ "Filho/parente 14–17",
        TRUE                    ~ NA_character_
      )
    )

  message(sprintf("  cônjuges < 18 (cat. C): %d  |  filhos/parentes 14–17: %d",
                  sum(pnadc_educ$grupo_educ == "Cônjuge < 18",        na.rm = TRUE),
                  sum(pnadc_educ$grupo_educ == "Filho/parente 14–17", na.rm = TRUE)))

  # Salva resultado — próximas execuções pulam todo este bloco
  message("Salvando pnadc_educ preparado em cache (compress='xz')...")
  saveRDS(pnadc_educ, educ_prep_cache, compress = "xz")
  message("Cache salvo: ", educ_prep_cache)
}

# Design amostral para educação
educ_srvyr <- pnadc_educ |>
  filter(!is.na(grupo_educ)) |>
  as_survey_design(
    ids     = UPA,
    strata  = Estrato,
    weights = pes_comcalib,
    nest    = TRUE
  )

message("educ_srvyr criado.")
message("02_preparacao.R concluído.")
