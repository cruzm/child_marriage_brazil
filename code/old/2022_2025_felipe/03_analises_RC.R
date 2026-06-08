# =============================================================================
# 03_analises_RC.R — Análises do Registro Civil
# =============================================================================
# Depende de: 01_importacao.R (rc_raw, rc_years, idade_menor_m, cols_h_*)
#
# Produz:
#   rc_annual    — totais anuais por região
#   rc_comp      — composição dos casamentos (ambos menores / só mulher / etc.)
#   rc_age_woman — distribuição por faixa etária da mulher
#   rc_pre_post  — comparação pré/pós reforma de 2019
#   rc_rate      — taxa por 10.000 menores (requer pop_menores.xlsx)
#   rc_flow      — fluxo anual agregado (usado em 04_analises_PNADC.R)
#
# Figuras salvas em OUT_DIR:
#   fig2_child_marriages_RC.png
# =============================================================================

source(here::here("00_setup.R"))

# ── 1.1  Totais anuais por região ─────────────────────────────────────────────
rc_annual <- rc_raw |>
  group_by(ano, regiao) |>
  summarise(
    total_geral     = sum(n_total_row,                na.rm = TRUE),
    total_inf       = sum(n_total_row * is_minor_w,   na.rm = TRUE),
    total_h_inf     = sum(n_h_minor,                  na.rm = TRUE),
    total_ambos_inf = sum(n_h_minor   * is_minor_w,   na.rm = TRUE),
    .groups = "drop"
  )

# ── 1.2  Composição: ambos menores / só mulher menor / só homem menor ─────────
rc_comp <- rc_raw |>
  group_by(ano) |>
  summarise(
    only_woman_minor = sum(n_h_adult * is_minor_w,  na.rm = TRUE),
    only_man_minor   = sum(n_h_minor * !is_minor_w, na.rm = TRUE),
    both_minor       = sum(n_h_minor * is_minor_w,  na.rm = TRUE),
    total_geral      = sum(n_total_row,              na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    total_inf      = only_woman_minor + only_man_minor + both_minor,
    pct_only_woman = only_woman_minor / total_inf,
    pct_only_man   = only_man_minor   / total_inf,
    pct_both       = both_minor       / total_inf
  )

# ── 1.3  Distribuição por faixa etária da mulher menor ────────────────────────
rc_age_woman <- rc_raw |>
  filter(is_minor_w) |>
  group_by(ano, idade_m) |>
  summarise(
    n_total   = sum(n_total_row, na.rm = TRUE),
    n_h_adult = sum(n_h_adult,   na.rm = TRUE),
    .groups = "drop"
  ) |>
  group_by(ano) |>
  mutate(pct = n_total / sum(n_total)) |>
  ungroup()

# ── 1.4  Comparação pré/pós reforma de 2019 ───────────────────────────────────
rc_pre_post <- rc_annual |>
  group_by(ano) |>
  summarise(total_inf = sum(total_inf), total_geral = sum(total_geral),
            .groups = "drop") |>
  mutate(
    pct_inf = total_inf / total_geral,
    periodo = if_else(ano < 2019,
                      "Pre-reform (2003–2018)", "Post-reform (2019–2022)")
  ) |>
  group_by(periodo) |>
  summarise(
    media_pct_inf = mean(pct_inf),
    sd_pct_inf    = sd(pct_inf),
    media_n_inf   = mean(total_inf),
    .groups = "drop"
  )

# ── 1.5  Taxa por 10.000 menores de 18 (requer pop_menores.xlsx) ──────────────
pop_file <- file.path(RC_DIR, "pop_menores.xlsx")
if (file.exists(pop_file)) {
  pop_menores <- read_xlsx(pop_file)
  rc_rate <- rc_annual |>
    group_by(ano) |>
    summarise(total_inf = sum(total_inf), .groups = "drop") |>
    left_join(pop_menores, by = "ano") |>
    mutate(taxa_por_10k = total_inf / pop_menores * 10000)
} else {
  message("pop_menores.xlsx não encontrado — rc_rate será NULL.")
  rc_rate <- NULL
}

# ── Fluxo anual agregado (usado na comparação RC × PNADC em 04_analises_PNADC.R)
rc_flow <- rc_annual |>
  group_by(ano) |>
  summarise(flow = sum(total_inf), .groups = "drop")

message(sprintf("rc_annual: %d linhas | rc_flow: %d anos", nrow(rc_annual), nrow(rc_flow)))

# =============================================================================
# FIGURAS DO REGISTRO CIVIL
# =============================================================================

# Figura 2: Evolução dos casamentos infantis formais (RC)
p1 <- rc_flow |>
  ggplot(aes(x = ano, y = flow)) +
  geom_line(color = "#2E4053", linewidth = 1) +
  geom_point(color = "#2E4053", size = 2) +
  geom_vline(xintercept = 2019, linetype = "dashed", color = "red", alpha = .7) +
  annotate("text", x = 2019.3, y = max(rc_flow$flow) * .85,
           label = "Lei 13.811/2019", hjust = 0, size = 3.2, color = "red") +
  scale_x_continuous(breaks = seq(2003, 2022, 2)) +
  scale_y_continuous(labels = label_number(big.mark = ",")) +
  labs(
    title    = "Figure 2: Child Marriages in Brazil, 2003–2022",
    subtitle = "Formally registered unions with at least one spouse under 18",
    x = NULL, y = "Number of marriages",
    caption  = "Source: IBGE Civil Registry Statistics (Registro Civil). Authors' elaboration."
  ) +
  theme_paper

ggsave(file.path(OUT_DIR, "fig2_child_marriages_RC.png"), p1,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")

message("Figura RC salva.")
message("03_analises_RC.R concluído.")
