# =============================================================================
# 05_analises_mercado.R — Análises de mercado de trabalho
# =============================================================================
# Depende de: 02_preparacao.R (pnadc_lm_srvyr)
#
# Produz (tabelas):
#   lm1_margens, lm1_horas_ocupados
#   lm2_informalidade
#   lm3_ocupacao
#   lm4_renda_grupo        (renomeado: agora compara grupos, não gêneros)
#   lm5_dupla_jornada
#   probit_comp            (LM6 — coeficientes do probit)
#   lm7_rend_hora_ocup
#
# Grupo de controle (LM1–LM4, LM7):
#   Tratamento : cônjuges mulheres < 18 anos (categ_domic == "C")
#   Controle   : filhas/parentes mulheres 14–17 anos da MESMA faixa etária
#                (NÃO cônjuges — condno_domic ≠ cônjuge)
#
# LM5 e LM6 mantêm comparação original C vs D (dupla jornada e probit).
#
# Figuras salvas em OUT_DIR:
#   lm1_participacao.png
#   lm2_informalidade.png
#   lm3_composicao_ocupacional.png
#   lm4_renda_grupo.png
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
  lm4_renda_grupo    <- lm_cache$lm4_renda_grupo
  lm5_dupla_jornada  <- lm_cache$lm5_dupla_jornada
  probit_comp        <- lm_cache$probit_comp
  lm7_rend_hora_ocup <- lm_cache$lm7_rend_hora_ocup
  rm(lm_cache)
  message("Cache LM carregado.")

} else {

  # ===========================================================================
  # BLOCO 0 — lm_filhas: controle etário (filhas/parentes femininas 14–17)
  # ===========================================================================
  # Baixa variáveis de LM para meninas 14–17 que NÃO são cônjuges.
  # Usa per-year caches (filhas_YYYY.rds) para retomar interrupção.
  # Cache consolidado: lm_filhas_cache.rds
  # Para regenerar: file.remove(file.path(CACHE_DIR, "lm_filhas_cache.rds"))
  # ===========================================================================

  FILHAS_VARS <- c(
    "Ano", "UF", "UPA",
    "V1008",    # número do domicílio
    "V2003",    # número de ordem
    "V1032",    # peso calibrado (anual, visita 1)
    "V2005",    # condição no domicílio
    "V2007",    # sexo
    "V2009",    # idade
    "V4001",    # tem trabalho remunerado
    "V403312",  # rendimento mensal do trabalho principal
    "V4039",    # horas trabalhadas efetivas na semana
    "V4029",    # contribuição ao INSS (formalidade)
    "V4012"     # posição na ocupação
  )

  import_filhas_year <- function(yr) {
    message(sprintf("  Baixando filhas/parentes LM %d...", yr))
    df <- tryCatch(
      get_pnadc(year = yr, interview = 1, vars = FILHAS_VARS, design = FALSE),
      error = function(e) { warning(sprintf("  Falhou %d: %s", yr, e$message)); NULL }
    )
    if (is.null(df)) return(NULL)

    df <- df |>
      rename(any_of(c(
        pes_comcalib            = "V1032",
        n_domic                 = "V1008",
        num_ordem               = "V2003",
        condno_domic            = "V2005",
        sexo                    = "V2007",
        idade                   = "V2009",
        trab_remun              = "V4001",
        rend                    = "V403312",
        horas_trabalhadas_seman = "V4039",
        inss                    = "V4029",
        pos_ocup                = "V4012"
      )))

    if (!"inss"     %in% names(df)) df$inss     <- NA_character_
    if (!"pos_ocup" %in% names(df)) df$pos_ocup <- NA_character_

    df <- df |>
      mutate(
        sexo = case_when(
          sexo %in% c("Mulher", "Feminino")  ~ "Feminino",
          sexo %in% c("Homem",  "Masculino") ~ "Masculino",
          TRUE ~ sexo
        ),
        domic_id  = paste(UF, UPA, n_domic, sep = "_"),
        pessoa_id = paste(domic_id, num_ordem, sep = "_")
      ) |>
      filter(
        str_detect(as.character(condno_domic),
                   "(?i)filho|enteado|outro parente|parente"),
        sexo  == "Feminino",
        idade >= 14L, idade <= 17L
      )

    if (nrow(df) == 0L) {
      message(sprintf("  Ano %d: nenhuma filha/parente encontrada.", yr))
      return(NULL)
    }

    df |>
      mutate(
        trab_remun_bin = as.integer(as.character(trab_remun) == "Sim"),
        rend           = if_else(as.character(trab_remun) != "Sim", NA_real_, rend),
        inss_lbl       = as.character(inss),
        pos_ocup_lbl   = as.character(pos_ocup),
        formal_bin     = as.integer(inss_lbl == "Sim"),
        pos_simples    = case_when(
          is.na(pos_ocup_lbl)                                                     ~ NA_character_,
          str_detect(pos_ocup_lbl, "(?i)dom.stico|domestico")                     ~ "Doméstico",
          str_detect(pos_ocup_lbl, "(?i)p.blico|publico|militar")                 ~ "Setor público",
          str_detect(pos_ocup_lbl, "(?i)privado") & inss_lbl == "Sim"             ~ "Privado c/ carteira",
          str_detect(pos_ocup_lbl, "(?i)privado")                                 ~ "Privado s/ carteira",
          str_detect(pos_ocup_lbl, "(?i)conta pr.pria|conta propria|conta-pr")    ~ "Conta própria",
          str_detect(pos_ocup_lbl, "(?i)empregador")                              ~ "Empregador",
          TRUE                                                                     ~ "Outro"
        ),
        grupo_lm = "Filha/parente 14–17"
      ) |>
      select(pessoa_id, domic_id, Ano, UF, UPA, pes_comcalib,
             sexo, idade, trab_remun, trab_remun_bin, rend,
             horas_trabalhadas_seman, formal_bin, pos_simples, grupo_lm)
  }

  lm_filhas_cache_path <- file.path(CACHE_DIR, "lm_filhas_cache.rds")

  if (file.exists(lm_filhas_cache_path)) {
    message("Carregando lm_filhas do cache...")
    lm_filhas <- readRDS(lm_filhas_cache_path)
    message(sprintf("  lm_filhas: %d linhas | anos: %s",
                    nrow(lm_filhas),
                    paste(sort(unique(as.character(lm_filhas$Ano))), collapse = ", ")))
  } else {
    message("Baixando filhas/parentes para controle LM (pode demorar ~20 min)...")
    lm_filhas    <- NULL
    anos_fail_fh <- character(0)

    for (yr in PNADC_YEARS) {
      yr_cache <- file.path(CACHE_DIR, sprintf("filhas_%d.rds", yr))

      if (file.exists(yr_cache)) {
        message(sprintf("  Ano %d: carregando do cache.", yr))
        yr_data <- readRDS(yr_cache)
      } else {
        yr_data <- import_filhas_year(yr)

        # Limpa zips do tempdir imediatamente após download de cada ano
        temp_zips <- list.files(tempdir(), pattern = "\\.zip$",
                                full.names = TRUE, recursive = TRUE)
        if (length(temp_zips) > 0) {
          unlink(temp_zips)
          message(sprintf("  Temp limpo: %d zip(s) removidos.", length(temp_zips)))
        }

        if (!is.null(yr_data)) {
          saveRDS(yr_data, yr_cache, compress = "xz")
          message(sprintf("  Ano %d: salvo em cache (%d linhas).", yr, nrow(yr_data)))
        }
      }

      if (is.null(yr_data)) {
        anos_fail_fh <- c(anos_fail_fh, as.character(yr))
      } else {
        lm_filhas <- bind_rows(lm_filhas, yr_data)
        rm(yr_data); gc()
      }
    }

    if (length(anos_fail_fh) > 0)
      warning("Anos filhas não importados: ", paste(anos_fail_fh, collapse = ", "))

    message(sprintf("lm_filhas: %d linhas | %.1f MB",
                    nrow(lm_filhas),
                    as.numeric(object.size(lm_filhas)) / 1e6))

    saveRDS(lm_filhas, lm_filhas_cache_path, compress = "xz")
    message("Cache lm_filhas salvo em: ", lm_filhas_cache_path)

    if (length(anos_fail_fh) == 0) {
      file.remove(Filter(file.exists,
        file.path(CACHE_DIR, sprintf("filhas_%d.rds", PNADC_YEARS))))
      message("Caches individuais filhas removidos.")
    }
  }

  # ── Helper: médias ponderadas ──────────────────────────────────────────────
  lm_vars <- pnadc_lm_srvyr$variables |>
    mutate(peso = weights(pnadc_lm_srvyr))

  wt_mean <- function(x, w) {
    ok <- !is.na(x) & !is.na(w)
    if (sum(ok) == 0) return(NA_real_)
    sum(x[ok] * w[ok]) / sum(w[ok])
  }

  # ===========================================================================
  # BLOCO CTRL — Frame combinado para LM1–LM4, LM7
  # ===========================================================================
  # Tratamento : cônjuges mulheres <18 da cat. C
  # Controle   : filhas/parentes femininas 14–17 (NÃO cônjuges)
  # ===========================================================================

  lm_ctrl <- bind_rows(
    # Tratamento: cônjuges menores — Cat. C, mulheres
    lm_vars |>
      filter(
        categ_domic  == "C",
        condno_domic == "Cônjuge ou companheiro(a) de sexo diferente",
        sexo_bin     == 1L
      ) |>
      mutate(grupo_lm = "Cônjuge < 18"),

    # Controle: filhas/parentes femininas 14–17
    lm_filhas |>
      mutate(peso = pes_comcalib)
  ) |>
    mutate(
      grupo_lm = factor(grupo_lm,
                        levels = c("Cônjuge < 18", "Filha/parente 14–17"))
    )

  message(sprintf("lm_ctrl: %d linhas | Cônjuge < 18: %d | Filha/parente: %d",
                  nrow(lm_ctrl),
                  sum(lm_ctrl$grupo_lm == "Cônjuge < 18",      na.rm = TRUE),
                  sum(lm_ctrl$grupo_lm == "Filha/parente 14–17", na.rm = TRUE)))

  # ── LM1: Margens extensiva e intensiva ─────────────────────────────────────
  message("  LM1: margens extensiva e intensiva...")
  lm1_margens <- lm_ctrl |>
    filter(!is.na(grupo_lm)) |>
    group_by(Ano, grupo_lm) |>
    summarise(
      taxa_participacao = wt_mean(trab_remun_bin,          peso),
      horas_media_total = wt_mean(horas_trabalhadas_seman, peso),
      n_obs             = n(),
      .groups = "drop"
    )

  lm1_horas_ocupados <- lm_ctrl |>
    filter(!is.na(grupo_lm),
           as.character(trab_remun) == "Sim",
           !is.na(horas_trabalhadas_seman)) |>
    group_by(Ano, grupo_lm) |>
    summarise(
      horas_media_ocup = wt_mean(horas_trabalhadas_seman, peso),
      n_obs            = n(),
      .groups = "drop"
    )
  message("  LM1 concluído.")

  # ── LM2: Taxa de informalidade ─────────────────────────────────────────────
  message("  LM2: informalidade...")
  lm2_informalidade <- lm_ctrl |>
    filter(!is.na(grupo_lm),
           as.character(trab_remun) == "Sim",
           !is.na(formal_bin)) |>
    mutate(informal_bin = 1L - formal_bin) |>
    group_by(Ano, grupo_lm) |>
    summarise(
      taxa_formal   = wt_mean(formal_bin,   peso),
      taxa_informal = wt_mean(informal_bin, peso),
      n_obs         = n(),
      .groups = "drop"
    )
  message("  LM2 concluído.")

  # ── LM3: Composição ocupacional ────────────────────────────────────────────
  message("  LM3: composicao_ocupacional...")
  lm3_ocupacao <- lm_ctrl |>
    filter(!is.na(grupo_lm),
           as.character(trab_remun) == "Sim",
           !is.na(pos_simples)) |>
    group_by(Ano, grupo_lm, pos_simples) |>
    summarise(n_pond = sum(peso, na.rm = TRUE), .groups = "drop") |>
    group_by(Ano, grupo_lm) |>
    mutate(prop = n_pond / sum(n_pond)) |>
    ungroup()
  message("  LM3 concluído.")

  # ── LM4: Renda média por grupo (cônjuge < 18 vs filha/parente 14–17) ───────
  # Anteriormente: razão H/M dentro de cada categ. Agora comparamos a renda
  # das cônjuges menores com a das jovens da mesma faixa etária não cônjuges.
  message("  LM4: renda média por grupo...")
  lm4_renda_grupo <- lm_ctrl |>
    filter(!is.na(grupo_lm),
           as.character(trab_remun) == "Sim",
           !is.na(rend), rend > 0) |>
    group_by(Ano, grupo_lm) |>
    summarise(
      renda_media  = wt_mean(rend, peso),
      n_obs        = n(),
      .groups = "drop"
    )
  message("  LM4 concluído.")

  # ── LM5: Dupla jornada (mantém Cat C vs D — variável não disponível p/ filhas) ──
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

  # ── LM6: Probit — mantém svyglm Cat C vs D ────────────────────────────────
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

  # ── LM7: Renda por hora por tipo de ocupação ──────────────────────────────
  message("  LM7: renda por hora por ocupação...")
  lm7_rend_hora_ocup <- lm_ctrl |>
    filter(!is.na(grupo_lm),
           as.character(trab_remun) == "Sim",
           !is.na(pos_simples), !is.na(rend), rend > 0,
           !is.na(horas_trabalhadas_seman), horas_trabalhadas_seman > 0) |>
    mutate(rend_hora = rend / (horas_trabalhadas_seman * 4.33)) |>
    group_by(grupo_lm, pos_simples) |>
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
         lm4_renda_grupo    = lm4_renda_grupo,
         lm5_dupla_jornada  = lm5_dupla_jornada,
         probit_comp        = probit_comp,
         lm7_rend_hora_ocup = lm7_rend_hora_ocup),
    lm_cache_path, compress = TRUE
  )
  message("Cache LM salvo em: ", lm_cache_path)
  rm(lm_vars, lm_ctrl, lm_filhas); gc()
}

message("Análises de mercado de trabalho concluídas.")

# =============================================================================
# PALETA e LABELS — grupos de controle (novo)
# =============================================================================

cores_grupo_lm <- c(
  "Cônjuge < 18"       = "#C0392B",
  "Filha/parente 14–17" = "#2980B9"
)

# =============================================================================
# FIGURAS DE MERCADO DE TRABALHO
# =============================================================================

# LM Plot 1: Participação laboral — cônjuge < 18 vs filha/parente 14–17
lm_p1 <- lm1_margens |>
  filter(!is.na(grupo_lm)) |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  ggplot(aes(x = Ano, y = taxa_participacao,
             color = grupo_lm, group = grupo_lm)) +
  geom_line(linewidth = 1) + geom_point(size = 2.5) +
  scale_color_manual(values = cores_grupo_lm, name = NULL) +
  scale_x_continuous(breaks = anos_pnadc) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(title    = "LM 1: Taxa de Participação Laboral — Mulheres 14–17 anos",
       subtitle = "Cônjuges menores (Cat. C) vs. filhas/parentes da mesma faixa etária",
       x = NULL, y = "Taxa de participação (%)",
       caption = "Fonte: PNADC (V4001). Médias ponderadas. Elaboração dos autores.") +
  theme_paper

ggsave(file.path(OUT_DIR, "lm1_participacao.png"), lm_p1,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# LM Plot 2: Taxa de informalidade — cônjuge < 18 vs filha/parente 14–17
lm_p2 <- lm2_informalidade |>
  filter(!is.na(grupo_lm)) |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  ggplot(aes(x = Ano, y = taxa_informal,
             color = grupo_lm, group = grupo_lm)) +
  geom_line(linewidth = 1) + geom_point(size = 2.5) +
  scale_color_manual(values = cores_grupo_lm, name = NULL) +
  scale_x_continuous(breaks = anos_pnadc) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(title    = "LM 2: Taxa de Informalidade — Mulheres 14–17 anos",
       subtitle = "% sem INSS entre ocupadas: cônjuge menor vs. filha/parente da mesma faixa etária",
       x = NULL, y = "Taxa de informalidade (%)",
       caption = "Fonte: PNADC (V4029). Médias ponderadas. Elaboração dos autores.") +
  theme_paper

ggsave(file.path(OUT_DIR, "lm2_informalidade.png"), lm_p2,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# LM Plot 3: Composição ocupacional — stacked bar (pooled)
lm_p3 <- lm3_ocupacao |>
  filter(!is.na(pos_simples), !is.na(grupo_lm)) |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  group_by(grupo_lm, pos_simples) |>
  summarise(prop = mean(prop, na.rm = TRUE), .groups = "drop") |>
  mutate(
    pos_simples = factor(pos_simples,
      levels = c("Setor público","Privado c/ carteira","Privado s/ carteira",
                 "Doméstico","Conta própria","Empregador","Outro"))
  ) |>
  ggplot(aes(x = grupo_lm, y = prop, fill = pos_simples)) +
  geom_col(position = "fill", width = 0.6) +
  scale_fill_brewer(palette = "Set2", name = "Posição na ocupação") +
  scale_y_continuous(labels = label_percent()) +
  labs(title    = "LM 3: Composição Ocupacional — Mulheres 14–17 (pooled 2012–2023)",
       subtitle = "Distribuição por tipo de vínculo entre cônjuges menores e filhas/parentes",
       x = NULL, y = "Proporção (%)",
       caption = "Fonte: PNADC (V4012). Elaboração dos autores.") +
  theme_paper + theme(legend.position = "right")

ggsave(file.path(OUT_DIR, "lm3_composicao_ocupacional.png"), lm_p3,
       width = 20, height = 13, units = "cm", dpi = 300, bg = "white")

# LM Plot 4: Renda média — cônjuge < 18 vs filha/parente 14–17
# (Antes: razão H/M dentro de categoria. Agora: comparação de renda entre grupos)
lm_p4 <- lm4_renda_grupo |>
  filter(!is.na(grupo_lm)) |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  ggplot(aes(x = Ano, y = renda_media,
             color = grupo_lm, group = grupo_lm)) +
  geom_line(linewidth = 1) + geom_point(size = 2.5) +
  scale_color_manual(values = cores_grupo_lm, name = NULL) +
  scale_x_continuous(breaks = anos_pnadc) +
  scale_y_continuous(labels = label_number(big.mark = ".", decimal.mark = ",",
                                           prefix = "R$ ")) +
  labs(title    = "LM 4: Renda Média — Mulheres 14–17 anos (ocupadas)",
       subtitle = "Cônjuges menores (Cat. C) vs. filhas/parentes da mesma faixa etária",
       x = NULL, y = "Renda média (R$)",
       caption = "Fonte: PNADC (V403312). Médias ponderadas. Elaboração dos autores.") +
  theme_paper

ggsave(file.path(OUT_DIR, "lm4_renda_grupo.png"), lm_p4,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# LM Plot 5: Dupla jornada — cônjuges mulheres C vs D (inalterado)
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
  labs(title    = "LM 5: Dupla Jornada — Cônjuges Mulheres",
       subtitle = "% que trabalha fora E faz cuidado doméstico vs. só cuidado doméstico",
       x = NULL, y = "Taxa (%)",
       caption = "Fonte: PNADC. Elaboração dos autores.") +
  theme_paper

ggsave(file.path(OUT_DIR, "lm5_dupla_jornada.png"), lm_p5,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

# LM Plot 6: Coeficientes do probit — C vs D (inalterado)
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
  labs(title    = "LM 6: Probit — Determinantes da Participação Laboral (C vs D)",
       subtitle = "Coeficientes de P(trabalha) ~ idade + raça | cônjuges mulheres",
       x = NULL, y = "Coeficiente (log-odds)",
       caption = "Fonte: PNADC. svyglm(quasibinomial). IC 95%. Elaboração dos autores.") +
  theme_paper + theme(legend.position = "right")

ggsave(file.path(OUT_DIR, "lm6_probit_participacao.png"), lm_p6,
       width = 20, height = 13, units = "cm", dpi = 300, bg = "white")

# LM Plot 7: Renda por hora por tipo de ocupação — novo controle
lm_p7 <- lm7_rend_hora_ocup |>
  filter(!is.na(pos_simples), !is.na(grupo_lm)) |>
  mutate(
    pos_simples = factor(pos_simples,
      levels = c("Setor público","Privado c/ carteira","Conta própria",
                 "Privado s/ carteira","Doméstico","Empregador","Outro"))
  ) |>
  ggplot(aes(x = reorder(pos_simples, media_rend_hora),
             y = media_rend_hora, fill = grupo_lm)) +
  geom_col(position = position_dodge(0.7), width = 0.6) +
  coord_flip() +
  scale_fill_manual(values = cores_grupo_lm, name = NULL) +
  scale_y_continuous(labels = label_number(big.mark = ".", decimal.mark = ",",
                                           prefix = "R$ ")) +
  labs(title    = "LM 7: Renda por Hora por Tipo de Ocupação — Mulheres 14–17",
       subtitle = "Produtividade horária (R$/hora) por posição, pooled 2012–2023",
       x = NULL, y = "Renda por hora (R$)",
       caption = "Fonte: PNADC. Elaboração dos autores.") +
  theme_paper + theme(legend.position = "right")

ggsave(file.path(OUT_DIR, "lm7_renda_hora_ocupacao.png"), lm_p7,
       width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

message("Figuras de mercado de trabalho salvas.")
message("05_analises_mercado.R concluído.")
