# =============================================================================
# 05_analises_mercado.R — Análises de mercado de trabalho
# =============================================================================
# Depende de: 02_preparacao.R (pnadc_lm_srvyr)
#
# Produz (tabelas):
#   lm1_margens, lm1_horas_ocupados
#   lm2_informalidade
#   lm3_ocupacao
#   lm4_wage_gap
#   lm5_dupla_jornada
#   probit_comp    (LM6 — coeficientes do probit)
#   lm7_rend_hora_ocup
#
# Figuras salvas em OUT_DIR:
#   lm1_participacao.png
#   lm2_informalidade.png
#   lm3_composicao_ocupacional.png
#   lm4_gender_wage_gap.png
#   lm5_dupla_jornada.png
#   lm6_probit_participacao.png
#   lm7_renda_hora_ocupacao.png
# =============================================================================

source(here::here("00_setup.R"))

# =============================================================================
# CACHE — LM1–LM7
# =============================================================================
# Para regenerar: file.remove(file.path(CACHE_DIR, "lm_analises_cache.rds"))

lm_cache_path <- file.path(CACHE_DIR, "lm_analises_cache.rds")

if (file.exists(lm_cache_path)) {
  message("Carregando análises LM do cache...")
  lm_cache <- readRDS(lm_cache_path)
  lm1_margens        <- lm_cache$lm1_margens
  lm1_horas_ocupados <- lm_cache$lm1_horas_ocupados
  lm2_informalidade  <- lm_cache$lm2_informalidade
  lm3_ocupacao       <- lm_cache$lm3_ocupacao
  lm4_wage_gap       <- lm_cache$lm4_wage_gap
  lm5_dupla_jornada  <- lm_cache$lm5_dupla_jornada
  probit_comp        <- lm_cache$probit_comp
  lm7_rend_hora_ocup <- lm_cache$lm7_rend_hora_ocup
  rm(lm_cache)
  message("Cache LM carregado.")

} else {
  # ── Helper: extrai dados + pesos para cálculo direto (sem srvyr) ─────────
  # survey_mean em pnadc_lm_srvyr com 160+ grupos trava por RAM e tempo.
  # weighted.mean() direto dá médias ponderadas idênticas sem overhead de
  # estimação de variância — correto para mostrar tendências e comparações.
  lm_vars <- pnadc_lm_srvyr$variables |>
    mutate(peso = weights(pnadc_lm_srvyr))

  wt_mean <- function(x, w) {
    ok <- !is.na(x) & !is.na(w)
    if (sum(ok) == 0) return(NA_real_)
    sum(x[ok] * w[ok]) / sum(w[ok])
  }

  # ── LM1: Margens extensiva e intensiva ─────────────────────────────────────
  message("  LM1: margens extensiva e intensiva...")
  lm1_margens <- lm_vars |>
    filter(!is.na(categ_domic)) |>
    mutate(sexo_label = if_else(sexo_bin == 1L, "Mulher", "Homem")) |>
    group_by(Ano, categ_domic, condno_domic, sexo_label) |>
    summarise(
      taxa_participacao = wt_mean(trab_remun_bin,          peso),
      horas_media_total = wt_mean(horas_trabalhadas_seman, peso),
      n_obs             = n(),
      .groups = "drop"
    )

  lm1_horas_ocupados <- lm_vars |>
    filter(!is.na(categ_domic),
           as.character(trab_remun) == "Sim",
           !is.na(horas_trabalhadas_seman)) |>
    mutate(sexo_label = if_else(sexo_bin == 1L, "Mulher", "Homem")) |>
    group_by(Ano, categ_domic, condno_domic, sexo_label) |>
    summarise(
      horas_media_ocup = wt_mean(horas_trabalhadas_seman, peso),
      n_obs            = n(),
      .groups = "drop"
    )
  message("  LM1 concluído.")

  # ── LM2: Taxa de informalidade ─────────────────────────────────────────────
  message("  LM2: informalidade...")
  lm2_informalidade <- lm_vars |>
    filter(!is.na(categ_domic),
           as.character(trab_remun) == "Sim",
           !is.na(formal_bin)) |>
    mutate(
      sexo_label    = if_else(sexo_bin == 1L, "Mulher", "Homem"),
      informal_bin  = 1L - formal_bin
    ) |>
    group_by(Ano, categ_domic, condno_domic, sexo_label) |>
    summarise(
      taxa_formal   = wt_mean(formal_bin,   peso),
      taxa_informal = wt_mean(informal_bin, peso),
      n_obs         = n(),
      .groups = "drop"
    )
  message("  LM2 concluído.")

  # ── LM3: Composição ocupacional ────────────────────────────────────────────
  message("  LM3: composicao_ocupacional...")
  lm3_ocupacao <- lm_vars |>
    filter(!is.na(categ_domic),
           as.character(trab_remun) == "Sim",
           !is.na(pos_simples),
           condno_domic == "Cônjuge ou companheiro(a) de sexo diferente",
           categ_domic %in% c("C","D")) |>
    group_by(Ano, categ_domic, pos_simples) |>
    summarise(n_pond = sum(peso, na.rm = TRUE), .groups = "drop") |>
    group_by(Ano, categ_domic) |>
    mutate(prop = n_pond / sum(n_pond)) |>
    ungroup()
  message("  LM3 concluído.")

  # ── LM4: Diferencial de salários por gênero ───────────────────────────────
  message("  LM4: gender wage gap...")
  lm4_wage_gap <- lm_vars |>
    filter(!is.na(categ_domic),
           as.character(trab_remun) == "Sim",
           !is.na(rend), rend > 0) |>
    mutate(sexo_label = if_else(sexo_bin == 1L, "Mulher", "Homem")) |>
    group_by(Ano, categ_domic, sexo_label) |>
    summarise(renda_media = wt_mean(rend, peso), .groups = "drop") |>
    pivot_wider(names_from = sexo_label, values_from = renda_media,
                names_prefix = "renda_media_") |>
    mutate(
      razao_H_M = renda_media_Homem / renda_media_Mulher,
      gap_pct   = (renda_media_Homem - renda_media_Mulher) / renda_media_Homem * 100
    )
  message("  LM4 concluído.")

  # ── LM5: Dupla jornada ────────────────────────────────────────────────────
  message("  LM5: dupla jornada...")
  lm5_dupla_jornada <- lm_vars |>
    filter(!is.na(categ_domic), sexo_bin == 1L,
           condno_domic == "Cônjuge ou companheiro(a) de sexo diferente") |>
    mutate(
      dupla_bin      = as.integer(trab_remun_bin == 1L & cuidado_trab_bin == 1L),
      so_cuidado_bin = as.integer(trab_remun_bin == 0L & cuidado_trab_bin == 1L)
    ) |>
    group_by(Ano, categ_domic) |>
    summarise(
      taxa_dupla_jornada = wt_mean(dupla_bin,        peso),
      taxa_so_cuidado    = wt_mean(so_cuidado_bin,   peso),
      taxa_cuidado_total = wt_mean(cuidado_trab_bin, peso),
      n_obs              = n(),
      .groups = "drop"
    )
  message("  LM5 concluído.")

  # ── LM6: Probit — mantém svyglm (precisa do design para consistência) ─────
  message("  LM6: probit participacao C vs D...")
  design_probit_C <- subset(pnadc_lm_srvyr,
    categ_domic == "C" & sexo_bin == 1L &
    condno_domic == "Cônjuge ou companheiro(a) de sexo diferente" &
    !is.na(idade) & !is.na(parda_preta_bin))

  design_probit_D <- subset(pnadc_lm_srvyr,
    categ_domic == "D" & sexo_bin == 1L &
    condno_domic == "Cônjuge ou companheiro(a) de sexo diferente" &
    !is.na(idade) & !is.na(parda_preta_bin))

  probit_C <- svyglm(trab_remun_bin ~ idade + I(idade^2) + parda_preta_bin,
                     design = design_probit_C, family = quasibinomial())
  probit_D <- svyglm(trab_remun_bin ~ idade + I(idade^2) + parda_preta_bin,
                     design = design_probit_D, family = quasibinomial())

  probit_comp <- bind_rows(
    broom::tidy(probit_C) |> mutate(categ = "C — cônjuge < 18"),
    broom::tidy(probit_D) |> mutate(categ = "D — controle adulto")
  ) |>
    select(categ, term, estimate, std.error, p.value) |>
    mutate(across(where(is.numeric), ~ round(., 4)))
  message("  LM6 concluído.")
  print(probit_comp)

  # ── LM7: Renda por hora por tipo de ocupação ─────────────────────────────
  message("  LM7: renda por hora por ocupação...")
  lm7_rend_hora_ocup <- lm_vars |>
    filter(!is.na(categ_domic), categ_domic %in% c("C","D"),
           as.character(trab_remun) == "Sim",
           !is.na(pos_simples), !is.na(rend), rend > 0,
           !is.na(horas_trabalhadas_seman), horas_trabalhadas_seman > 0) |>
    mutate(rend_hora = rend / (horas_trabalhadas_seman * 4.33)) |>
    group_by(categ_domic, pos_simples) |>
    summarise(
      media_rend_hora = wt_mean(rend_hora, peso),
      n_obs           = n(),
      .groups = "drop"
    )
  message("  LM7 concluído.")

  # Salva cache
  saveRDS(
    list(lm1_margens        = lm1_margens,
         lm1_horas_ocupados = lm1_horas_ocupados,
         lm2_informalidade  = lm2_informalidade,
         lm3_ocupacao       = lm3_ocupacao,
         lm4_wage_gap       = lm4_wage_gap,
         lm5_dupla_jornada  = lm5_dupla_jornada,
         probit_comp        = probit_comp,
         lm7_rend_hora_ocup = lm7_rend_hora_ocup),
    lm_cache_path, compress = "gz"
  )
  message("Cache LM salvo em: ", lm_cache_path)
  rm(lm_vars); gc()
}

message("Análises de mercado de trabalho concluídas.")

# =============================================================================
# FIGURAS DE MERCADO DE TRABALHO
# =============================================================================

# LM Plot 1: Participação laboral — cônjuges mulheres C vs D
lm_p1 <- lm1_margens |>
  filter(condno_domic == "Cônjuge ou companheiro(a) de sexo diferente",
         categ_domic %in% c("C","D"), sexo_label == "Mulher") |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  ggplot(aes(x = Ano, y = taxa_participacao,
             color = categ_domic, group = categ_domic)) +
  geom_line(linewidth = 1) + geom_point(size = 2.5) +
  scale_color_manual(values = cores_categ,
    labels = c("C"="Cat. C (cônjuge < 18)","D"="Cat. D (controle adulto)"), name = NULL) +
  scale_x_continuous(breaks = anos_pnadc) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(title   = "LM 1: Taxa de Participação Laboral — Cônjuges Mulheres",
       subtitle = "Margem extensiva: % com trabalho remunerado, cat. C vs D",
       x = NULL, y = "Taxa de participação (%)",
       caption = "Fonte: PNADC. Médias ponderadas. Elaboração dos autores.") +
  theme_paper


ggsave(file.path(OUT_DIR, "lm1_participacao.png"), lm_p1,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# LM Plot 2: Taxa de informalidade — cônjuges mulheres C vs D
lm_p2 <- lm2_informalidade |>
  filter(condno_domic == "Cônjuge ou companheiro(a) de sexo diferente",
         categ_domic %in% c("C","D"), sexo_label == "Mulher") |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  ggplot(aes(x = Ano, y = taxa_informal,
             color = categ_domic, group = categ_domic)) +
  geom_line(linewidth = 1) + geom_point(size = 2.5) +
  scale_color_manual(values = cores_categ,
    labels = c("C"="Cat. C (cônjuge < 18)","D"="Cat. D (controle adulto)"), name = NULL) +
  scale_x_continuous(breaks = anos_pnadc) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(title   = "LM 2: Taxa de Informalidade — Cônjuges Mulheres",
       subtitle = "% sem contribuição ao INSS entre ocupadas: união precoce (C) vs controle (D)",
       x = NULL, y = "Taxa de informalidade (%)",
       caption = "Fonte: PNADC (V4029). Médias ponderadas. Elaboração dos autores.") +
  theme_paper

ggsave(file.path(OUT_DIR, "lm2_informalidade.png"), lm_p2,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# LM Plot 3: Composição ocupacional — stacked bar C vs D (pooled)
lm_p3 <- lm3_ocupacao |>
  filter(!is.na(pos_simples)) |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  group_by(categ_domic, pos_simples) |>
  summarise(prop = mean(prop, na.rm = TRUE), .groups = "drop") |>
  mutate(
    categ_label = if_else(categ_domic == "C",
                          "Cat. C (cônjuge < 18)", "Cat. D (controle adulto)"),
    pos_simples = factor(pos_simples,
      levels = c("Setor público","Privado c/ carteira","Privado s/ carteira",
                 "Doméstico","Conta própria","Empregador","Outro"))
  ) |>
  ggplot(aes(x = categ_label, y = prop, fill = pos_simples)) +
  geom_col(position = "fill", width = 0.6) +
  scale_fill_brewer(palette = "Set2", name = "Posição na ocupação") +
  scale_y_continuous(labels = label_percent()) +
  labs(title   = "LM 3: Composição Ocupacional — C vs D (pooled 2012–2023)",
       subtitle = "Distribuição por tipo de vínculo empregatício entre cônjuges ocupadas",
       x = NULL, y = "Proporção (%)",
       caption = "Fonte: PNADC. Elaboração dos autores.") +
  theme_paper + theme(legend.position = "right")

ggsave(file.path(OUT_DIR, "lm3_composicao_ocupacional.png"), lm_p3,
       width = 20, height = 13, units = "cm", dpi = 300, bg = "white")

# LM Plot 4: Gender wage gap por categoria ao longo do tempo
lm_p4 <- lm4_wage_gap |>
  filter(categ_domic %in% c("C","D")) |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  ggplot(aes(x = Ano, y = razao_H_M,
             color = categ_domic, group = categ_domic)) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "gray50") +
  annotate("text", x = min(anos_pnadc), y = 1.02,
           label = "Sem diferencial", hjust = 0, size = 3, color = "gray40") +
  geom_line(linewidth = 1) + geom_point(size = 2.5) +
  scale_color_manual(values = cores_categ,
    labels = c("C"="Cat. C (cônjuge < 18)","D"="Cat. D (controle adulto)"), name = NULL) +
  scale_x_continuous(breaks = anos_pnadc) +
  scale_y_continuous(labels = label_number(accuracy = 0.01)) +
  labs(title   = "LM 4: Diferencial de Salários por Gênero (Homem/Mulher)",
       subtitle = "Razão renda homem / renda mulher dentro de cada categoria. > 1 = homem ganha mais.",
       x = NULL, y = "Razão H/M",
       caption = "Fonte: PNADC. Elaboração dos autores.") +
  theme_paper

ggsave(file.path(OUT_DIR, "lm4_gender_wage_gap.png"), lm_p4,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# LM Plot 5: Dupla jornada — cônjuges mulheres C vs D
lm_p5 <- lm5_dupla_jornada |>
  filter(categ_domic %in% c("C","D")) |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  pivot_longer(c(taxa_dupla_jornada, taxa_so_cuidado),
               names_to = "tipo", values_to = "taxa") |>
  mutate(tipo = recode(tipo,
    "taxa_dupla_jornada" = "Trabalha fora + cuidado doméstico",
    "taxa_so_cuidado"    = "Só cuidado doméstico (não trabalha fora)"
  )) |>
  ggplot(aes(x = Ano, y = taxa, color = categ_domic,
             linetype = tipo, group = interaction(categ_domic, tipo))) +
  geom_line(linewidth = 0.9) + geom_point(size = 2) +
  scale_color_manual(values = cores_categ,
    labels = c("C"="Cat. C (cônjuge < 18)","D"="Cat. D (controle adulto)"),
    name = "Categoria") +
  scale_linetype_manual(
    values = c("Trabalha fora + cuidado doméstico"        = "solid",
               "Só cuidado doméstico (não trabalha fora)" = "dashed"),
    name = NULL) +
  scale_x_continuous(breaks = anos_pnadc) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(title   = "LM 5: Dupla Jornada — Cônjuges Mulheres",
       subtitle = "% que trabalha fora E faz cuidado doméstico vs. só cuidado doméstico",
       x = NULL, y = "Taxa (%)",
       caption = "Fonte: PNADC. Elaboração dos autores.") +
  theme_paper

ggsave(file.path(OUT_DIR, "lm5_dupla_jornada.png"), lm_p5,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# LM Plot 6: Coeficientes do probit — C vs D
lm_p6 <- probit_comp |>
  filter(term != "(Intercept)") |>
  mutate(
    term = recode(term,
      "idade"           = "Idade",
      "I(idade^2)"      = "Idade²",
      "parda_preta_bin" = "Parda/Preta"
    ),
    ci_low = estimate - 1.96 * std.error,
    ci_upp = estimate + 1.96 * std.error
  ) |>
  ggplot(aes(x = term, y = estimate, color = categ, group = categ)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "gray50") +
  geom_errorbar(aes(ymin = ci_low, ymax = ci_upp),
                width = 0.15, position = position_dodge(0.4)) +
  geom_point(size = 3.5, position = position_dodge(0.4)) +
  scale_color_manual(
    values = c("C — cônjuge < 18" = "#C0392B", "D — controle adulto" = "#2980B9"),
    name = NULL) +
  labs(title   = "LM 6: Probit — Determinantes da Participação Laboral (C vs D)",
       subtitle = "Coeficientes de P(trabalha) ~ idade + raça | cônjuges mulheres",
       x = NULL, y = "Coeficiente (log-odds)",
       caption = "Fonte: PNADC. svyglm(quasibinomial). IC 95%. Elaboração dos autores.") +
  theme_paper + theme(legend.position = "right")

ggsave(file.path(OUT_DIR, "lm6_probit_participacao.png"), lm_p6,
       width = 20, height = 13, units = "cm", dpi = 300, bg = "white")

# LM Plot 7: Renda por hora por tipo de ocupação — C vs D
lm_p7 <- lm7_rend_hora_ocup |>
  filter(!is.na(pos_simples)) |>
  mutate(
    categ_label = if_else(categ_domic == "C",
                          "Cat. C (cônjuge < 18)", "Cat. D (controle adulto)"),
    pos_simples = factor(pos_simples,
      levels = c("Setor público","Privado c/ carteira","Conta própria",
                 "Privado s/ carteira","Doméstico","Empregador","Outro"))
  ) |>
  ggplot(aes(x = reorder(pos_simples, media_rend_hora),
             y = media_rend_hora, fill = categ_domic)) +
  geom_col(position = position_dodge(0.7), width = 0.6) +
  coord_flip() +
  scale_fill_manual(values = cores_categ,
    labels = c("C"="Cat. C (cônjuge < 18)","D"="Cat. D (controle adulto)"), name = NULL) +
  scale_y_continuous(labels = label_number(big.mark=".", decimal.mark=",", prefix="R$ ")) +
  labs(title   = "LM 7: Renda por Hora por Tipo de Ocupação — C vs D",
       subtitle = "Produtividade horária (R$/hora) por posição ocupacional, pooled 2012–2023",
       x = NULL, y = "Renda por hora (R$)",
       caption = "Fonte: PNADC. IC 95%. Elaboração dos autores.") +
  theme_paper + theme(legend.position = "right")

ggsave(file.path(OUT_DIR, "lm7_renda_hora_ocupacao.png"), lm_p7,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

message("Figuras de mercado de trabalho salvas.")
message("05_analises_mercado.R concluído.")
