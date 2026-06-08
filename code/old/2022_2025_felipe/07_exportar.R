# =============================================================================
# 07_exportar.R — Exportação de todas as tabelas para Excel
# =============================================================================
# Depende de: todos os scripts de análise (03 a 06)
#
# Produz: descriptive_stats_all.xlsx em OUT_DIR
# =============================================================================

source(here::here("00_setup.R"))

output_path <- file.path(OUT_DIR, "descriptive_stats_all.xlsx")

write_xlsx(
  list(
    # ── Registro Civil ──────────────────────────────────────────────────────
    "RC_annual"            = rc_annual,
    "RC_composition"       = rc_comp,
    "RC_age_woman"         = rc_age_woman,
    "RC_pre_post_reform"   = rc_pre_post,
    "RC_rate_per10k"       = rc_rate %||% data.frame(note = "pop file not found"),
    # ── PNADC: perfis e contagens ────────────────────────────────────────────
    "PNADC_profile_pooled" = as.data.frame(profile_pooled),
    "PNADC_counts_annual"  = as.data.frame(early_annual),
    "PNADC_profile_annual" = as.data.frame(profile_annual),
    # ── Sub-registro ─────────────────────────────────────────────────────────
    "Underreporting"       = underreporting,
    "Underreporting_CI"    = underreporting_ci,
    # ── Análises pré/pós reforma ─────────────────────────────────────────────
    "NEW_pre_post_PNADC"   = pnadc_pre_post,
    "NEW_age_gap_dist"     = as.data.frame(age_gap_dist),
    "NEW_hourly_income"    = as.data.frame(profile_hourly),
    # ── Análises econômicas: taxas ────────────────────────────────────────────
    "ECON_prevalencia_anual"    = prevalencia_anual,
    "ECON_prevalencia_regiao"   = as.data.frame(prevalencia_regional_taxa),
    "ECON_prevalencia_rural"    = as.data.frame(prevalencia_rural),
    "ECON_participacao_laboral" = as.data.frame(taxa_participacao),
    "ECON_renda_SM"             = as.data.frame(renda_sm_categ),
    "ECON_razao_renda_CD"       = razao_renda_CD,
    "ECON_neet"                 = as.data.frame(neet_proxy),
    "ECON_racial"               = as.data.frame(taxa_racial),
    # ── Mercado de trabalho ───────────────────────────────────────────────────
    "LM1_margens"               = as.data.frame(lm1_margens),
    "LM1_horas_ocupados"        = as.data.frame(lm1_horas_ocupados),
    "LM2_informalidade"         = as.data.frame(lm2_informalidade),
    "LM3_composicao_ocup"       = as.data.frame(lm3_ocupacao),
    "LM4_gender_wage_gap"       = lm4_wage_gap,
    "LM5_dupla_jornada"         = as.data.frame(lm5_dupla_jornada),
    "LM6_probit_coef"           = probit_comp,
    "LM7_renda_hora_ocup"       = as.data.frame(lm7_rend_hora_ocup),
    # ── Capital humano (autocontido, 2º trimestre) ───────────────────────────
    "EDUC_8_1a_freq_serie"      = as.data.frame(educ_8_1a),
    "EDUC_8_1b_motivo_aband"    = as.data.frame(educ_8_1b),
    "EDUC_8_1c_anos_sexo"       = as.data.frame(educ_8_1c),
    "EDUC_8_1d_defasagem"       = as.data.frame(educ_8_1d),
    "EDUC_8_1e_rede_ensino"     = as.data.frame(educ_8_1e),
    "EDUC_8_1f_pre_pos_2019"    = as.data.frame(educ_8_1f)
  ),
  path = output_path
)

message(sprintf("Todas as tabelas exportadas para: %s", output_path))
message("07_exportar.R concluído.")
