# =============================================================================
# 06_analises_educacao.R — Análises educacionais (módulo 2º trimestre)
# =============================================================================
# Depende de: 02_preparacao.R (educ_srvyr)
#
# Produz (tabelas):
#   educ_8_1a  — frequência escolar por grupo × ano
#   educ_8_1b  — motivo de abandono escolar (pooled)
#   educ_8_1c  — anos de estudo por grupo × sexo
#   educ_8_1d  — defasagem idade-série por grupo × ano
#   educ_8_1e  — rede de ensino (pública vs privada)
#   educ_8_1f  — gap pré/pós 2019
#
# Figuras salvas em OUT_DIR:
#   figNEW_educ_freq_serie.png
#   figNEW_educ_motivo_abandono.png
#   figNEW_educ_defasagem_serie.png
# =============================================================================

source(here::here("00_setup.R"))

# ── Helper: extrai dados + pesos do survey para cálculo robusto ──────────────
# Todas as análises de educação usam subgrupos pequenos (esp. Cônjuge < 18
# por ano), o que causa "índice fora dos limites" no srvyr ao tentar calcular
# variância. Solução uniforme: weighted.mean() direto com os pesos do survey.
# Isso dá médias ponderadas corretas; os IC são omitidos para estes subgrupos.
educ_vars <- educ_srvyr$variables |>
  mutate(peso = weights(educ_srvyr))

wt_mean <- function(x, w) {
  ok <- !is.na(x) & !is.na(w)
  if (sum(ok) == 0) return(NA_real_)
  sum(x[ok] * w[ok]) / sum(w[ok])
}

# ── 8.1a: Frequência escolar por categoria × ano ─────────────────────────────
message("  8.1a frequencia_escolar_serie...")
educ_8_1a <- educ_vars |>
  filter(!is.na(freq_esc_bin), !is.na(grupo_educ)) |>
  group_by(Ano, grupo_educ) |>
  summarise(
    taxa_freq = wt_mean(freq_esc_bin, peso),
    n_obs     = n(),
    .groups   = "drop"
  )

# ── 8.1b: Motivo de abandono escolar (pooled) ────────────────────────────────
# Usa nao_freq_bin (não frequenta) em vez de freq_esc_bin == 0, pois V3002
# pode ter label diferente de "Sim"/"Não" dependendo do ano.
message("  8.1b motivo_abandono_pooled...")
educ_8_1b <- educ_vars |>
  mutate(
    nao_freq_bin = as.integer(
      !is.na(freq_escola) &
      !str_detect(as.character(freq_escola), "(?i)^sim$|^yes$")
    )
  ) |>
  filter(nao_freq_bin == 1L, !is.na(motivo_simpl), !is.na(grupo_educ)) |>
  group_by(grupo_educ, motivo_simpl) |>
  summarise(n_pond = sum(peso, na.rm = TRUE), .groups = "drop") |>
  group_by(grupo_educ) |>
  mutate(prop = n_pond / sum(n_pond)) |>
  ungroup()

# ── 8.1c: Anos de estudo por categoria × sexo (pooled) ───────────────────────
message("  8.1c anos_estudo_sexo...")
educ_8_1c <- educ_vars |>
  filter(!is.na(anos_estudo), !is.na(grupo_educ)) |>
  mutate(sexo_label = if_else(
    as.character(sexo) %in% c("Mulher","Feminino"), "Mulher", "Homem")) |>
  group_by(grupo_educ, sexo_label) |>
  summarise(
    media_anos = wt_mean(anos_estudo, peso),
    n_obs      = n(),
    .groups    = "drop"
  )

# ── 8.1d: Nível de ensino frequentado por categoria × ano ────────────────────
# V3006 (série/ano específico) não foi baixada neste ciclo — defasagem exata
# indisponível. Substituto: distribuição do nível de ensino (fundamental vs
# médio vs EJA) entre quem frequenta escola, que também evidencia atraso.
# EJA = Educação de Jovens e Adultos, concentra alunos com trajetória irregular.
message("  8.1d nivel_ensino_frequentado...")
educ_8_1d <- educ_vars |>
  filter(freq_esc_bin == 1L, !is.na(grupo_educ), !is.na(curso_freq)) |>
  mutate(
    nivel_simpl = case_when(
      str_detect(as.character(curso_freq), "(?i)EJA|supletivo|jovens e adultos") ~ "EJA/Supletivo",
      str_detect(as.character(curso_freq), "(?i)fundamental") ~ "Fundamental regular",
      str_detect(as.character(curso_freq), "(?i)médio|medio")  ~ "Médio regular",
      str_detect(as.character(curso_freq), "(?i)superior")     ~ "Superior",
      TRUE ~ "Outro"
    )
  ) |>
  group_by(Ano, grupo_educ, nivel_simpl) |>
  summarise(n_pond = sum(peso, na.rm = TRUE), .groups = "drop") |>
  group_by(Ano, grupo_educ) |>
  mutate(prop = n_pond / sum(n_pond)) |>
  ungroup()

# ── 8.1e: Tipo de fundamental (8 ou 9 anos) por categoria ────────────────────
# V3005 (rede pública/privada) não foi baixada neste ciclo.
# V3004 disponível = duração do fundamental (8 ou 9 anos), proxy de transição
# curricular pós-2006 (Lei 11.274). Cônjuges < 18 mais velhos podem ainda
# estar no sistema de 8 anos — indicador indireto de trajetória atrasada.
message("  8.1e tipo_fundamental (proxy V3004)...")
educ_8_1e <- educ_vars |>
  filter(freq_esc_bin == 1L,
         !is.na(rede_ensino),      # rede_ensino aqui = V3004 = "8 anos"/"9 anos"
         !is.na(grupo_educ),
         str_detect(as.character(rede_ensino), "anos")) |>
  mutate(fund_9anos_bin = as.integer(as.character(rede_ensino) == "9 anos")) |>
  group_by(grupo_educ) |>
  summarise(
    taxa_9anos = wt_mean(fund_9anos_bin, peso),
    n_obs      = n(),
    .groups    = "drop"
  )

# ── 8.1f: Gap pré/pós 2019 ───────────────────────────────────────────────────
# taxa_defas usa o mesmo proxy de 8.1d (nível × idade) — defasagem_bin é NA.
message("  8.1f pre_pos_2019...")
educ_8_1f <- educ_vars |>
  filter(!is.na(grupo_educ)) |>
  mutate(
    periodo  = if_else(as.integer(as.character(Ano)) <= 2019, "Pré-2019", "Pós-2019"),
    eja_bin  = as.integer(str_detect(as.character(curso_freq),
                                     "(?i)EJA|supletivo|jovens e adultos"))
  ) |>
  group_by(periodo, grupo_educ) |>
  summarise(
    taxa_freq = wt_mean(freq_esc_bin, peso),
    taxa_eja  = wt_mean(eja_bin,      peso),
    .groups = "drop"
  )

message("Análises 8.1a–8.1f concluídas.")

# =============================================================================
# FIGURAS EDUCACIONAIS
# =============================================================================

cores_grupo_educ <- c("Cônjuge < 18"        = "#C0392B",
                      "Filho/parente 14–17" = "#2C3E50")

# Figura A — Frequência escolar ao longo do tempo
# (sem ribbon de IC — médias ponderadas diretas, sem estimação de variância)
fig_educ_A <- educ_8_1a |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  ggplot(aes(x = Ano, y = taxa_freq, color = grupo_educ,
             group = grupo_educ)) +
  geom_line(linewidth = 1) + geom_point(size = 2.5) +
  geom_vline(xintercept = 2019, linetype = "dashed", color = "grey40") +
  scale_color_manual(values = cores_grupo_educ, name = NULL) +
  scale_y_continuous(labels = label_percent(accuracy = 1), limits = c(0, 1)) +
  scale_x_continuous(breaks = anos_pnadc) +
  labs(
    title    = "EDUC A: Frequência Escolar — Cônjuges < 18 vs Filhos/Parentes 14–17",
    subtitle = "PNADC 2º trimestre. Linha vertical = 2019. Médias ponderadas.",
    x = NULL, y = "Taxa de frequência escolar (%)",
    caption  = "Fonte: PNADC 2º trimestre (V3002). Médias ponderadas pelo peso amostral."
  ) + theme_paper

ggsave(file.path(OUT_DIR, "figNEW_educ_freq_serie.png"), fig_educ_A,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# Figura B — Motivo de abandono escolar (barras horizontais empilhadas)
fig_educ_B <- educ_8_1b |>
  mutate(motivo_simpl = factor(motivo_simpl, levels = c(
    "Trabalho","Cuidado doméstico / filhos","Gravidez",
    "Falta de interesse","Concluiu os estudos","Acesso / distância","Outro"
  ))) |>
  ggplot(aes(x = grupo_educ, y = prop, fill = motivo_simpl)) +
  geom_col(position = "fill", width = 0.6) +
  coord_flip() +
  scale_fill_brewer(palette = "Set2", name = "Motivo de não frequentar") +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(
    title    = "EDUC B: Motivo de Abandono Escolar por Categoria (pooled)",
    subtitle = "Distribuição condicional ao não-frequentamento da escola",
    x = NULL, y = "Proporção (%)",
    caption  = "Fonte: PNADC 2º trimestre (V3007). Elaboração dos autores."
  ) + theme_paper + theme(legend.position = "right")

ggsave(file.path(OUT_DIR, "figNEW_educ_motivo_abandono.png"), fig_educ_B,
       width = 22, height = 12, units = "cm", dpi = 300, bg = "white")

# Figura C — Distribuição do nível de ensino frequentado (pooled)
# educ_8_1d agora traz nivel_simpl × prop (V3006 não disponível neste ciclo)
fig_educ_C <- educ_8_1d |>
  group_by(grupo_educ, nivel_simpl) |>
  summarise(n_pond = sum(n_pond, na.rm = TRUE), .groups = "drop") |>
  group_by(grupo_educ) |>
  mutate(prop = n_pond / sum(n_pond),
         nivel_simpl = factor(nivel_simpl,
           levels = c("Fundamental regular","EJA/Supletivo",
                      "Médio regular","Superior","Outro"))) |>
  ungroup() |>
  ggplot(aes(x = grupo_educ, y = prop, fill = nivel_simpl)) +
  geom_col(position = "fill", width = 0.6) +
  coord_flip() +
  scale_fill_brewer(palette = "Set2", name = "Nível de ensino") +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(
    title    = "EDUC C: Nível de Ensino Frequentado por Categoria",
    subtitle = "Entre adolescentes que frequentam escola (pooled 2012–2023)",
    x = NULL, y = "Proporção (%)",
    caption  = "Fonte: PNADC 2º trimestre (V3003). Médias ponderadas pelo peso amostral."
  ) + theme_paper + theme(legend.position = "right")

ggsave(file.path(OUT_DIR, "figNEW_educ_defasagem_serie.png"), fig_educ_C,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

message("Figuras EDUC A/B/C salvas em: ", OUT_DIR)
message("06_analises_educacao.R concluído.")
