# =============================================================================
# 04_analises_PNADC.R — Análises descritivas PNADC + comparação RC × PNADC
# =============================================================================
# Depende de: 02_preparacao.R (pnadc_srvyr, pnadc_categ)
#             03_analises_RC.R (rc_flow, rc_annual)
#
# Produz (estatísticas):
#   profile_pooled, early_annual, profile_annual   (Part 3 — survey stats)
#   rc_stock, pnadc_stock, underreporting          (Part 4 — sub-registro)
#   pnadc_pre_post, age_gap_dist, profile_region   (Part 5.1–5.3)
#   underreporting_ci, profile_hourly              (Part 5.4–5.5)
#   prevalencia_anual, prevalencia_regional_taxa   (Part 5.6–5.7)
#   prevalencia_rural, taxa_participacao           (Part 5.8–5.9)
#   renda_sm_categ, razao_renda_CD                 (Part 5.10–5.11)
#   neet_proxy, taxa_racial                        (Part 5.12–5.13)
#
# Figuras salvas em OUT_DIR:
#   fig6_RC_vs_PNADC_variation.png
#   figNEW_age_gap_distribution.png
#   econ1_prevalencia_anual.png … econ8_racial.png
# =============================================================================

source(here::here("00_setup.R"))

# =============================================================================
# CONTROLES DE EXECUÇÃO
# =============================================================================
#
# FIGURES_ONLY_MODE = TRUE  (padrão recomendado)
#   Pula as análises NÃO usadas em 09_figuras_paper.R:
#     • 3.1 profile_pooled      (pesada: 8 survey_mean × dataset completo)
#     • 3.3 profile_annual      (moderada)
#     • 5.3 profile_region      (moderada)
#     • 5.5 profile_hourly      (moderada)
#     • 5.9  taxa_participacao  (moderada)
#     • 5.10 renda_sm_categ     (moderada)
#     • 5.11 razao_renda_CD     (moderada)
#     • 5.13 taxa_racial        (leve)
#   Resultado: tempo estimado cai de ~60 min → ~20 min; RAM ~30% menor.
#
# FIGURES_ONLY_MODE = FALSE
#   Roda tudo — necessário para gerar tabelas descritivas do paper.
#
FIGURES_ONLY_MODE <- TRUE

# =============================================================================
# HELPER: sub-cache por etapa (crash-resilient)
# =============================================================================
# Cada análise salva seu resultado num arquivo .ckpt_<nome>.rds.
# Na próxima execução, se o arquivo existir, o cálculo é pulado.
# Os arquivos .ckpt são intermediários; os caches combinados (parte3/5) são
# o produto final. Para forçar recomputação, apague os .ckpt correspondentes.

ckpt_path <- function(name) {
  file.path(CACHE_DIR, sprintf(".ckpt_%s.rds", name))
}

with_ckpt <- function(name, fn) {
  p <- ckpt_path(name)
  if (file.exists(p)) {
    message(sprintf("  [ckpt] %s (carregando do disco)", name))
    return(readRDS(p))
  }
  message(sprintf("  [compute] %s...", name))
  res <- fn()
  saveRDS(res, p, compress = FALSE)   # compress=FALSE: I/O muito mais rápido
  gc()
  invisible(res)
}

# =============================================================================
# GARANTIA DE pnadc_srvyr — reconstrói do cache se não estiver em memória
# =============================================================================
# Permite rodar 04_analises_PNADC.R em sessão nova sem ter rodado 02_preparacao.R
# antes. Se pnadc_srvyr já existir (sessão contínua), não faz nada.

if (!exists("pnadc_srvyr") || !inherits(pnadc_srvyr, "tbl_svy")) {
  message("pnadc_srvyr não encontrado — reconstruindo de pnadc_categ_cache.rds...")

  if (!exists("pnadc_categ"))
    pnadc_categ <- readRDS(file.path(CACHE_DIR, "pnadc_categ_cache.rds"))

  cols_survey <- c(
    "UPA","Estrato","pes_comcalib",
    "domic_id","pessoa_id","Ano","regiao",
    "condno_domic","categ_domic","dif_idade",
    "sexo_bin","parda_preta_bin","ler_escrever_bin",
    "trab_remun_bin","afastd_bin","matern_bin",
    "cuidado_provid_bin","cuidado_trab_bin",
    "rend","horas_trabalhadas_seman",
    "freq_esc","idade","trab_remun","sit_domic"
  )

  pnadc_categ_slim <- pnadc_categ |>
    select(any_of(cols_survey)) |>
    mutate(
      sm      = as.numeric(sm_lookup[as.character(Ano)]),
      rend_sm = if_else(!is.na(rend) & sm > 0, rend / sm, NA_real_)
    )

  rm(pnadc_categ); gc()

  pnadc_srvyr <- pnadc_categ_slim |>
    as_survey_design(
      ids     = UPA,
      strata  = Estrato,
      weights = pes_comcalib,
      nest    = TRUE
    )
  message("pnadc_srvyr reconstruído.")
} else {
  message("pnadc_srvyr já está em memória — OK.")
}

# ── Libera objetos pesados não necessários para as análises PNADC ─────────────
rm(list = intersect(ls(), c(
  "pnadc_categ_lm", "pnadc_lm_srvyr", "pnadc_lm",
  "pnadc_educ", "educ_srvyr", "pnadc_categ_slim"
)))
gc()

# =============================================================================
# PART 3 – ESTATÍSTICAS DESCRITIVAS PONDERADAS
# =============================================================================
# Cache combinado: parte3_cache.rds
# Sub-caches por etapa: .ckpt_3_1.rds, .ckpt_3_3.rds  (3.2 não precisa: < 1 s)
#
# DIAGNÓSTICO DE LENTIDÃO:
#   survey_total() / survey_mean() do srvyr estimam variância via linearização
#   de Taylor sobre todos os estratos e PSUs — O(n × nPSU × nStrata) por grupo.
#   Com o dataset completo (~10 anos × centenas de PSUs) isso leva 15–30 min.
#
# SOLUÇÃO EM FIGURES_ONLY_MODE:
#   Para early_annual só é usada a coluna total_early (soma ponderada).
#   Os IC (ci_low/ci_high) NÃO são usados em nenhuma figura.
#   → Substituímos survey_total() por sum(pesos), que roda em < 1 segundo
#     e dá exatamente o mesmo estimador pontual.
#   O SE é preenchido com NA (apenas para manter a estrutura de colunas).

parte3_cache_path <- file.path(CACHE_DIR, "parte3_cache.rds")

if (file.exists(parte3_cache_path)) {
  message("Carregando Parte 3 do cache combinado...")
  parte3 <- readRDS(parte3_cache_path)
  list2env(parte3, envir = environment())
  rm(parte3); gc()

} else {
  message("Parte 3: calculando (modo ",
          if (FIGURES_ONLY_MODE) "rápido — soma de pesos, sem variância"
          else "completo — survey_total() com variância", ")...")

  # ── 3.1  Perfil pooled — pulado em FIGURES_ONLY_MODE ─────────────────────
  if (FIGURES_ONLY_MODE) {
    message("  [skip] 3.1 profile_pooled")
    profile_pooled <- NULL
  } else {
    profile_pooled <- with_ckpt("3_1", function() {
      pnadc_srvyr |>
        group_by(condno_domic, categ_domic) |>
        summarise(
          parda_preta     = survey_mean(parda_preta_bin,         na.rm = TRUE, vartype = "ci"),
          female          = survey_mean(sexo_bin,                na.rm = TRUE, vartype = "ci"),
          literate        = survey_mean(ler_escrever_bin,        na.rm = TRUE, vartype = "ci"),
          has_paid_work   = survey_mean(trab_remun_bin,          na.rm = TRUE, vartype = "ci"),
          mean_income     = survey_mean(rend,                    na.rm = TRUE, vartype = "ci"),
          mean_hours_week = survey_mean(horas_trabalhadas_seman, na.rm = TRUE, vartype = "ci"),
          domestic_care   = survey_mean(cuidado_trab_bin,        na.rm = TRUE, vartype = "ci"),
          mean_age_gap    = survey_mean(dif_idade,               na.rm = TRUE, vartype = "ci"),
          n_obs           = survey_total(vartype = "se")
        )
    })
    message("  3.1 concluído.")
  }

  # ── 3.2  Contagem anual de uniões precoces ────────────────────────────────
  # FIGURES_ONLY_MODE: soma de pesos direta (< 1 s) — mesmo estimador pontual
  #   que survey_total(), mas sem a cara estimação de variância.
  # FULL MODE: survey_total() com variância completa (15–30 min).

  if (FIGURES_ONLY_MODE) {
    message("  3.2 early_annual (soma de pesos — rápido)...")

    # Extrai dados e pesos diretamente do objeto srvyr, sem recarregar nada
    srv_df <- pnadc_srvyr$variables |>
      mutate(.peso = weights(pnadc_srvyr))

    pnadc_counts_annual <- srv_df |>
      filter(condno_domic == "Pessoa responsável pelo domicílio") |>
      group_by(Ano, categ_domic) |>
      summarise(
        n_domic_ponderado     = sum(.peso, na.rm = TRUE),
        n_domic_ponderado_se  = NA_real_,   # não usado em figuras
        n_domic_ponderado_low = NA_real_,
        n_domic_ponderado_upp = NA_real_,
        .groups = "drop"
      )

    early_annual <- pnadc_counts_annual |>
      filter(categ_domic %in% c("A","B","C")) |>
      group_by(Ano) |>
      summarise(
        total_early    = sum(n_domic_ponderado),
        total_early_se = NA_real_,   # não usado em figuras (só total_early é lido)
        ci_low         = NA_real_,
        ci_high        = NA_real_,
        .groups = "drop"
      )

    rm(srv_df); gc()
    message("  3.2 concluído em modo rápido.")

  } else {
    # Modo completo: survey_total() com variância (lento mas correto para tabelas)
    counts_and_early <- with_ckpt("3_2", function() {
      counts <- pnadc_srvyr |>
        filter(condno_domic == "Pessoa responsável pelo domicílio") |>
        group_by(Ano, categ_domic) |>
        summarise(
          n_domic_ponderado = survey_total(vartype = c("se","ci")),
          .groups = "drop"
        )
      early <- counts |>
        filter(categ_domic %in% c("A","B","C")) |>
        group_by(Ano) |>
        summarise(
          total_early    = sum(n_domic_ponderado),
          total_early_se = sqrt(sum(n_domic_ponderado_se^2)),
          .groups = "drop"
        ) |>
        mutate(
          ci_low  = total_early - 1.96 * total_early_se,
          ci_high = total_early + 1.96 * total_early_se
        )
      list(pnadc_counts_annual = counts, early_annual = early)
    })
    pnadc_counts_annual <- counts_and_early$pnadc_counts_annual
    early_annual        <- counts_and_early$early_annual
    rm(counts_and_early)
    message("  3.2 concluído em modo completo.")
  }

  # ── 3.3  Perfil anual — pulado em FIGURES_ONLY_MODE ──────────────────────
  if (FIGURES_ONLY_MODE) {
    message("  [skip] 3.3 profile_annual")
    profile_annual <- NULL
  } else {
    profile_annual <- with_ckpt("3_3", function() {
      pnadc_srvyr |>
        filter(categ_domic %in% c("A","B","C")) |>
        group_by(Ano, condno_domic) |>
        summarise(
          parda_preta   = survey_mean(parda_preta_bin,  na.rm = TRUE, vartype = "ci"),
          female        = survey_mean(sexo_bin,         na.rm = TRUE, vartype = "ci"),
          has_paid_work = survey_mean(trab_remun_bin,   na.rm = TRUE, vartype = "ci"),
          mean_income   = survey_mean(rend,             na.rm = TRUE, vartype = "ci"),
          domestic_care = survey_mean(cuidado_trab_bin, na.rm = TRUE, vartype = "ci"),
          .groups = "drop"
        )
    })
    message("  3.3 concluído.")
  }

  # Salva cache combinado
  saveRDS(
    list(profile_pooled      = profile_pooled,
         pnadc_counts_annual = pnadc_counts_annual,
         early_annual        = early_annual,
         profile_annual      = profile_annual),
    parte3_cache_path, compress = TRUE
  )
  message("Cache da Parte 3 salvo: ", parte3_cache_path)
}
message("Parte 3 concluída. early_annual: ", nrow(early_annual), " anos.")

# =============================================================================
# PART 4 – SUB-REGISTRO: ESTOQUE RC vs PNADC  (manipulação pura, sem survey)
# =============================================================================

# rc_flow vem de 03_analises_RC.R. Se não estiver em memória (sessão nova),
# reconstrói a partir de rc_raw_cache.rds.
if (!exists("rc_flow")) {
  message("rc_flow não encontrado — reconstruindo de rc_raw_cache.rds...")
  rc_raw_tmp <- readRDS(file.path(CACHE_DIR, "rc_raw_cache.rds"))
  rc_flow <- rc_raw_tmp |>
    group_by(ano) |>
    summarise(flow = sum(n_total_row * is_minor_w, na.rm = TRUE), .groups = "drop")
  rm(rc_raw_tmp); gc()
  message("rc_flow reconstruído: ", nrow(rc_flow), " anos.")
}

build_rc_stock <- function(rc_flow_df, max_gap = 4) {
  years <- sort(unique(rc_flow_df$ano))
  map_dfr(years, function(y) {
    tibble(ano = y,
           rc_stock = sum(rc_flow_df$flow[rc_flow_df$ano >= y - max_gap + 1 &
                                          rc_flow_df$ano <= y], na.rm = TRUE))
  })
}

rc_stock <- build_rc_stock(rc_flow)

pnadc_stock <- early_annual |>
  mutate(ano = as.integer(Ano)) |>
  select(-Ano) |>
  rename(pnadc_stock    = total_early,
         pnadc_stock_se = total_early_se,
         pnadc_ci_low   = ci_low,
         pnadc_ci_high  = ci_high)

underreporting <- inner_join(rc_stock, pnadc_stock, by = "ano") |>
  mutate(
    ratio           = pnadc_stock / rc_stock,
    underreport_pct = 1 - rc_stock / pnadc_stock,
    daily_pnadc     = pnadc_stock / 365,
    daily_rc_new    = rc_flow$flow[match(ano, rc_flow$ano)] / 365
  )
gc()

# =============================================================================
# PART 5 – ANÁLISES ECONÔMICAS ADICIONAIS (cache completo)
# =============================================================================
# Cache combinado: parte5_cache.rds
# Sub-caches por etapa: .ckpt_5_<n>.rds
#   → cada análise é salva individualmente; crashes são retomados da etapa
#     onde pararam, sem refazer o trabalho anterior.
# BUG FIX: age_gap_dist agora incluída no cache (antes era recomputada sempre).
# Para forçar recomputação: apague parte5_cache.rds e/ou os .ckpt_5_*.rds.

parte5_cache_path <- file.path(CACHE_DIR, "parte5_cache.rds")

if (file.exists(parte5_cache_path)) {
  message("Carregando Parte 5 do cache combinado...")
  p5 <- readRDS(parte5_cache_path)
  list2env(p5, envir = environment())
  rm(p5); gc()

} else {
  message("Parte 5: calculando (modo ", if (FIGURES_ONLY_MODE) "rápido" else "completo", ")...")

  # ── 5.1  Pré/pós 2019 (manipulação pura) ─────────────────────────────────
  pnadc_pre_post <- underreporting |>
    mutate(periodo = if_else(ano < 2019, "Pre-reform", "Post-reform (excl. COVID)")) |>
    group_by(periodo) |>
    summarise(
      mean_pnadc_stock = mean(pnadc_stock),
      mean_rc_stock    = mean(rc_stock),
      n_years          = n(),
      .groups = "drop"
    ) |>
    mutate(periodo = factor(periodo,
                            levels = c("Pre-reform","Post-reform (excl. COVID)"))) |>
    arrange(periodo) |>
    mutate(
      pct_change_pnadc = (mean_pnadc_stock - lag(mean_pnadc_stock)) / lag(mean_pnadc_stock),
      pct_change_rc    = (mean_rc_stock    - lag(mean_rc_stock))    / lag(mean_rc_stock)
    )

  # ── 5.2  Distribuição da diferença de idade — soma de pesos (rápido) ─────
  # survey_total() daria o mesmo pct; o SE não é usado no gráfico.
  age_gap_dist <- with_ckpt("5_2", function() {
    srv_df2 <- pnadc_srvyr$variables |>
      mutate(.peso = weights(pnadc_srvyr)) |>
      filter(categ_domic == "C",
             condno_domic == "Pessoa responsável pelo domicílio",
             !is.na(dif_idade))
    srv_df2 |>
      group_by(dif_idade) |>
      summarise(n_ponderado    = sum(.peso, na.rm = TRUE),
                n_ponderado_se = NA_real_,
                .groups = "drop") |>
      mutate(pct = n_ponderado / sum(n_ponderado))
  })
  message("  5.2 age_gap_dist concluído.")

  # ── 5.3  Prevalência regional — pulada em FIGURES_ONLY_MODE ──────────────
  if (FIGURES_ONLY_MODE) {
    message("  [skip] 5.3 profile_region")
    profile_region <- NULL
  } else {
    profile_region <- with_ckpt("5_3", function() {
      pnadc_srvyr |>
        filter(categ_domic %in% c("A","B","C"),
               condno_domic == "Pessoa responsável pelo domicílio") |>
        group_by(Ano, regiao) |>
        summarise(
          n_early   = survey_total(vartype = c("se","ci")),
          mean_rend = survey_mean(rend, na.rm = TRUE, vartype = "ci"),
          .groups   = "drop"
        )
    })
    message("  5.3 profile_region concluído.")
  }

  # ── 5.4  Sub-registro com IC (manipulação pura) ───────────────────────────
  underreporting_ci <- underreporting |>
    mutate(
      underreport_low  = 1 - rc_stock / pnadc_ci_high,
      underreport_high = 1 - rc_stock / pnadc_ci_low
    )

  # ── 5.5  Renda por hora — pulada em FIGURES_ONLY_MODE ────────────────────
  if (FIGURES_ONLY_MODE) {
    message("  [skip] 5.5 profile_hourly")
    profile_hourly <- NULL
  } else {
    profile_hourly <- with_ckpt("5_5", function() {
      # usa pnadc_categ_slim via pnadc_srvyr (já tem rend e horas)
      pnadc_srvyr |>
        filter(as.character(trab_remun) == "Sim",
               !is.na(rend), !is.na(horas_trabalhadas_seman),
               horas_trabalhadas_seman > 0) |>
        mutate(rend_hora = rend / (horas_trabalhadas_seman * 4.33)) |>
        group_by(categ_domic, condno_domic) |>
        summarise(
          rend_hora_medio = survey_mean(rend_hora, na.rm = TRUE, vartype = "ci"),
          .groups = "drop"
        )
    })
    message("  5.5 profile_hourly concluído.")
  }

  # ── 5.6  Prevalência anual (sempre necessária para figuras) ──────────────
  prevalencia_anual <- with_ckpt("5_6", function() {
    pnadc_srvyr |>
      filter(condno_domic == "Pessoa responsável pelo domicílio",
             !is.na(categ_domic)) |>
      mutate(early_bin = as.integer(categ_domic %in% c("A","B","C"))) |>
      group_by(Ano) |>
      summarise(
        taxa_uniao_precoce = survey_mean(early_bin, vartype = c("se","ci"), na.rm = TRUE),
        n_domic_conjugais  = survey_total(vartype = "se"),
        .groups = "drop"
      )
  })
  message("  5.6 prevalencia_anual concluído.")

  # ── 5.7  Prevalência por região ───────────────────────────────────────────
  prevalencia_regional_taxa <- with_ckpt("5_7", function() {
    pnadc_srvyr |>
      filter(condno_domic == "Pessoa responsável pelo domicílio",
             !is.na(categ_domic), !is.na(regiao)) |>
      mutate(early_bin = as.integer(categ_domic %in% c("A","B","C"))) |>
      group_by(Ano, regiao) |>
      summarise(
        taxa_uniao_precoce = survey_mean(early_bin, vartype = c("se","ci"), na.rm = TRUE),
        .groups = "drop"
      )
  })
  message("  5.7 prevalencia_regional_taxa concluído.")

  # ── 5.8  Prevalência urbano vs rural ──────────────────────────────────────
  prevalencia_rural <- with_ckpt("5_8", function() {
    pnadc_srvyr |>
      filter(condno_domic == "Pessoa responsável pelo domicílio",
             !is.na(categ_domic), !is.na(sit_domic)) |>
      mutate(
        early_bin = as.integer(categ_domic %in% c("A","B","C")),
        area      = if_else(str_detect(as.character(sit_domic), "(?i)rural"),
                            "Rural", "Urbano")
      ) |>
      group_by(Ano, area) |>
      summarise(
        taxa_uniao_precoce = survey_mean(early_bin, vartype = c("se","ci"), na.rm = TRUE),
        .groups = "drop"
      )
  })
  message("  5.8 prevalencia_rural concluído.")

  # ── 5.9  Taxa de participação laboral — pulada em FIGURES_ONLY_MODE ───────
  if (FIGURES_ONLY_MODE) {
    message("  [skip] 5.9 taxa_participacao")
    taxa_participacao <- NULL
  } else {
    taxa_participacao <- with_ckpt("5_9", function() {
      pnadc_srvyr |>
        filter(!is.na(categ_domic)) |>
        mutate(sexo_label = if_else(sexo_bin == 1L, "Mulher", "Homem")) |>
        group_by(Ano, categ_domic, condno_domic, sexo_label) |>
        summarise(
          taxa_ocupacao    = survey_mean(trab_remun_bin,   na.rm = TRUE, vartype = c("se","ci")),
          taxa_cuidado_dom = survey_mean(cuidado_trab_bin, na.rm = TRUE, vartype = c("se","ci")),
          .groups = "drop"
        )
    })
    message("  5.9 taxa_participacao concluído.")
  }

  # ── 5.10  Renda em salários mínimos — pulada em FIGURES_ONLY_MODE ─────────
  if (FIGURES_ONLY_MODE) {
    message("  [skip] 5.10 renda_sm_categ")
    renda_sm_categ <- NULL
  } else {
    renda_sm_categ <- with_ckpt("5_10", function() {
      pnadc_srvyr |>
        filter(!is.na(categ_domic), !is.na(rend_sm)) |>
        group_by(Ano, categ_domic, condno_domic) |>
        summarise(
          media_rend_sm = survey_mean(rend_sm, na.rm = TRUE, vartype = c("se","ci")),
          .groups = "drop"
        )
    })
    message("  5.10 renda_sm_categ concluído.")
  }

  # ── 5.11  Razão de renda C/D — pulada em FIGURES_ONLY_MODE ───────────────
  if (FIGURES_ONLY_MODE) {
    message("  [skip] 5.11 razao_renda_CD")
    razao_renda_CD <- NULL
  } else {
    razao_renda_CD <- with_ckpt("5_11", function() {
      renda_por_cat <- pnadc_srvyr |>
        filter(condno_domic == "Cônjuge ou companheiro(a) de sexo diferente",
               categ_domic %in% c("C","D"), sexo_bin == 1L, !is.na(rend)) |>
        group_by(Ano, categ_domic) |>
        summarise(
          renda_media = survey_mean(rend, na.rm = TRUE, vartype = c("se","ci")),
          .groups = "drop"
        )
      renda_por_cat |>
        select(Ano, categ_domic, renda_media) |>
        pivot_wider(names_from = categ_domic, values_from = renda_media,
                    names_prefix = "renda_") |>
        mutate(razao_C_D      = renda_C / renda_D,
               penalidade_pct = (1 - razao_C_D) * 100)
    })
    message("  5.11 razao_renda_CD concluído.")
  }

  # ── 5.12  NEET proxy (sempre necessário para figuras) ────────────────────
  neet_proxy <- with_ckpt("5_12", function() {
    pnadc_srvyr |>
      filter(condno_domic == "Cônjuge ou companheiro(a) de sexo diferente",
             idade < 18, !is.na(categ_domic)) |>
      mutate(
        estuda_bin = as.integer(!is.na(freq_esc) & as.character(freq_esc) == "Sim"),
        neet_bin   = as.integer(trab_remun_bin == 0L & estuda_bin == 0L)
      ) |>
      group_by(Ano, categ_domic) |>
      summarise(
        taxa_neet   = survey_mean(neet_bin,       na.rm = TRUE, vartype = c("se","ci")),
        taxa_escola = survey_mean(estuda_bin,     na.rm = TRUE, vartype = c("se","ci")),
        taxa_trab   = survey_mean(trab_remun_bin, na.rm = TRUE, vartype = c("se","ci")),
        .groups = "drop"
      )
  })
  message("  5.12 neet_proxy concluído.")

  # ── 5.13  Taxa racial — pulada em FIGURES_ONLY_MODE ──────────────────────
  if (FIGURES_ONLY_MODE) {
    message("  [skip] 5.13 taxa_racial")
    taxa_racial <- NULL
  } else {
    taxa_racial <- with_ckpt("5_13", function() {
      pnadc_srvyr |>
        filter(condno_domic == "Cônjuge ou companheiro(a) de sexo diferente",
               !is.na(categ_domic)) |>
        group_by(Ano, categ_domic) |>
        summarise(
          taxa_parda_preta = survey_mean(parda_preta_bin, na.rm = TRUE, vartype = c("se","ci")),
          .groups = "drop"
        )
    })
    message("  5.13 taxa_racial concluído.")
  }

  # ── Libera pnadc_srvyr — não é mais necessário após este ponto ───────────
  rm(pnadc_srvyr); gc()
  message("pnadc_srvyr liberado.")

  # Salva cache combinado (inclui NULLs para itens pulados — inofensivo)
  saveRDS(
    list(
      age_gap_dist              = age_gap_dist,           # BUG FIX: era omitida
      pnadc_pre_post            = pnadc_pre_post,
      underreporting_ci         = underreporting_ci,
      profile_region            = profile_region,
      profile_hourly            = profile_hourly,
      prevalencia_anual         = prevalencia_anual,
      prevalencia_regional_taxa = prevalencia_regional_taxa,
      prevalencia_rural         = prevalencia_rural,
      taxa_participacao         = taxa_participacao,
      renda_sm_categ            = renda_sm_categ,
      razao_renda_CD            = razao_renda_CD,
      neet_proxy                = neet_proxy,
      taxa_racial               = taxa_racial
    ),
    parte5_cache_path, compress = TRUE
  )
  message("Cache da Parte 5 salvo: ", parte5_cache_path)
}

message("Análises econômicas (Partes 4–5) concluídas.")

# =============================================================================
# FIGURAS PNADC
# =============================================================================

# Figura 6: Variação anual RC vs PNADC
p2 <- underreporting |>
  left_join(rc_flow, by = "ano") |>
  mutate(
    var_pnadc = (pnadc_stock - lag(pnadc_stock)) / lag(pnadc_stock) * 100,
    var_rc    = (flow - lag(flow)) / lag(flow) * 100
  ) |>
  filter(!is.na(var_pnadc)) |>
  pivot_longer(c(var_pnadc, var_rc), names_to = "source", values_to = "pct_change") |>
  mutate(source = recode(source,
    var_pnadc = "PNADC (survey stock)",
    var_rc    = "Civil Registry (flow)"
  )) |>
  ggplot(aes(x = ano, y = pct_change, color = source, group = source)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "gray50") +
  geom_line(linewidth = 1) + geom_point(size = 2) +
  scale_color_brewer(palette = "Set2", name = NULL) +
  scale_x_continuous(breaks = seq(2012, 2019, 1)) +
  scale_y_continuous(labels = label_percent(scale = 1)) +
  labs(
    title    = "Figure 6: Annual % Change in Early Unions: Civil Registry vs. PNADC",
    subtitle = "PNADC shows lower and more volatile decline than civil registry data",
    x = NULL, y = "Year-on-year change (%)",
    caption  = "Source: IBGE (Civil Registry & PNADC). Authors' elaboration."
  ) + theme_paper

ggsave(file.path(OUT_DIR, "fig6_RC_vs_PNADC_variation.png"), p2,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")

# Figura NEW: Distribuição da diferença de idade (cat C)
p3 <- age_gap_dist |>
  filter(!is.na(dif_idade), dif_idade <= 30) |>
  ggplot(aes(x = dif_idade, y = pct)) +
  geom_col(fill = "#C0392B", alpha = .8) +
  geom_vline(xintercept = 10, linetype = "dashed", color = "gray30") +
  annotate("text", x = 10.5, y = max(age_gap_dist$pct, na.rm = TRUE) * .9,
           label = "Mean ≈ 8 yrs", hjust = 0, size = 3.2) +
  scale_x_continuous(breaks = seq(0, 30, 5)) +
  scale_y_continuous(labels = label_percent()) +
  labs(
    title    = "NEW Figure: Age Gap Distribution – Households where Spouse is a Minor",
    subtitle = "Category C: household head ≥ 18, spouse < 18 (PNADC pooled, 2012–2023)",
    x = "Age gap (years)", y = "Share of households",
    caption  = "Source: PNADC, survey-weighted. Authors' elaboration."
  ) + theme_paper

ggsave(file.path(OUT_DIR, "figNEW_age_gap_distribution.png"), p3,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")

# ── ECON Plot 1: Prevalência anual ────────────────────────────────────────────
econ_p1 <- prevalencia_anual |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  ggplot(aes(x = Ano, y = taxa_uniao_precoce)) +
  geom_ribbon(aes(ymin = taxa_uniao_precoce_low,
                  ymax = taxa_uniao_precoce_upp),
              alpha = 0.15, fill = "#2E4053") +
  geom_line(color = "#2E4053", linewidth = 1) +
  geom_point(color = "#2E4053", size = 2.5) +
  geom_vline(xintercept = 2019, linetype = "dashed", color = "red", alpha = .7) +
  annotate("text", x = 2019.2,
           y = max(prevalencia_anual$taxa_uniao_precoce, na.rm = TRUE) * 0.97,
           label = "Lei 13.811/2019", hjust = 0, size = 3, color = "red") +
  scale_x_continuous(breaks = anos_pnadc) +
  scale_y_continuous(labels = label_percent(accuracy = 0.1)) +
  labs(
    title    = "ECON 1: Taxa de Prevalência de Uniões Precoces",
    subtitle = "% de domicílios conjugais com ao menos um cônjuge < 18 anos (PNADC)",
    x = NULL, y = "Prevalência (%)",
    caption  = "Fonte: PNADC. Estimativas com desenho amostral complexo. Banda = IC 95%."
  ) + theme_paper

ggsave(file.path(OUT_DIR, "econ1_prevalencia_anual.png"), econ_p1,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# ── ECON Plot 2: Prevalência por região ───────────────────────────────────────
econ_p2 <- prevalencia_regional_taxa |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  filter(!is.na(regiao)) |>
  ggplot(aes(x = Ano, y = taxa_uniao_precoce,
             color = regiao, group = regiao)) +
  geom_ribbon(aes(ymin = taxa_uniao_precoce_low,
                  ymax = taxa_uniao_precoce_upp,
                  fill = regiao),
              alpha = 0.1, color = NA) +
  geom_line(linewidth = 0.9) + geom_point(size = 2) +
  scale_color_brewer(palette = "Set1", name = "Região") +
  scale_fill_brewer(palette  = "Set1", guide  = "none") +
  scale_x_continuous(breaks = anos_pnadc) +
  scale_y_continuous(labels = label_percent(accuracy = 0.1)) +
  labs(
    title    = "ECON 2: Prevalência de Uniões Precoces por Região",
    subtitle = "% de domicílios conjugais com cônjuge < 18 — comparação regional",
    x = NULL, y = "Prevalência (%)",
    caption  = "Fonte: PNADC. Banda = IC 95%. Elaboração dos autores."
  ) + theme_paper

ggsave(file.path(OUT_DIR, "econ2_prevalencia_regional.png"), econ_p2,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# ── ECON Plot 3: Prevalência urbano vs rural ──────────────────────────────────
econ_p3 <- prevalencia_rural |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  filter(!is.na(area)) |>
  ggplot(aes(x = Ano, y = taxa_uniao_precoce,
             color = area, group = area)) +
  geom_ribbon(aes(ymin = taxa_uniao_precoce_low,
                  ymax = taxa_uniao_precoce_upp,
                  fill = area),
              alpha = 0.15, color = NA) +
  geom_line(linewidth = 1) + geom_point(size = 2.5) +
  scale_color_manual(values = c("Rural" = "#C0392B", "Urbano" = "#2980B9"), name = NULL) +
  scale_fill_manual(values  = c("Rural" = "#C0392B", "Urbano" = "#2980B9"), guide = "none") +
  scale_x_continuous(breaks = anos_pnadc) +
  scale_y_continuous(labels = label_percent(accuracy = 0.1)) +
  labs(
    title    = "ECON 3: Prevalência de Uniões Precoces — Urbano vs Rural",
    subtitle = "% de domicílios conjugais com cônjuge < 18 por área de residência",
    x = NULL, y = "Prevalência (%)",
    caption  = "Fonte: PNADC. Banda = IC 95%. Elaboração dos autores."
  ) + theme_paper

ggsave(file.path(OUT_DIR, "econ3_prevalencia_rural.png"), econ_p3,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# ── ECON Plot 4: Taxa de participação laboral — cônjuges mulheres ─────────────
econ_p4 <- taxa_participacao |>
  filter(condno_domic == "Cônjuge ou companheiro(a) de sexo diferente",
         categ_domic %in% c("C","D"), sexo_label == "Mulher") |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  ggplot(aes(x = Ano, y = taxa_ocupacao,
             color = categ_domic, group = categ_domic)) +
  geom_ribbon(aes(ymin = taxa_ocupacao_low,
                  ymax = taxa_ocupacao_upp,
                  fill = categ_domic),
              alpha = 0.15, color = NA) +
  geom_line(linewidth = 1) + geom_point(size = 2.5) +
  scale_color_manual(values = cores_categ,
                     labels = c("C"="Cat. C (cônjuge < 18)","D"="Cat. D (controle adulto)"),
                     name = NULL) +
  scale_fill_manual(values = cores_categ, guide = "none") +
  scale_x_continuous(breaks = anos_pnadc) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(
    title    = "ECON 4: Taxa de Participação Laboral – Cônjuges Mulheres",
    subtitle = "% com trabalho remunerado: união precoce (C) vs controle adulto (D)",
    x = NULL, y = "Taxa de ocupação (%)",
    caption  = "Fonte: PNADC. Banda = IC 95%. Elaboração dos autores."
  ) + theme_paper

ggsave(file.path(OUT_DIR, "econ4_participacao_laboral.png"), econ_p4,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# ── ECON Plot 5: Renda em múltiplos do salário mínimo ─────────────────────────
econ_p5 <- renda_sm_categ |>
  filter(condno_domic == "Cônjuge ou companheiro(a) de sexo diferente",
         categ_domic %in% c("C","D")) |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  ggplot(aes(x = Ano, y = media_rend_sm,
             color = categ_domic, group = categ_domic)) +
  geom_ribbon(aes(ymin = media_rend_sm_low,
                  ymax = media_rend_sm_upp,
                  fill = categ_domic),
              alpha = 0.15, color = NA) +
  geom_hline(yintercept = 1, linetype = "dotted", color = "gray50") +
  annotate("text", x = min(anos_pnadc), y = 1.04,
           label = "1 salário mínimo", hjust = 0, size = 3, color = "gray40") +
  geom_line(linewidth = 1) + geom_point(size = 2.5) +
  scale_color_manual(values = cores_categ,
                     labels = c("C"="Cat. C (cônjuge < 18)","D"="Cat. D (controle adulto)"),
                     name = NULL) +
  scale_fill_manual(values = cores_categ, guide = "none") +
  scale_x_continuous(breaks = anos_pnadc) +
  labs(
    title    = "ECON 5: Renda Média em Múltiplos do Salário Mínimo",
    subtitle = "Cônjuges: renda normalizada pelo SM do ano — elimina efeito da inflação",
    x = NULL, y = "Renda (nº de salários mínimos)",
    caption  = "Fonte: PNADC. Banda = IC 95%. Elaboração dos autores."
  ) + theme_paper

ggsave(file.path(OUT_DIR, "econ5_renda_salario_minimo.png"), econ_p5,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# ── ECON Plot 6: Razão de renda C/D ───────────────────────────────────────────
econ_p6 <- razao_renda_CD |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  filter(!is.na(razao_C_D)) |>
  ggplot(aes(x = Ano, y = razao_C_D)) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "gray50") +
  annotate("text", x = min(razao_renda_CD$Ano, na.rm = TRUE),
           y = 1.02, label = "Paridade (sem penalidade)",
           hjust = 0, size = 3, color = "gray40") +
  geom_line(color = "#C0392B", linewidth = 1) +
  geom_point(color = "#C0392B", size = 2.5) +
  geom_area(fill = "#C0392B", alpha = 0.1) +
  scale_x_continuous(breaks = anos_pnadc) +
  scale_y_continuous(labels = label_number(accuracy = 0.01), limits = c(0, NA)) +
  labs(
    title    = "ECON 6: Índice de Desvantagem Econômica — Renda C/D",
    subtitle = "Razão de renda entre cônjuge em união precoce (C) e adulta (D). Abaixo de 1 = penalidade.",
    x = NULL, y = "Razão de renda (C ÷ D)",
    caption  = "Fonte: PNADC. Elaboração dos autores."
  ) + theme_paper

ggsave(file.path(OUT_DIR, "econ6_penalidade_renda.png"), econ_p6,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# ── ECON Plot 7: NEET, escola e trabalho ──────────────────────────────────────
econ_p7 <- neet_proxy |>
  filter(categ_domic %in% c("C","D")) |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  pivot_longer(c(taxa_neet, taxa_escola, taxa_trab),
               names_to = "indicador", values_to = "taxa") |>
  mutate(
    indicador = recode(indicador,
      taxa_neet   = "NEET (nem trabalha nem estuda)",
      taxa_escola = "Frequenta escola",
      taxa_trab   = "Trabalho remunerado"
    ),
    categ_label = if_else(categ_domic == "C",
                          "Cat. C – cônjuge < 18", "Cat. D – controle adulto")
  ) |>
  ggplot(aes(x = Ano, y = taxa, color = indicador, group = indicador)) +
  geom_line(linewidth = 0.9) + geom_point(size = 2) +
  facet_wrap(~ categ_label) +
  scale_color_manual(
    values = c("NEET (nem trabalha nem estuda)" = "#C0392B",
               "Frequenta escola"               = "#2980B9",
               "Trabalho remunerado"            = "#27AE60"),
    name = NULL
  ) +
  scale_x_continuous(breaks = c(2012, 2015, 2019, 2022)) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(
    title    = "ECON 7: NEET, Escola e Trabalho — Cônjuges Menores de 18",
    subtitle = "Taxas entre cônjuges < 18: cat. C (união precoce) vs cat. D (controle adulto)",
    x = NULL, y = "Taxa (%)",
    caption  = "Fonte: PNADC. Elaboração dos autores. NEET = não trabalha e não estuda."
  ) + theme_paper

ggsave(file.path(OUT_DIR, "econ7_neet.png"), econ_p7,
       width = 24, height = 13, units = "cm", dpi = 300, bg = "white")

# ── ECON Plot 8: Composição racial ────────────────────────────────────────────
econ_p8 <- taxa_racial |>
  filter(categ_domic %in% c("C","D")) |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  ggplot(aes(x = Ano, y = taxa_parda_preta,
             color = categ_domic, group = categ_domic)) +
  geom_ribbon(aes(ymin = taxa_parda_preta_low,
                  ymax = taxa_parda_preta_upp,
                  fill = categ_domic),
              alpha = 0.15, color = NA) +
  geom_line(linewidth = 1) + geom_point(size = 2.5) +
  scale_color_manual(values = cores_categ,
                     labels = c("C"="Cat. C (cônjuge < 18)","D"="Cat. D (controle adulto)"),
                     name = NULL) +
  scale_fill_manual(values = cores_categ, guide = "none") +
  scale_x_continuous(breaks = anos_pnadc) +
  scale_y_continuous(labels = label_percent(accuracy = 1), limits = c(0, 1)) +
  labs(
    title    = "ECON 8: % de Cônjuges Pardas e Pretas por Categoria",
    subtitle = "Desigualdade racial: uniões precoces concentram-se mais entre mulheres pardas/pretas?",
    x = NULL, y = "% parda ou preta (%)",
    caption  = "Fonte: PNADC. Banda = IC 95%. Elaboração dos autores."
  ) + theme_paper

ggsave(file.path(OUT_DIR, "econ8_racial.png"), econ_p8,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

message("Figuras PNADC (p2, p3, econ_p1–econ_p8) salvas.")
message("04_analises_PNADC.R concluído.")
