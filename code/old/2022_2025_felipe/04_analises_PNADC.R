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

# ── Libera objetos não necessários para as análises PNADC ─────────────────────
# pnadc_lm_srvyr, pnadc_educ e educ_srvyr são usados apenas nos scripts 05 e 06.
# Removê-los aqui libera 5–8 GB de RAM antes das operações pesadas de survey.
rm(list = intersect(ls(), c(
  "pnadc_categ_lm", "pnadc_lm_srvyr", "pnadc_lm",
  "pnadc_educ", "educ_srvyr"
)))
gc()

# =============================================================================
# PART 3 – ESTATÍSTICAS DESCRITIVAS PONDERADAS (com cache)
# =============================================================================
# Cache: parte3_cache.rds — apague se alterar qualquer análise desta seção.

parte3_cache <- file.path(CACHE_DIR, "parte3_cache.rds")

if (file.exists(parte3_cache)) {
  message("Carregando resultados da Parte 3 do cache...")
  parte3 <- readRDS(parte3_cache)
  profile_pooled      <- parte3$profile_pooled
  pnadc_counts_annual <- parte3$pnadc_counts_annual
  early_annual        <- parte3$early_annual
  profile_annual      <- parte3$profile_annual
  rm(parte3)

} else {
  message("Calculando estatísticas de survey (pode demorar 15–30 min)...")

  # ── 3.1  Perfil por categoria de domicílio × papel (pooled) ─────────────────
  message("  3.1 profile_pooled...")
  profile_pooled <- pnadc_srvyr |>
    group_by(condno_domic, categ_domic) |>
    summarise(
      parda_preta      = survey_mean(parda_preta_bin,          na.rm = TRUE, vartype = c("se","ci")),
      female           = survey_mean(sexo_bin,                 na.rm = TRUE, vartype = c("se","ci")),
      literate         = survey_mean(ler_escrever_bin,         na.rm = TRUE, vartype = c("se","ci")),
      has_paid_work    = survey_mean(trab_remun_bin,           na.rm = TRUE, vartype = c("se","ci")),
      mean_income      = survey_mean(rend,                     na.rm = TRUE, vartype = c("se","ci")),
      mean_hours_week  = survey_mean(horas_trabalhadas_seman,  na.rm = TRUE, vartype = c("se","ci")),
      domestic_care    = survey_mean(cuidado_trab_bin,         na.rm = TRUE, vartype = c("se","ci")),
      mean_age_gap     = survey_mean(dif_idade,                na.rm = TRUE, vartype = c("se","ci")),
      n_obs            = survey_total(vartype = "se")
    )
  message("  3.1 concluído.")

  # ── 3.2  Contagem anual de uniões precoces por categoria ─────────────────────
  message("  3.2 pnadc_counts_annual...")
  pnadc_counts_annual <- pnadc_srvyr |>
    filter(condno_domic == "Pessoa responsável pelo domicílio") |>
    group_by(Ano, categ_domic) |>
    summarise(
      n_domic_ponderado = survey_total(vartype = c("se","ci")),
      .groups = "drop"
    )

  early_annual <- pnadc_counts_annual |>
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
  message("  3.2 concluído.")

  # ── 3.3  Perfil anual (variação temporal) ─────────────────────────────────────
  message("  3.3 profile_annual...")
  profile_annual <- pnadc_srvyr |>
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
  message("  3.3 concluído.")

  saveRDS(
    list(profile_pooled      = profile_pooled,
         pnadc_counts_annual = pnadc_counts_annual,
         early_annual        = early_annual,
         profile_annual      = profile_annual),
    parte3_cache, compress = "gz"
  )
  message("Cache da Parte 3 salvo em: ", parte3_cache)
}

# =============================================================================
# PART 4 – SUB-REGISTRO: ESTOQUE RC vs PNADC
# =============================================================================
# Estoque RC no ano y = soma dos fluxos de [y-3, y] (cônjuge <18 tem no máximo
# 4 anos de casamento antes de completar 18). Limite inferior conservador.

build_rc_stock <- function(rc_flow_df, max_gap = 4) {
  years <- sort(unique(rc_flow_df$ano))
  map_dfr(years, function(y) {
    relevant <- rc_flow_df |> filter(ano >= y - max_gap + 1, ano <= y)
    tibble(ano = y, rc_stock = sum(relevant$flow, na.rm = TRUE))
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

# =============================================================================
# PART 5 – ANÁLISES ECONÔMICAS ADICIONAIS
# =============================================================================

# ── 5.1  Pré/pós 2019: PNADC ──────────────────────────────────────────────────
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
         levels = c("Pre-reform", "Post-reform (excl. COVID)"))) |>
  arrange(periodo) |>
  mutate(
    pct_change_pnadc = (mean_pnadc_stock - lag(mean_pnadc_stock)) / lag(mean_pnadc_stock),
    pct_change_rc    = (mean_rc_stock    - lag(mean_rc_stock))    / lag(mean_rc_stock)
  )

# ── 5.2  Distribuição da diferença de idade (cat C) ───────────────────────────
age_gap_dist <- pnadc_srvyr |>
  filter(categ_domic == "C",
         condno_domic == "Pessoa responsável pelo domicílio") |>
  group_by(dif_idade) |>
  summarise(n_ponderado = survey_total(vartype = "se"), .groups = "drop") |>
  mutate(pct = n_ponderado / sum(n_ponderado))

# ── 5.3  Prevalência regional ─────────────────────────────────────────────────
profile_region <- pnadc_srvyr |>
  filter(categ_domic %in% c("A","B","C"),
         condno_domic == "Pessoa responsável pelo domicílio") |>
  group_by(Ano, regiao) |>
  summarise(
    n_early   = survey_total(vartype = c("se","ci")),
    mean_rend = survey_mean(rend, na.rm = TRUE, vartype = "ci"),
    .groups   = "drop"
  )

# ── 5.4  Sub-registro com banda de IC ─────────────────────────────────────────
underreporting_ci <- underreporting |>
  mutate(
    underreport_low  = 1 - rc_stock / pnadc_ci_high,
    underreport_high = 1 - rc_stock / pnadc_ci_low
  )

# ── 5.5  Renda por hora ───────────────────────────────────────────────────────
profile_hourly <- pnadc_categ |>
  filter(trab_remun == "Sim", !is.na(rend), !is.na(horas_trabalhadas_seman),
         horas_trabalhadas_seman > 0) |>
  mutate(rend_hora = rend / (horas_trabalhadas_seman * 4.33)) |>
  as_survey_design(weights = pes_comcalib) |>
  group_by(categ_domic, condno_domic) |>
  summarise(rend_hora_medio = survey_mean(rend_hora, na.rm = TRUE, vartype = "ci"),
            .groups = "drop")

# =============================================================================
# PART 5 (cont.) — ANÁLISES ECONÔMICAS 5.6–5.13 (com cache)
# =============================================================================
# Cache: parte5_cache.rds — apague se alterar qualquer análise desta seção.
# Para regenerar: file.remove(file.path(CACHE_DIR, "parte5_cache.rds"))

parte5_cache <- file.path(CACHE_DIR, "parte5_cache.rds")

if (file.exists(parte5_cache)) {
  message("Carregando resultados 5.6–5.13 do cache...")
  p5 <- readRDS(parte5_cache)
  prevalencia_anual        <- p5$prevalencia_anual
  prevalencia_regional_taxa <- p5$prevalencia_regional_taxa
  prevalencia_rural        <- p5$prevalencia_rural
  taxa_participacao        <- p5$taxa_participacao
  renda_sm_categ           <- p5$renda_sm_categ
  razao_renda_CD           <- p5$razao_renda_CD
  neet_proxy               <- p5$neet_proxy
  taxa_racial              <- p5$taxa_racial
  rm(p5)

} else {
  message("Calculando análises econômicas 5.6–5.13 (pode demorar 20–40 min)...")

  # ── 5.6  Taxa de prevalência anual de uniões precoces ─────────────────────────
  message("  5.6 prevalencia_anual...")
  prevalencia_anual <- pnadc_srvyr |>
    filter(condno_domic == "Pessoa responsável pelo domicílio",
           !is.na(categ_domic)) |>
    mutate(early_bin = as.integer(categ_domic %in% c("A","B","C"))) |>
    group_by(Ano) |>
    summarise(
      taxa_uniao_precoce = survey_mean(early_bin, vartype = c("se","ci"), na.rm = TRUE),
      n_domic_conjugais  = survey_total(vartype = "se"),
      .groups = "drop"
    )
  message("  5.6 concluído.")

  # ── 5.7  Taxa de prevalência por região e ano ─────────────────────────────────
  message("  5.7 prevalencia_regional_taxa...")
  prevalencia_regional_taxa <- pnadc_srvyr |>
    filter(condno_domic == "Pessoa responsável pelo domicílio",
           !is.na(categ_domic), !is.na(regiao)) |>
    mutate(early_bin = as.integer(categ_domic %in% c("A","B","C"))) |>
    group_by(Ano, regiao) |>
    summarise(
      taxa_uniao_precoce = survey_mean(early_bin, vartype = c("se","ci"), na.rm = TRUE),
      .groups = "drop"
    )
  message("  5.7 concluído.")

  # ── 5.8  Taxa de prevalência urbano vs rural ──────────────────────────────────
  message("  5.8 prevalencia_rural...")
  prevalencia_rural <- pnadc_srvyr |>
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
  message("  5.8 concluído.")

  # ── 5.9  Taxa de participação laboral por categoria, papel e gênero ───────────
  message("  5.9 taxa_participacao...")
  taxa_participacao <- pnadc_srvyr |>
    filter(!is.na(categ_domic)) |>
    mutate(sexo_label = if_else(sexo_bin == 1L, "Mulher", "Homem")) |>
    group_by(Ano, categ_domic, condno_domic, sexo_label) |>
    summarise(
      taxa_ocupacao    = survey_mean(trab_remun_bin,   na.rm = TRUE, vartype = c("se","ci")),
      taxa_cuidado_dom = survey_mean(cuidado_trab_bin, na.rm = TRUE, vartype = c("se","ci")),
      .groups = "drop"
    )
  message("  5.9 concluído.")

  # ── 5.10  Renda em múltiplos do salário mínimo por categoria ─────────────────
  message("  5.10 renda_sm_categ...")
  renda_sm_categ <- pnadc_srvyr |>
    filter(!is.na(categ_domic), !is.na(rend_sm)) |>
    group_by(Ano, categ_domic, condno_domic) |>
    summarise(
      media_rend_sm = survey_mean(rend_sm, na.rm = TRUE, vartype = c("se","ci")),
      .groups = "drop"
    )
  message("  5.10 concluído.")

  # ── 5.11  Razão de renda C/D para cônjuges mulheres ──────────────────────────
  message("  5.11 razao_renda_CD...")
  renda_por_cat <- pnadc_srvyr |>
    filter(condno_domic == "Cônjuge ou companheiro(a) de sexo diferente",
           categ_domic %in% c("C","D"), sexo_bin == 1L, !is.na(rend)) |>
    group_by(Ano, categ_domic) |>
    summarise(
      renda_media = survey_mean(rend, na.rm = TRUE, vartype = c("se","ci")),
      .groups = "drop"
    )

  razao_renda_CD <- renda_por_cat |>
    select(Ano, categ_domic, renda_media) |>
    pivot_wider(names_from = categ_domic, values_from = renda_media,
                names_prefix = "renda_") |>
    mutate(
      razao_C_D      = renda_C / renda_D,
      penalidade_pct = (1 - razao_C_D) * 100
    )
  message("  5.11 concluído.")

  # ── 5.12  Taxa NEET para cônjuges < 18 ───────────────────────────────────────
  message("  5.12 neet_proxy...")
  neet_proxy <- pnadc_srvyr |>
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
  message("  5.12 concluído.")

  # ── 5.13  Taxa racial por categoria ──────────────────────────────────────────
  message("  5.13 taxa_racial...")
  taxa_racial <- pnadc_srvyr |>
    filter(condno_domic == "Cônjuge ou companheiro(a) de sexo diferente",
           !is.na(categ_domic)) |>
    group_by(Ano, categ_domic) |>
    summarise(
      taxa_parda_preta = survey_mean(parda_preta_bin, na.rm = TRUE, vartype = c("se","ci")),
      .groups = "drop"
    )
  message("  5.13 concluído.")

  # Salva tudo num único cache
  saveRDS(
    list(
      prevalencia_anual         = prevalencia_anual,
      prevalencia_regional_taxa = prevalencia_regional_taxa,
      prevalencia_rural         = prevalencia_rural,
      taxa_participacao         = taxa_participacao,
      renda_sm_categ            = renda_sm_categ,
      razao_renda_CD            = razao_renda_CD,
      neet_proxy                = neet_proxy,
      taxa_racial               = taxa_racial
    ),
    parte5_cache, compress = "gz"   # gz: muito mais rápido que xz para tabelas pequenas
  )
  message("Cache da Parte 5 salvo em: ", parte5_cache)
}

message("Análises econômicas (5.1–5.13) concluídas.")

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
