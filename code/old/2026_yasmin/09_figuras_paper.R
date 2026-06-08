# =============================================================================
# 09_figuras_paper.R — Figuras prontas para o paper (publication-ready)
# =============================================================================
# 
#   [GERAL]  Tudo em inglês, sem title/subtitle (serão feitos via LaTeX),
#            sem source no caption (vai para \note{} no LaTeX),
#            data labels em todos os gráficos de série temporal.
#   [Fig. 2] Y-axis: % dos casamentos totais do RC (não contagem absoluta)
#   [Fig. 6] Labels "xx.xx%" em cada ponto
#   [ECON 1] Labels "x.xx%" em cada ponto + novo gráfico PNADC vs RC como %
#   [ECON 2] Transformar em painel de mapas coropléticos (2013,2015,2017,2019,2023)
#   [ECON 3] Manter como linha — sem transformação ("Não precisa fazer pra esse")
#   [Gap]    Gráfico de barras com labels; verificar média (~8 anos)
#   [EDUC]   EDUC A (school attendance, bar chart); EDUC C (education level)
#   [LM 1]   Labels; controle = filha/parente 14–17 (já em 05_analises_mercado.R)
#
# Depende de: caches em CACHE_DIR (não re-roda os pipelines pesados)
#   pnadc_categ_cache.rds  — para cálculo UF-level no mapa
#   parte3_cache.rds       — early_annual (PNADC stock)
#   parte5_cache.rds       — prevalencia_anual, prevalencia_regional_taxa, etc.
#   lm_analises_cache.rds  — lm1_margens, etc.
#   pnadc_educ_prep_cache.rds — para EDUC A / C
#   rc_raw_cache.rds       — rc_raw para Fig. 2 como %
#
# Outputs salvos em PUB_DIR (sub-pasta outputs/pub/) para não sobrescrever os originais.
#
# Nota LaTeX (template para cada figura):
#   \begin{figure}[htbp]
#     \centering
#     \includegraphics[width=\textwidth]{fig_name.png}
#     \caption{Caption title here.}
#     \footnotesize\textit{Note:} Source info + methodology here.
#     \label{fig:fig_name}
#   \end{figure}
# =============================================================================

source(here::here("00_setup.R"))
library(ggrepel)    # geom_text_repel para labels sem sobreposição

# Sub-pasta dedicada para figuras do paper (separada dos outputs intermediários)
PUB_DIR <- file.path(OUT_DIR, "pub")
dir.create(PUB_DIR, showWarnings = FALSE, recursive = TRUE)

# geobr é necessário apenas para o mapa (ECON 2)
has_geobr <- requireNamespace("geobr", quietly = TRUE)
if (has_geobr) {
  library(geobr)
  library(sf)
} else {
  message("NOTA: instale geobr para o mapa coroplético: install.packages('geobr')")
  message("  ECON 2 será exportado como gráfico de linhas (fallback).")
}

# =============================================================================
# TEMA E PALETAS — publication-quality (economics paper standard)
# =============================================================================
# Design principles:
#   • theme_classic base + horizontal gridlines only (no vertical clutter)
#   • Law reference lines in gray50 (dashed), never red
#   • Linetype differentiation in all multi-series charts (B&W print-safe)
#   • Colourblind-friendly, muted palette
#   • Consistent: linewidth = 0.8, point size = 1.8 throughout

theme_pub <- theme_classic(base_size = 11) +
  theme(
    plot.title       = element_blank(),
    plot.subtitle    = element_blank(),
    plot.caption     = element_blank(),   # source vai para LaTeX \note{}
    # Axes
    axis.line        = element_line(colour = "black", linewidth = 0.4),
    axis.ticks       = element_line(colour = "black", linewidth = 0.3),
    axis.text        = element_text(size = 9, colour = "black"),
    axis.title       = element_text(size = 10),
    # Horizontal gridlines only
    panel.grid.major.y = element_line(colour = "gray90", linewidth = 0.3),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank(),
    # Legend: tight, no box
    legend.position    = "bottom",
    legend.text        = element_text(size = 9),
    legend.key.size    = unit(0.45, "cm"),
    legend.key         = element_blank(),
    legend.background  = element_blank(),
    legend.title       = element_text(size = 9),
    # Facet strips: no background box
    strip.background = element_blank(),
    strip.text       = element_text(face = "bold", size = 9),
    # Background
    plot.background  = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA),
    plot.margin      = margin(8, 10, 6, 8)
  )

# ── Colour constants ──────────────────────────────────────────────────────────
COL_MAIN     <- "#2C3E50"   # dark navy  — single-series primary
COL_TREAT    <- "#B22222"   # firebrick  — minor spouse / PNADC stock
COL_CONTROL  <- "#2C3E50"   # dark navy  — comparison group / RC flow
COL_RC       <- "#555555"   # medium gray — Civil Registry series
COL_REF      <- "gray50"    # reference / law line (replaces red everywhere)
COL_BAR_MAIN <- "gray38"    # single-series bar fill
COL_BAR_A    <- "gray28"    # two-group bar A (Rural / darker)
COL_BAR_B    <- "gray70"    # two-group bar B (Urban / lighter)

# ── Named palettes ────────────────────────────────────────────────────────────
# Portuguese-label palettes (for figures using raw grupo_educ column values)
cores_grupo_educ <- c("Cônjuge < 18"        = COL_TREAT,
                      "Filho/parente 14–17"  = COL_CONTROL)
lt_educ          <- c("Cônjuge < 18"        = "solid",
                      "Filho/parente 14–17"  = "dashed")
lbl_educ         <- c("Cônjuge < 18"        = "Minor spouse",
                      "Filho/parente 14–17"  = "Daughter/relative 14–17")

cores_grupo_lm   <- c("Cônjuge < 18"        = COL_TREAT,
                      "Filha/parente 14–17"  = COL_CONTROL)
cores_rural_urb  <- c("Rural" = COL_BAR_A, "Urban" = COL_BAR_B)

# English-label linetypes (figures that recode grupo_educ before plotting)
lt_group_en <- c("Minor spouse"             = "solid",
                 "Daughter/relative 14–17"  = "dashed")

# Helper: any UF representation (full name / sigla / IBGE code) → integer code
# Required because pnadc_categ$UF is a labelled factor with state names, so
# as.integer(as.character(UF)) introduces NAs for every non-numeric label.
uf_to_code <- function(uf) {
  sc <- c(
    RO=11L, AC=12L, AM=13L, RR=14L, PA=15L, AP=16L, TO=17L,
    MA=21L, PI=22L, CE=23L, RN=24L, PB=25L, PE=26L, AL=27L, SE=28L, BA=29L,
    MG=31L, ES=32L, RJ=33L, SP=35L,
    PR=41L, SC=42L, RS=43L,
    MS=50L, MT=51L, GO=52L, DF=53L
  )
  sc[uf_to_sigla(as.character(uf))]   # uf_to_sigla() handles names, siglas, codes
}

# Anos nos eixos
anos_breaks <- c(2012:2019, 2022, 2023)
LABEL_ANOS  <- c(2012, 2015, 2019, 2023)

# =============================================================================
# CARREGAR DADOS DOS CACHES
# =============================================================================
# Estratégia de memória:
#   1. pnadc_categ (maior cache) carregado PRIMEIRO, quando a RAM está livre.
#      Extraímos apenas os dois objetos derivados que precisamos (prev_uf e
#      age_gap_periodo), depois fazemos rm() + gc() antes de carregar o resto.
#   2. Demais caches carregados em sequência, liberando cada um após uso.
# Isso evita o erro "cannot allocate vector" causado por múltiplos caches
# grandes coexistindo na memória.
# =============================================================================

# ── Verificação prévia: todos os caches necessários devem existir ─────────────
required_caches <- list(
  pnadc_categ_cache    = list(file = "pnadc_categ_cache.rds",    script = "02_preparacao.R"),
  rc_raw_cache         = list(file = "rc_raw_cache.rds",         script = "01_importacao.R"),
  parte3_cache         = list(file = "parte3_cache.rds",         script = "04_analises_PNADC.R  (Part 3)"),
  parte5_cache         = list(file = "parte5_cache.rds",         script = "04_analises_PNADC.R  (Parts 5.6–5.13)"),
  lm_analises_cache    = list(file = "lm_analises_cache.rds",    script = "05_analises_mercado.R"),
  pnadc_educ_prep_cache = list(file = "pnadc_educ_prep_cache.rds", script = "02_preparacao.R / 06_analises_educacao.R")
)

missing_caches <- Filter(
  function(x) !file.exists(file.path(CACHE_DIR, x$file)),
  required_caches
)

if (length(missing_caches) > 0L) {
  msg_lines <- c(
    "",
    "====================================================================",
    "ERRO: caches necessários não encontrados em CACHE_DIR:",
    sprintf("  CACHE_DIR = %s", CACHE_DIR),
    "",
    "Caches ausentes e scripts que os geram:",
    vapply(missing_caches, function(x)
      sprintf("  ✗  %-35s  ← execute %s", x$file, x$script),
      character(1L)
    ),
    "",
    "Execute os scripts na ordem 01 → 02 → 03 → 04 → 05 → 06",
    "e tente novamente.",
    "====================================================================",
    ""
  )
  stop(paste(msg_lines, collapse = "\n"), call. = FALSE)
}

message("Preflight OK — todos os caches encontrados.")

# ── FASE 1: pnadc_categ — extrair, comprimir, liberar ────────────────────────
message("Fase 1: carregando pnadc_categ e extraindo derivados...")
pnadc_categ <- readRDS(file.path(CACHE_DIR, "pnadc_categ_cache.rds"))

MAP_YEARS <- c(2013L, 2015L, 2017L, 2019L, 2023L)

# prev_uf: usado no mapa ECON 2
message("  Extraindo prev_uf para o mapa...")
prev_uf <- pnadc_categ |>
  filter(condno_domic == "Pessoa responsável pelo domicílio",
         !is.na(categ_domic)) |>
  mutate(
    early_bin = as.integer(categ_domic %in% c("A","B","C")),
    Ano_int   = as.integer(as.character(Ano)),
    uf_code   = uf_to_code(UF)
  ) |>
  filter(Ano_int %in% MAP_YEARS) |>
  group_by(Ano_int, uf_code) |>
  summarise(taxa = weighted.mean(early_bin, w = pes_comcalib, na.rm = TRUE),
            .groups = "drop")

# age_gap_periodo: usado nos gráficos de age gap pré/pós 2019
message("  Extraindo age_gap_periodo...")
age_gap_periodo <- pnadc_categ |>
  filter(
    categ_domic  == "C",
    condno_domic == "Pessoa responsável pelo domicílio",
    !is.na(dif_idade),
    dif_idade    >= 0L,
    dif_idade    <= 40L
  ) |>
  mutate(
    Ano_int = as.integer(as.character(Ano)),
    periodo = case_when(
      Ano_int < 2019L                        ~ "Before 2019 (2012–2018)",
      Ano_int %in% c(2019L, 2022L, 2023L)   ~ "2019 and after",
      TRUE                                   ~ NA_character_
    )
  ) |>
  filter(!is.na(periodo)) |>
  group_by(periodo, dif_idade) |>
  summarise(n_pond = sum(pes_comcalib, na.rm = TRUE), .groups = "drop") |>
  group_by(periodo) |>
  mutate(
    pct      = n_pond / sum(n_pond),
    mean_gap = sum(dif_idade * n_pond) / sum(n_pond)
  ) |>
  ungroup()

# idade_conjuge: distribuição de idade dos cônjuges menores (Cat. C)
# Usada para o gráfico de CDF de idade por período.
# Filtra pela pessoa cônjuge/companheira (não o chefe) → usa V2009 (idade PNADC).
# Se 02_preparacao.R renomeou V2009, ajuste abaixo para o nome correto.
message("  Extraindo distribuição de idade do cônjuge menor...")
idade_conjuge <- tryCatch({
  pnadc_categ |>
    filter(
      categ_domic == "C",
      str_detect(as.character(condno_domic), "(?i)c[oô]njuge|companheiro")
    ) |>
    mutate(
      Ano_int = as.integer(as.character(Ano)),
      periodo = case_when(
        Ano_int < 2019L                      ~ "Before 2019 (2012–2018)",
        Ano_int %in% c(2019L, 2022L, 2023L) ~ "2019 and after",
        TRUE                                 ~ NA_character_
      ),
      idade = as.integer(idade)   # <— ajuste se renomeado
    ) |>
    filter(!is.na(periodo), !is.na(idade), idade >= 10L, idade <= 17L) |>
    group_by(periodo, idade) |>
    summarise(n_pond = sum(pes_comcalib, na.rm = TRUE), .groups = "drop") |>
    group_by(periodo) |>
    arrange(periodo, idade) |>
    mutate(
      pct = n_pond / sum(n_pond),
      cdf = cumsum(pct)
    ) |>
    ungroup()
}, error = function(e) {
  warning("idade_conjuge não pôde ser extraído: ", conditionMessage(e),
          "\n  Verifique o nome da coluna de idade em pnadc_categ.")
  NULL
})
if (!is.null(idade_conjuge))
  message(sprintf("  idade_conjuge extraído: %d combinações período×idade.",
                  nrow(idade_conjuge)))

# total_conjugal_yr: total de domicílios conjugais (A+B+C+D) por ano.
# Necessário para calcular a proporção PNADC de uniões com menores em relação
# ao total de uniões — denominador correto para a comparação com o RC.
message("  Extraindo total de domicilios conjugais por ano...")
total_conjugal_yr <- pnadc_categ |>
  filter(
    condno_domic == "Pessoa responsável pelo domicílio",
    !is.na(categ_domic)
  ) |>
  mutate(Ano_int = as.integer(as.character(Ano))) |>
  group_by(Ano_int) |>
  summarise(
    n_conjugal = sum(pes_comcalib, na.rm = TRUE),
    .groups = "drop"
  )
message(sprintf("  total_conjugal_yr extraído: %d anos.", nrow(total_conjugal_yr)))

rm(pnadc_categ); gc()
message("  pnadc_categ liberado da memória.")

# ── FASE 2: caches leves — carregar em sequência ─────────────────────────────
safe_rds <- function(name) {
  path <- file.path(CACHE_DIR, name)
  readRDS(path)  # preflight já garantiu existência; erro aqui é problema de I/O
}

message("Fase 2: carregando demais caches...")

# RC raw
rc_raw <- safe_rds("rc_raw_cache.rds")

# Parte 3 — extrai só early_annual (o resto não é necessário aqui)
p3           <- safe_rds("parte3_cache.rds")
early_annual <- p3$early_annual
rm(p3); gc()

# Parte 5
p5 <- safe_rds("parte5_cache.rds")
list2env(p5, envir = environment())
rm(p5); gc()

# LM
lm_cache <- safe_rds("lm_analises_cache.rds")
list2env(lm_cache, envir = environment())
rm(lm_cache); gc()

# Educação
pnadc_educ <- safe_rds("pnadc_educ_prep_cache.rds")

message("Todos os caches carregados.")

# Reconstrói educ_vars (weighted means diretos — mesmo padrão de 06_analises_educacao.R)
wt_mean <- function(x, w) {
  ok <- !is.na(x) & !is.na(w)
  if (sum(ok) == 0L) return(NA_real_)
  sum(x[ok] * w[ok]) / sum(w[ok])
}

educ_vars <- pnadc_educ |>
  filter(!is.na(grupo_educ)) |>
  mutate(peso = pes_comcalib)

# Reconstrói rc_flow e rc_pct_total a partir de rc_raw
rc_pct_total <- rc_raw |>
  group_by(ano) |>
  summarise(
    total_inf   = sum(n_total_row * is_minor_w, na.rm = TRUE),
    total_geral = sum(n_total_row,              na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(pct_inf = total_inf / total_geral * 100)

rc_flow <- rc_raw |>
  group_by(ano) |>
  summarise(flow = sum(n_total_row * is_minor_w, na.rm = TRUE), .groups = "drop")

message("Dados preparados.")

# =============================================================================
# FIGURA 2 — Civil Registry: child marriages as % of all marriages
# =============================================================================
# Spec: % dos casamentos totais do Registro Civil; labels, sem título/subtítulo; fonte → LaTeX
# LaTeX note: Source: IBGE Civil Registry Statistics (Estatísticas do Registro
#   Civil). Bars show formally registered marriages with at least one spouse
#   under 18 as a share of total marriages. Dashed line: Lei 13.811/2019.

lbl_fig2 <- rc_pct_total |>
  filter(ano %in% LABEL_ANOS | ano == max(ano))

fig2_pub <- rc_pct_total |>
  ggplot(aes(x = ano, y = pct_inf)) +
  geom_line(colour = COL_MAIN, linewidth = 0.8) +
  geom_point(colour = COL_MAIN, size = 1.8) +
  geom_vline(xintercept = 2019, linetype = "dashed", colour = COL_REF) +
  annotate("text", x = 2019.2, y = max(rc_pct_total$pct_inf) * .9,
           label = "Law 13.811/2019", hjust = 0, size = 2.8, colour = "gray40") +
  geom_text_repel(data = lbl_fig2,
                  aes(label = sprintf("%.2f%%", pct_inf)),
                  size               = 2.8,
                  nudge_y            = 0.30,   # lift well above the line
                  nudge_x            = 0.40,   # slight rightward shift
                  direction          = "y",    # repel vertically only
                  segment.colour     = "gray55",
                  segment.size       = 0.3,
                  min.segment.length = 0,      # always draw the connector
                  show.legend = FALSE) +
  scale_x_continuous(breaks = seq(2003, 2022, 3)) +
  scale_y_continuous(labels = label_number(suffix = "%", accuracy = .01)) +
  labs(x = NULL, y = "Child marriages (% of all marriages)") +
  theme_pub

ggsave(file.path(PUB_DIR, "RC_pct_total.png"), fig2_pub,
       width = 18, height = 11, units = "cm", dpi = 300, bg = "white")
message("Fig2 (RC %) salva.")

# =============================================================================
# FIGURA 6 — Annual % change: Civil Registry vs. PNADC
# =============================================================================
# Spec: sem título/subtítulo; label com xx.xx% em cada ponto
# LaTeX note: Source: IBGE (Civil Registry & PNADC, visit 1). Year-on-year
#   change in the stock of early unions (PNADC) and flow of child marriages
#   (Civil Registry). PNADC 2020–2021 excluded (COVID disruption).

pnadc_stock_yr <- early_annual |>
  mutate(ano = as.integer(as.character(Ano))) |>
  select(ano, pnadc_stock = total_early)

rc_stock_yr <- rc_flow |> rename(rc_flow_n = flow)

underrep_chg <- inner_join(pnadc_stock_yr, rc_stock_yr, by = "ano") |>
  arrange(ano) |>
  mutate(
    var_pnadc = (pnadc_stock  - lag(pnadc_stock))  / lag(pnadc_stock)  * 100,
    var_rc    = (rc_flow_n    - lag(rc_flow_n))    / lag(rc_flow_n)    * 100
  ) |>
  filter(!is.na(var_pnadc)) |>
  pivot_longer(c(var_pnadc, var_rc),
               names_to = "source", values_to = "pct_change") |>
  mutate(source = recode(source,
    var_pnadc = "PNADC (stock of unions)",
    var_rc    = "Civil Registry (new marriages)"
  ))

lbl_fig6 <- underrep_chg |>
  filter(ano %in% LABEL_ANOS | ano == max(ano))

fig6_pub <- underrep_chg |>
  ggplot(aes(x = ano, y = pct_change,
             colour = source, linetype = source, group = source)) +
  geom_hline(yintercept = 0, linetype = "dotted", colour = "gray60") +
  geom_line(linewidth = 0.8) + geom_point(size = 1.8) +
  geom_text_repel(data = lbl_fig6,
                  aes(label = sprintf("%+.1f%%", pct_change)),
                  size = 2.5, show.legend = FALSE,
                  min.segment.length = .3) +
  scale_colour_manual(
    values  = c("PNADC (stock of unions)"          = COL_TREAT,
                "Civil Registry (new marriages)"   = COL_RC),
    name = NULL
  ) +
  scale_linetype_manual(
    values  = c("PNADC (stock of unions)"          = "solid",
                "Civil Registry (new marriages)"   = "dashed"),
    name = NULL
  ) +
  scale_x_continuous(breaks = anos_breaks) +
  scale_y_continuous(labels = label_percent(scale = 1)) +
  labs(x = NULL, y = "Year-on-year change (%)") +
  theme_pub

ggsave(file.path(PUB_DIR, "variation_RC_PNADC.png"), fig6_pub,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")
message("Fig6 (variation RC/PNADC) salva.")

# =============================================================================
# FIGURA NOVA — PNADC prevalence vs. RC child marriage rate (both as %)
# =============================================================================
# Spec: gráfico comparando % de casamentos PNADC vs RC; revela gap de subnotificação.
# LaTeX note: Source: IBGE Civil Registry & PNADC. Left axis: share of
#   conjugal households where a spouse is under 18 (PNADC, survey-weighted).
#   Right axis: child marriages as % of all marriages (Civil Registry).
#   The persistent gap reflects underregistration of informal unions.

pnadc_pct <- prevalencia_anual |>
  mutate(ano = as.integer(as.character(Ano)),
         pnadc_pct = taxa_uniao_precoce * 100) |>
  select(ano, pnadc_pct)

rc_pct_sel <- rc_pct_total |>
  filter(ano %in% pnadc_pct$ano) |>
  select(ano, rc_pct = pct_inf)

comparacao_pct <- inner_join(pnadc_pct, rc_pct_sel, by = "ano") |>
  pivot_longer(c(pnadc_pct, rc_pct),
               names_to = "source", values_to = "pct") |>
  mutate(source = recode(source,
    pnadc_pct = "PNADC (share of conjugal HH with minor spouse)",
    rc_pct    = "Civil Registry (% of all marriages)"
  ))

lbl_comp <- comparacao_pct |>
  filter(ano %in% LABEL_ANOS | ano == max(ano))

fig_pnadc_rc_pct <- comparacao_pct |>
  ggplot(aes(x = ano, y = pct,
             colour = source, linetype = source, group = source)) +
  geom_vline(xintercept = 2019, linetype = "dashed", colour = COL_REF) +
  geom_line(linewidth = 0.8) + geom_point(size = 1.8) +
  geom_text_repel(data = lbl_comp,
                  aes(label = sprintf("%.2f%%", pct)),
                  size = 2.5, show.legend = FALSE, min.segment.length = .3) +
  scale_colour_manual(
    values = c("PNADC (share of conjugal HH with minor spouse)" = COL_TREAT,
               "Civil Registry (% of all marriages)"           = COL_RC),
    name = NULL
  ) +
  scale_linetype_manual(
    values = c("PNADC (share of conjugal HH with minor spouse)" = "solid",
               "Civil Registry (% of all marriages)"           = "dashed"),
    name = NULL
  ) +
  scale_x_continuous(breaks = anos_breaks) +
  scale_y_continuous(labels = label_number(suffix = "%", accuracy = .01)) +
  labs(x = NULL, y = "Share (%)") +
  theme_pub

ggsave(file.path(PUB_DIR, "pnadc_vs_rc_pct.png"), fig_pnadc_rc_pct,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")
message("Fig PNADC vs RC (%) salva.")

# =============================================================================
# ECON 1 — Annual prevalence of early unions
# =============================================================================
# Spec: sem título/subtítulo; label com x.xx% em cada ponto
# LaTeX note: Source: PNADC (visit 1, IBGE), survey-weighted estimates.
#   Share of conjugal households in which at least one spouse is under 18.
#   Shaded area: 95% confidence interval. Dashed line: Lei 13.811/2019.
#   Years 2020–2021 excluded due to COVID-related survey disruption.

prev_anual_df <- prevalencia_anual |>
  mutate(Ano = as.integer(as.character(Ano)))

lbl_econ1 <- prev_anual_df |>
  filter(Ano %in% LABEL_ANOS | Ano == max(Ano))

econ1_pub <- prev_anual_df |>
  ggplot(aes(x = Ano, y = taxa_uniao_precoce)) +
  geom_ribbon(aes(ymin = taxa_uniao_precoce_low,
                  ymax = taxa_uniao_precoce_upp),
              alpha = .12, fill = COL_MAIN) +
  geom_line(colour = COL_MAIN, linewidth = 0.8) +
  geom_point(colour = COL_MAIN, size = 1.8) +
  geom_vline(xintercept = 2019, linetype = "dashed", colour = COL_REF) +
  annotate("text", x = 2019.2, y = max(prev_anual_df$taxa_uniao_precoce, na.rm = TRUE) * .96,
           label = "Lei 13.811/2019", hjust = 0, size = 2.8, colour = "gray40") +
  geom_text_repel(data = lbl_econ1,
                  aes(label = sprintf("%.2f%%", taxa_uniao_precoce * 100)),
                  size = 2.8, nudge_y = .0004, min.segment.length = .3) +
  scale_x_continuous(breaks = anos_breaks) +
  scale_y_continuous(labels = label_percent(accuracy = .1)) +
  labs(x = NULL, y = "Prevalence (% of conjugal households)") +
  theme_pub

ggsave(file.path(PUB_DIR, "prevalencia_anual_pnad.png"), econ1_pub,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")
message("ECON 1 salva.")

# =============================================================================
# ECON 2 — Regional prevalence: choropleth map panel (5 selected years)
# =============================================================================
# Spec: mapa coroplético com anos 2013, 2015, 2017, 2019, 2023 em grid.
# LaTeX note: Source: PNADC (visit 1, IBGE), weighted means by state.
#   Share of conjugal households with at least one minor spouse, by Brazilian
#   state. Selected years; 2020–2021 excluded (COVID). Darker shading indicates
#   higher prevalence. States without data shown in light grey.
# prev_uf already computed in Fase 1 (loading section) to avoid RAM conflicts.

if (has_geobr) {
  states_sf <- tryCatch(
    geobr::read_state(year = 2020, simplified = TRUE, showProgress = FALSE),
    error = function(e) { warning("geobr::read_state falhou: ", e$message); NULL }
  )

  if (!is.null(states_sf)) {
    map_data <- states_sf |>
      left_join(prev_uf, by = c("code_state" = "uf_code")) |>
      filter(!is.na(Ano_int))

    # Legenda: garante escala contínua mesmo com dados ausentes em alguns anos
    scale_limits <- range(prev_uf$taxa, na.rm = TRUE)

    econ2_map_pub <- map_data |>
      mutate(Ano_int = factor(Ano_int)) |>
      ggplot() +
      geom_sf(aes(fill = taxa * 100), color = "white", linewidth = .15) +
      facet_wrap(~ Ano_int, nrow = 1) +
      scale_fill_gradient(
        low  = "#EFF3FF",
        high = "#084594",
        na.value = "grey80",
        limits = scale_limits * 100,
        labels = label_number(suffix = "%", accuracy = .1),
        name   = "Prevalence (%)"
      ) +
      theme_void() +
      theme(
        legend.position  = "bottom",
        legend.title     = element_text(size = 8),
        legend.text      = element_text(size = 7),
        legend.key.width = unit(1.5, "cm"),
        strip.background = element_blank(),
        strip.text       = element_text(face = "bold", size = 9),
        plot.background  = element_rect(fill = "white", colour = NA),
        plot.margin      = margin(2, 2, 2, 2)
      )

    ggsave(file.path(PUB_DIR, "mapa_regional.png"), econ2_map_pub,
           width = 28, height = 10, units = "cm", dpi = 300, bg = "white")
    message("ECON 2 (mapa) salva.")
  } else {
    message("geobr falhou — exportando ECON 2 como linha (fallback).")
    has_geobr <- FALSE
  }
}

if (!has_geobr) {
  # Fallback: gráfico de linhas por região (original melhorado)
  econ2_line_pub <- prevalencia_regional_taxa |>
    mutate(Ano = as.integer(as.character(Ano))) |>
    filter(!is.na(regiao)) |>
    ggplot(aes(x = Ano, y = taxa_uniao_precoce,
               colour = regiao, linetype = regiao, group = regiao)) +
    geom_line(linewidth = 0.8) + geom_point(size = 1.8) +
    scale_colour_manual(
      values = c("Norte"        = "#B22222",
                 "Nordeste"     = "#E69A00",
                 "Sudeste"      = "#2166AC",
                 "Sul"          = "#1D7C4D",
                 "Centro-Oeste" = "#555555"),
      name = "Region"
    ) +
    scale_linetype_manual(
      values = c("Norte"        = "solid",
                 "Nordeste"     = "dashed",
                 "Sudeste"      = "dotdash",
                 "Sul"          = "longdash",
                 "Centro-Oeste" = "twodash"),
      name = "Region"
    ) +
    scale_x_continuous(breaks = anos_breaks) +
    scale_y_continuous(labels = label_percent(accuracy = .1)) +
    labs(x = NULL, y = "Prevalence (% of conjugal households)") +
    theme_pub

  ggsave(file.path(PUB_DIR, "mapa_regional.png"), econ2_line_pub,
         width = 22, height = 12, units = "cm", dpi = 300, bg = "white")
  message("ECON 2 (fallback linha) salva.")
}

# =============================================================================
# ECON 3 — Urban vs. rural prevalence (BAR CHART — grouped by year)
# =============================================================================
# Requested: "% casamentos informais urbano vs rural, de barras"
# LaTeX note: Source: PNADC (visit 1, IBGE), survey-weighted. Share of
#   conjugal households with at least one minor spouse, by residential area.
#   Grouped bars per year; 2020–2021 excluded (COVID). Dashed line: 2019.

econ3_pub <- prevalencia_rural |>
  mutate(
    Ano     = as.integer(as.character(Ano)),
    area_en = if_else(area == "Rural", "Rural", "Urban")
  ) |>
  filter(!is.na(area)) |>
  ggplot(aes(x = factor(Ano), y = taxa_uniao_precoce * 100, fill = area_en)) +
  geom_col(position = "dodge", width = 0.72, alpha = 0.87) +
  geom_errorbar(
    aes(ymin = taxa_uniao_precoce_low * 100,
        ymax = taxa_uniao_precoce_upp * 100),
    position = position_dodge(0.72), width = 0.25, linewidth = 0.4,
    color = "gray30"
  ) +
  geom_vline(xintercept = 7.5,          # between 2019 (pos 7) and 2022 (pos 8)
             linetype = "dashed", color = "gray40", alpha = .8) +
  annotate("text", x = 7.7, y = Inf, label = "Law 13.811/2019",
           hjust = 0, vjust = 1.4, size = 2.6, color = "gray30") +
  scale_fill_manual(values = cores_rural_urb, name = NULL) +
  scale_y_continuous(labels = label_number(suffix = "%", accuracy = .1),
                     expand = expansion(mult = c(0, .08))) +
  labs(x = NULL, y = "Prevalence (% of conjugal households)") +
  theme_pub

ggsave(file.path(PUB_DIR, "rural_urbano.png"), econ3_pub,
       width = 22, height = 12, units = "cm", dpi = 300, bg = "white")
message("ECON 3 (bar chart) salva.")

# =============================================================================
# AGE GAP — Distribution of age gap (bar chart + mean check)
# =============================================================================
# Spec: gráfico de barras com labels xx.xx%; verificação da média no console.
# Nota: usa geom_col; verificação impressa no console.
# LaTeX note: Source: PNADC (visit 1, IBGE), survey-weighted. Distribution of
#   age gap between household head (≥18) and minor spouse (<18) in Category C
#   households. Pooled 2012–2023.

# Verificação da média (Maria Cruz: "Observar se a média está correta")
mean_gap_check <- age_gap_dist |>
  filter(!is.na(dif_idade)) |>
  summarise(
    mean_gap     = sum(dif_idade * n_ponderado, na.rm = TRUE) / sum(n_ponderado, na.rm = TRUE),
    median_approx = dif_idade[cumsum(pct) >= .5][1]
  )
message(sprintf(
  "Age gap check — Mean: %.2f years | Median (approx): %d years  (expected ~8 years mean)",
  mean_gap_check$mean_gap, mean_gap_check$median_approx
))

# Labels apenas nas barras mais altas (evita poluição)
lbl_gap <- age_gap_dist |>
  filter(!is.na(dif_idade), dif_idade <= 30, pct >= .025)

fig_age_gap_pub <- age_gap_dist |>
  filter(!is.na(dif_idade), dif_idade <= 30) |>
  ggplot(aes(x = dif_idade, y = pct)) +
  geom_col(fill = COL_BAR_MAIN, alpha = .88, width = .85) +
  geom_vline(xintercept = mean_gap_check$mean_gap,
             linetype = "dashed", colour = COL_REF, linewidth = 0.8) +
  annotate("text",
           x     = mean_gap_check$mean_gap + .4,
           y     = max(age_gap_dist$pct, na.rm = TRUE) * .92,
           label = sprintf("Mean: %.1f yrs", mean_gap_check$mean_gap),
           hjust = 0, size = 3, colour = "gray30") +
  geom_text(data = lbl_gap,
            aes(label = sprintf("%.1f%%", pct * 100)),
            vjust = -0.5, size = 2.5, colour = "gray25") +
  scale_x_continuous(breaks = seq(0, 30, 5)) +
  scale_y_continuous(labels = label_percent(accuracy = .1),
                     expand = expansion(mult = c(0, .08))) +
  labs(x = "Age gap (years)", y = "Share of households (%)") +
  theme_pub

ggsave(file.path(PUB_DIR, "age_gap.png"), fig_age_gap_pub,
       width = 18, height = 11, units = "cm", dpi = 300, bg = "white")
message("Age gap (bar chart) salva.")

# =============================================================================
# ECON 7 — NEET, school and work (minor spouses, Cat. C)
# =============================================================================
# Spec: sem título/subtítulo, em inglês, data labels em todos os pontos.
# LaTeX note: Source: PNADC (visit 1, IBGE), survey-weighted. Rates among
#   conjugal households classified as Category C (adult head, minor spouse).
#   NEET = not in employment, education or training. Dashed lines: 2019.

lbl_econ7 <- neet_proxy |>
  filter(categ_domic == "C") |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  pivot_longer(c(taxa_neet, taxa_escola, taxa_trab),
               names_to = "indicador", values_to = "taxa") |>
  filter(Ano %in% LABEL_ANOS | Ano == max(Ano))

econ7_pub <- neet_proxy |>
  filter(categ_domic == "C") |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  pivot_longer(c(taxa_neet, taxa_escola, taxa_trab),
               names_to = "indicador", values_to = "taxa") |>
  mutate(indicador = recode(indicador,
    taxa_neet   = "NEET (neither working nor studying)",
    taxa_escola = "Attending school",
    taxa_trab   = "Paid employment"
  )) |>
  ggplot(aes(x = Ano, y = taxa,
             colour = indicador, linetype = indicador, group = indicador)) +
  geom_vline(xintercept = 2019, linetype = "dashed", colour = COL_REF) +
  geom_line(linewidth = 0.8) + geom_point(size = 1.8) +
  geom_text_repel(
    data = lbl_econ7 |>
      mutate(indicador = recode(indicador,
        taxa_neet   = "NEET (neither working nor studying)",
        taxa_escola = "Attending school",
        taxa_trab   = "Paid employment"
      )),
    aes(label = sprintf("%.1f%%", taxa * 100)),
    size = 2.5, show.legend = FALSE, min.segment.length = .3
  ) +
  scale_colour_manual(
    values = c("NEET (neither working nor studying)" = "#B22222",
               "Attending school"                    = "#1A5276",
               "Paid employment"                     = "#1D7C4D"),
    name = NULL
  ) +
  scale_linetype_manual(
    values = c("NEET (neither working nor studying)" = "solid",
               "Attending school"                    = "dashed",
               "Paid employment"                     = "dotdash"),
    name = NULL
  ) +
  scale_x_continuous(breaks = c(2012, 2015, 2019, 2022, 2023)) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(x = NULL, y = "Rate (%)") +
  theme_pub

ggsave(file.path(PUB_DIR, "neet.png"), econ7_pub,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")
message("ECON 7 salva.")

# =============================================================================
# EDUC A — School attendance over time (existing, paper-ready)
# =============================================================================
# LaTeX note: Source: PNADC (2nd quarter, IBGE), weighted means.
#   Share attending school: minor spouses (Category C) vs. same-age
#   daughters/relatives (14–17). Dashed line: Lei 13.811/2019.

educ_8_1a <- educ_vars |>
  filter(!is.na(freq_esc_bin)) |>
  group_by(Ano, grupo_educ) |>
  summarise(taxa_freq = wt_mean(freq_esc_bin, peso), n_obs = n(), .groups = "drop")

educ_A_pub <- local({
  df <- educ_8_1a |>
    mutate(
      Ano_int     = as.integer(as.character(Ano)),
      grupo_label = recode(grupo_educ,
        "Cônjuge < 18"        = "Minor spouse",
        "Filho/parente 14–17" = "Daughter/relative 14–17")
    )
  anos_seq <- sort(unique(df$Ano_int))
  law_pos  <- which(anos_seq == 2019L) + 0.5   # vertical line between 2018 and 2019 bars

  ggplot(df, aes(x = factor(Ano_int), y = taxa_freq, fill = grupo_label)) +
    geom_vline(xintercept = law_pos, linetype = "dashed",
               colour = COL_REF, linewidth = 0.6) +
    geom_col(position = position_dodge(width = 0.8), width = 0.75) +
    geom_text(aes(label = sprintf("%.1f%%", taxa_freq * 100)),
              position = position_dodge(width = 0.8),
              vjust = -0.35, size = 2.2, colour = "gray20") +
    scale_fill_manual(
      values = c("Minor spouse"             = COL_BAR_A,
                 "Daughter/relative 14–17" = COL_BAR_B),
      name = NULL
    ) +
    scale_y_continuous(labels = label_percent(accuracy = 1),
                       limits = c(0, 1.08),
                       expand = expansion(mult = c(0, 0))) +
    labs(x = NULL, y = "School attendance rate (%)") +
    theme_pub +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8))
})

ggsave(file.path(PUB_DIR, "freq_escolar.png"), educ_A_pub,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")
message("EDUC A salva.")

# =============================================================================
# EDUC C — Education level composition (bar chart)
# =============================================================================
# LaTeX note: Source: PNADC (2nd quarter, IBGE), weighted means. Distribution
#   of education level attended among those currently enrolled, pooled 2012–2023.
#   EJA = Educação de Jovens e Adultos (adult education program).

educ_8_1d_pooled <- educ_vars |>
  filter(freq_esc_bin == 1L, !is.na(grupo_educ), !is.na(curso_freq)) |>
  mutate(
    nivel_simpl = case_when(
      str_detect(as.character(curso_freq), "(?i)EJA|supletivo|jovens e adultos") ~ "Adult ed. (EJA)",
      str_detect(as.character(curso_freq), "(?i)fundamental") ~ "Lower secondary",
      str_detect(as.character(curso_freq), "(?i)médio|medio")  ~ "Upper secondary",
      str_detect(as.character(curso_freq), "(?i)superior")     ~ "Higher ed.",
      TRUE ~ "Other"
    )
  ) |>
  group_by(grupo_educ, nivel_simpl) |>
  summarise(n_pond = sum(peso, na.rm = TRUE), .groups = "drop") |>
  group_by(grupo_educ) |>
  mutate(prop = n_pond / sum(n_pond),
         nivel_simpl = factor(nivel_simpl,
           levels = c("Lower secondary","Adult ed. (EJA)",
                      "Upper secondary","Higher ed.","Other")),
         grupo_label = recode(grupo_educ,
           "Cônjuge < 18"        = "Minor spouse",
           "Filho/parente 14–17" = "Daughter/relative 14–17")) |>
  ungroup()

educ_C_pub <- educ_8_1d_pooled |>
  ggplot(aes(x = grupo_label, y = prop, fill = nivel_simpl)) +
  geom_col(position = "fill", width = .6) +
  geom_text(aes(label = ifelse(prop >= .03, sprintf("%.1f%%", prop * 100), "")),
            position = position_fill(vjust = .5),
            size = 2.7, color = "white", fontface = "bold") +
  coord_flip() +
  scale_fill_manual(
    values = c(
      "Lower secondary"  = "#3690C0",
      "Adult ed. (EJA)"  = "#B22222",
      "Upper secondary"  = "#253494",
      "Higher ed."       = "#081D58",
      "Other"            = "#878787"
    ),
    name = "Education level"
  ) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(x = NULL, y = "Share (%)") +
  theme_pub + theme(legend.position = "right")

ggsave(file.path(PUB_DIR, "nivel_ensino.png"), educ_C_pub,
       width = 20, height = 10, units = "cm", dpi = 300, bg = "white")
message("EDUC C salva.")

# =============================================================================
# LM 1 — Labor force participation (new control group: daughters/relatives)
# =============================================================================
# LaTeX note: Source: PNADC (visit 1, IBGE), weighted means. Share with paid
#   employment. Treatment: minor spouses (Cat. C). Control: same-age
#   daughters/relatives aged 14–17. Dashed line: Lei 13.811/2019.

lm1_df <- lm1_margens |>
  filter(!is.na(grupo_lm)) |>
  mutate(
    Ano = as.integer(as.character(Ano)),
    grupo_label = recode(as.character(grupo_lm),
      "Cônjuge < 18"        = "Minor spouse",
      "Filha/parente 14–17" = "Daughter/relative 14–17")
  )

lbl_lm1 <- lm1_df |>
  filter(Ano %in% LABEL_ANOS | Ano == max(Ano))

lm1_pub <- lm1_df |>
  ggplot(aes(x = Ano, y = taxa_participacao,
             colour = grupo_label, linetype = grupo_label, group = grupo_label)) +
  geom_vline(xintercept = 2019, linetype = "dashed", colour = COL_REF) +
  geom_line(linewidth = 0.8) + geom_point(size = 1.8) +
  geom_text_repel(data = lbl_lm1,
                  aes(label = sprintf("%.1f%%", taxa_participacao * 100)),
                  size = 2.5, show.legend = FALSE, min.segment.length = .3) +
  scale_colour_manual(
    values = c("Minor spouse"             = COL_TREAT,
               "Daughter/relative 14–17" = COL_CONTROL),
    name = NULL
  ) +
  scale_linetype_manual(values = lt_group_en, name = NULL) +
  scale_x_continuous(breaks = anos_breaks) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(x = NULL, y = "Labour force participation rate (%)") +
  theme_pub

ggsave(file.path(PUB_DIR, "lm_participacao.png"), lm1_pub,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")
message("LM 1 salva.")

# =============================================================================
# FIGURA NOVA — Child unions per 10,000 minors (RC formal + PNADC informal)
# =============================================================================
# Requested: "casamento por 10 mil menores"
# LaTeX note: Source: IBGE (Civil Registry Statistics and PNADC visit 1).
#   Numerator — Civil Registry: formally registered marriages with at least
#   one spouse under 18. PNADC: survey-weighted count of conjugal households
#   with a minor spouse (stock). Denominator: IBGE population projections,
#   age group 10–17 (Revisão 2018); verify exact values at ibge.gov.br.
#   Dashed line: Lei 13.811/2019.

# Population 10–17 — derived from pop_menores.xlsx (IBGE state-level estimates).
# Columns used: "10 a 14 anos" + "15 anos" + "16 anos" + "17 anos", summed
# across all 27 UFs to obtain the national total.
# 2023: linearly extrapolated from the 2021→2022 trend (file ends at 2022).
pop_file <- here("PIBIC",
                 "Iniciação Científica - Registro Civil",
                 "pop_menores.xlsx")

pop_nacional <- readxl::read_excel(pop_file, sheet = "Tabela") |>
  filter(!is.na(ano), !is.na(uf)) |>
  mutate(
    ano       = as.integer(ano),
    pop_10_17 = as.numeric(`10 a 14 anos`) +
                as.numeric(`15 anos`)      +
                as.numeric(`16 anos`)      +
                as.numeric(`17 anos`)
  ) |>
  group_by(ano) |>
  summarise(pop_10_17 = sum(pop_10_17, na.rm = TRUE), .groups = "drop")

# Extrapolate 2023 (linear projection from last two observed years)
delta_pop <- with(pop_nacional,
                  pop_10_17[ano == 2022] - pop_10_17[ano == 2021])
pop_nacional <- bind_rows(
  pop_nacional,
  tibble(ano = 2023L, pop_10_17 = pop_nacional$pop_10_17[pop_nacional$ano == 2022] + delta_pop)
)
message(sprintf(
  "pop_menores: anos %d–%d carregados; 2023 extrapolado (%.0f menores, 10–17 anos).",
  min(pop_nacional$ano), 2022L,
  pop_nacional$pop_10_17[pop_nacional$ano == 2023]
))

# RC rate: formally registered child marriages (flow) per 10,000 minors (10–17).
# NOTE: the PNADC stock measure is deliberately excluded — it counts conjugal
# households at survey date (stock), which is not comparable to the RC annual
# flow on the same rate scale.
rc_rate_10k <- rc_flow |>
  left_join(pop_nacional, by = "ano") |>
  mutate(rate_per_10k = flow / pop_10_17 * 10000) |>
  filter(!is.na(pop_10_17)) |>
  select(ano, rate_per_10k)

lbl_rate <- rc_rate_10k |>
  filter(ano %in% c(2003, 2006, 2012, 2015, 2019, 2022) | ano == max(ano))

fig_rate_10k_pub <- rc_rate_10k |>
  ggplot(aes(x = ano, y = rate_per_10k)) +
  geom_line(colour = COL_MAIN, linewidth = 0.8) +
  geom_point(colour = COL_MAIN, size = 1.8) +
  geom_vline(xintercept = 2019, linetype = "dashed", colour = COL_REF) +
  annotate("text", x = 2019.2, y = max(rc_rate_10k$rate_per_10k, na.rm = TRUE) * .96,
           label = "Lei 13.811/2019", hjust = 0, size = 2.8, colour = "gray40") +
  geom_text_repel(data = lbl_rate,
                  aes(label = sprintf("%.1f", rate_per_10k)),
                  size               = 2.8,
                  nudge_y            = 1.5,
                  nudge_x            = 0.3,
                  direction          = "y",
                  segment.colour     = "gray55",
                  segment.size       = 0.3,
                  min.segment.length = 0,
                  show.legend = FALSE) +
  scale_x_continuous(breaks = seq(2003, 2022, 3)) +
  scale_y_continuous(expand = expansion(mult = c(.02, .12))) +
  labs(x = NULL,
       y = "Formally registered child marriages per 10,000 minors (age 10–17)") +
  theme_pub

ggsave(file.path(PUB_DIR, "rate_per_10k.png"), fig_rate_10k_pub,
       width = 22, height = 12, units = "cm", dpi = 300, bg = "white")
message("Rate per 10,000 minors salva.")

# =============================================================================
# AGE GAP — Pre-2019 and Post-2019 distributions (separate bar charts)
# =============================================================================
# Requested: "distribuição de age gap antes de 2019" +
#            "distribuição de age gap depois de 2019"
# age_gap_periodo already computed in Fase 1 (loading section).
# LaTeX note: Source: PNADC (visit 1, IBGE), survey-weighted. Distribution of
#   age gap between the household head (≥18) and the minor spouse (<18) in
#   Category C households. Before 2019: years 2012–2018. 2019+: 2019, 2022–2023.
#   Dashed line: weighted mean.

# Weighted mean per period (for vertical dashed line annotation)
means_gap_periodo <- age_gap_periodo |>
  distinct(periodo, mean_gap)

# Only label bars >= 2.5% to avoid clutter
lbl_gap_periodo <- age_gap_periodo |>
  filter(pct >= .025, dif_idade <= 30)

message(sprintf("Age gap means — Before 2019: %.2f yrs | 2019+: %.2f yrs",
  means_gap_periodo$mean_gap[means_gap_periodo$periodo == "Before 2019 (2012–2018)"],
  means_gap_periodo$mean_gap[means_gap_periodo$periodo == "2019 and after"]
))

# Faceted bar chart: age gap before vs. after 2019, side by side.
# geom_vline and geom_text with the faceting variable in their data frames
# are drawn independently per panel — no annotate() needed.

# y_top per period — used to position the mean label inside each panel
means_lbl <- means_gap_periodo |>
  left_join(
    age_gap_periodo |>
      filter(dif_idade <= 30) |>
      group_by(periodo) |>
      summarise(y_top = max(pct, na.rm = TRUE), .groups = "drop"),
    by = "periodo"
  ) |>
  mutate(
    x_lbl = mean_gap + 0.4,
    y_lbl = y_top * 0.91,
    lbl   = sprintf("Mean: %.1f yrs", mean_gap)
  )

fig_gap_periodos_pub <- age_gap_periodo |>
  filter(dif_idade <= 30) |>
  ggplot(aes(x = dif_idade, y = pct)) +
  geom_col(fill = COL_BAR_MAIN, alpha = .88, width = .85) +
  # Per-panel mean line (data must carry the faceting variable)
  geom_vline(data = means_gap_periodo,
             aes(xintercept = mean_gap),
             linetype = "dashed", colour = COL_REF, linewidth = 0.8) +
  # Per-panel mean annotation
  geom_text(data = means_lbl,
            aes(x = x_lbl, y = y_lbl, label = lbl),
            hjust = 0, size = 3, colour = "gray30",
            inherit.aes = FALSE) +
  # Bar-level labels (pct >= 2.5%)
  geom_text(data = lbl_gap_periodo |> filter(dif_idade <= 30),
            aes(label = sprintf("%.1f%%", pct * 100)),
            vjust = -0.45, size = 2.5, colour = "gray25") +
  facet_wrap(~ periodo, ncol = 2, scales = "free_y") +
  scale_x_continuous(breaks = seq(0, 30, 5)) +
  scale_y_continuous(labels = label_percent(accuracy = .1),
                     expand = expansion(mult = c(0, .18))) +
  labs(x = "Age gap (years)", y = "Share of households (%)") +
  theme_pub

ggsave(file.path(PUB_DIR, "age_gap_periodos.png"), fig_gap_periodos_pub,
       width = 26, height = 12, units = "cm", dpi = 300, bg = "white")
message("Age gap pre/post-2019 (faceted) salva.")

# =============================================================================
# CDF DE IDADE DO CÔNJUGE MENOR — antes vs. depois de 2019
# =============================================================================
# Cada ponto (x, y) do gráfico responde: qual a proporção acumulada de cônjuges
# menores com idade ≤ x anos?
# Interpretação: se a lei reduziu casamentos com menores muito jovens (10–13),
# a curva pós-2019 estará deslocada para a direita (peso maior em idades mais
# altas dentro do grupo < 18).
# Nota: idade_conjuge pode ser NULL se V2009 estiver renomeado no cache.

if (!is.null(idade_conjuge)) {

  # Labels only where cumulative share >= 0.3 % (avoids cluttering near-zero steps)
  lbl_cdf <- idade_conjuge |>
    filter(cdf >= 0.003) |>
    # preserve factor order for the facet
    mutate(periodo = factor(periodo,
                            levels = c("Before 2019 (2012–2018)", "2019 and after")))

  # Colour constants for the legal-threshold annotations
  COL_EXCEP <- "#C85B1A"   # burnt orange — exception zone / threshold line

  fig_cdf_idade_pub <- idade_conjuge |>
    # Fix panel order: Before 2019 on the left
    mutate(periodo = factor(periodo,
                            levels = c("Before 2019 (2012–2018)", "2019 and after"))) |>
    ggplot(aes(x = idade, y = cdf)) +

    # ── Background zones ──────────────────────────────────────────────────────
    # Salmon zone: ages where exceptions existed (< 16 pre-2019)
    annotate("rect",
             xmin = 9.5, xmax = 16, ymin = 0, ymax = Inf,
             fill = "#FCE4D0", alpha = 0.55) +
    # Blue zone: ages ≥ 16 (above parental-consent threshold)
    annotate("rect",
             xmin = 16, xmax = 17.8, ymin = 0, ymax = Inf,
             fill = "#D6E8F5", alpha = 0.55) +

    # ── "Exception zone" label (top of salmon region) ─────────────────────────
    annotate("text",
             x = 12.75, y = 0.92,
             label = "Exception zone", hjust = 0.5, size = 3,
             colour = COL_EXCEP, fontface = "italic") +

    # ── Step function ─────────────────────────────────────────────────────────
    geom_step(colour = COL_MAIN, linewidth = 0.9, direction = "hv") +
    geom_point(colour = COL_MAIN, size = 2) +

    # ── Age-16 parental-consent threshold line ────────────────────────────────
    geom_vline(xintercept = 16, linetype = "dashed",
               colour = COL_EXCEP, linewidth = 0.75) +
    annotate("text",
             x = 16.10, y = 0.55,
             label = "Age 16\n(parental consent\nthreshold)",
             hjust = 0, vjust = 0.5, size = 2.6, colour = COL_EXCEP) +

    # ── CDF labels — positioned BELOW each step point ─────────────────────────
    geom_text(data = lbl_cdf,
              aes(label = sprintf("%.1f%%", cdf * 100)),
              hjust = 0.5, vjust = 1.7, size = 2.5, colour = "gray25") +

    facet_wrap(~ periodo, ncol = 2) +
    scale_x_continuous(breaks = 10:17,
                       expand = expansion(mult = c(0.03, 0.14))) +
    scale_y_continuous(labels = label_percent(accuracy = 1),
                       breaks = seq(0, 1, .2),
                       limits = c(0, 1.08)) +
    labs(x = "Age of minor spouse (years)",
         y = "Cumulative share (%)") +
    theme_pub +
    theme(panel.background = element_rect(fill = "white", colour = NA))

  ggsave(file.path(PUB_DIR, "cdf_idade_conjuge.png"),
         fig_cdf_idade_pub,
         width = 26, height = 12, units = "cm", dpi = 300, bg = "white")
  message("CDF de idade do cônjuge menor (faceted) salva.")

  # ── Versão overlay: ambos os períodos no mesmo painel ────────────────────────
  # geom_ribbon preenche a área sob a curva pré-2019 (interpolação linear entre
  # os inteiros de idade — idêntico ao sombreamento da imagem de referência).
  pre2019_ribbon <- idade_conjuge |>
    filter(periodo == "Before 2019 (2012–2018)")

  # Legend labels curtos, estilo da imagem de referência
  lbl_periodos <- c("Before 2019 (2012–2018)" = "Informal – Pre-2019",
                    "2019 and after"           = "Informal – Post-2019")

  fig_cdf_overlay_pub <- idade_conjuge |>
    mutate(periodo = factor(periodo,
                            levels = c("Before 2019 (2012–2018)", "2019 and after"))) |>
    ggplot(aes(x = idade, y = cdf,
               colour = periodo, linetype = periodo, group = periodo)) +

    # Shaded fill under Pre-2019 curve
    geom_ribbon(data    = pre2019_ribbon,
                aes(x = idade, ymin = 0, ymax = cdf, group = 1),
                fill    = COL_MAIN, alpha = 0.12,
                colour  = NA, inherit.aes = FALSE) +

    # Step curves for both periods
    geom_step(linewidth = 0.9, direction = "hv") +
    geom_point(size = 2) +

    # Age-16 parental-consent threshold
    geom_vline(xintercept = 16, linetype = "dashed",
               colour = "gray50", linewidth = 0.75) +
    annotate("text", x = 16.10, y = 0.08,
             label = "Age 16", hjust = 0, size = 2.8, colour = "gray40") +

    scale_colour_manual(
      values = c("Before 2019 (2012–2018)" = COL_MAIN,
                 "2019 and after"           = COL_TREAT),
      labels = lbl_periodos, name = NULL
    ) +
    scale_linetype_manual(
      values = c("Before 2019 (2012–2018)" = "solid",
                 "2019 and after"           = "dashed"),
      labels = lbl_periodos, name = NULL
    ) +
    scale_x_continuous(breaks = 10:17,
                       expand = expansion(mult = c(0.03, 0.10))) +
    scale_y_continuous(labels = label_percent(accuracy = 1),
                       breaks = seq(0, 1, .2),
                       limits = c(0, 1.08)) +
    labs(x = "Age of underage spouse",
         y = "Cumulative share of minor spouses (%)") +
    theme_pub +
    theme(legend.position = "top",
          legend.key.width = unit(1.2, "cm"))

  ggsave(file.path(PUB_DIR, "cdf_overlay.png"),
         fig_cdf_overlay_pub,
         width = 18, height = 12, units = "cm", dpi = 300, bg = "white")
  message("CDF de idade do cônjuge menor (overlay) salva.")

} else {
  message("AVISO: fig_cdf_idade_conjuge não gerada (idade_conjuge é NULL).")
  message("  Corrija o nome da coluna de idade no bloco de extração da Fase 1.")
}

# =============================================================================
# ESTATÍSTICAS CHAVE PARA A INTRODUÇÃO (RC)
# =============================================================================
# Imprime na console os valores para preencher os XX no texto do paper.
# Colunas usadas: is_minor_w (pré-calculado), idade_m, n_total_row, n_h_minor.

rc_stats_intro <- rc_raw |>
  mutate(
    under16_w = idade_m %in% c("Menos de 15 anos", "15 anos"),
    under16_h = rowSums(across(any_of(c("h_men15", "h_15"))), na.rm = TRUE)
  ) |>
  group_by(ano) |>
  summarise(
    total_marriages      = sum(n_total_row,              na.rm = TRUE),
    child_marriages      = sum(n_total_row[is_minor_w],  na.rm = TRUE),
    child_under16_w      = sum(n_total_row[under16_w],   na.rm = TRUE),
    child_under16_h_adw  = sum(under16_h[!is_minor_w],  na.rm = TRUE),
    minor_female         = sum(n_total_row[is_minor_w],  na.rm = TRUE),
    minor_male           = sum(n_h_minor,                na.rm = TRUE),
    .groups = "drop"
  ) |>
  left_join(pop_nacional, by = "ano") |>
  mutate(
    child_under16_total  = child_under16_w + child_under16_h_adw,
    pct_under16          = child_under16_total / child_marriages   * 100,
    pct_under16_of_total = child_under16_total / total_marriages   * 100,
    rate_per_1k         = child_marriages / pop_10_17 * 1e3,
    rate_per_10k        = child_marriages / pop_10_17 * 1e4,
    total_minor_spouses = minor_female + minor_male,
    pct_female          = minor_female / total_minor_spouses * 100
  )

cat("\n=== Estatísticas RC para Introdução ===\n")
with(rc_stats_intro |> filter(ano == 2022), {
  cat(sprintf("  Casamentos infantis (2022):         %d\n",  child_marriages))
  cat(sprintf("  Por mil menores 10-17 (2022):       %.2f\n", rate_per_1k))
  cat(sprintf("  Por 10 mil menores 10-17 (2022):    %.2f\n", rate_per_10k))
  cat(sprintf("  Cônjuge < 16 (2022):                %.0f\n",
              child_under16_total))
  cat(sprintf("    %% dos casamentos infantis:        %.2f%%\n", pct_under16))
  cat(sprintf("    %% do total de casamentos (2022):  %.4f%%\n", pct_under16_of_total))
  cat(sprintf("  Total de casamentos (2022):         %d\n",      total_marriages))
})
cat(sprintf("  %% cônjuges menores femininos (média 2003-2022): %.1f%%\n",
            mean(rc_stats_intro$pct_female, na.rm = TRUE)))
cat(sprintf("  Variação 2003 -> 2022: %+.1f pp\n",
            rc_stats_intro$pct_female[rc_stats_intro$ano == 2022] -
            rc_stats_intro$pct_female[rc_stats_intro$ano == 2003]))

# Composição etária das cônjuges menores femininas (pooled 2003–2022)
rc_age_breakdown <- rc_raw |>
  filter(is_minor_w) |>
  mutate(idade_cat = case_when(
    idade_m == "Menos de 15 anos" ~ "<=14",
    idade_m == "15 anos"          ~ "15",
    idade_m == "16 anos"          ~ "16",
    idade_m == "17 anos"          ~ "17",
    TRUE                          ~ NA_character_
  )) |>
  filter(!is.na(idade_cat)) |>
  group_by(idade_cat) |>
  summarise(n = sum(n_total_row, na.rm = TRUE), .groups = "drop") |>
  mutate(pct = n / sum(n) * 100,
         idade_cat = factor(idade_cat, levels = c("<=14","15","16","17"))) |>
  arrange(idade_cat)

cat("\n  Composição etária cônjuges menores femininas (pooled 2003-2022):\n")
print(rc_age_breakdown)
message("Estatísticas RC para introdução impressas.")

# =============================================================================
# SUBREGISTRO: estoque RC sintético vs estoque PNADC
# =============================================================================
# Abordagem correta: comparar dois ESTOQUES (não fluxo vs estoque).
#
# RC stock sintético no ano y = soma dos fluxos de (y - max_gap + 1) até y.
#   max_gap = 4: uma noiva de 14 anos (mínimo no RC) permanece menor por 4
#   anos → esse é o limite máximo de contribuição de cada casamento ao estoque.
#   É uma estimativa CONSERVADORA (limite inferior do estoque formal).
#
# PNADC stock = domicílios conjugais com cônjuge < 18 observados na pesquisa
#   (captura formal + informal).
#
# ratio           = PNADC_stock / RC_stock
#                 → para cada união formal com menor, quantas existem no total
# underreport_pct = 1 - RC_stock / PNADC_stock
#                 → % das uniões com menores nunca registradas em cartório

# Contribuição de cada faixa etária: anos restantes até completar 18
# "Menos de 15 anos" → noiva de 14 → ainda menor por 4 anos
# "15 anos"          → ainda menor por 3 anos
# "16 anos"          → ainda menor por 2 anos
# "17 anos"          → ainda menor por 1 ano
ANOS_CONTRIB <- c(
  "Menos de 15 anos" = 4L,
  "15 anos"          = 3L,
  "16 anos"          = 2L,
  "17 anos"          = 1L
)

# Fluxo anual por faixa etária da noiva (usando rc_raw diretamente)
rc_flow_by_age <- rc_raw |>
  filter(is_minor_w) |>
  mutate(anos_contrib = ANOS_CONTRIB[as.character(idade_m)]) |>
  filter(!is.na(anos_contrib)) |>
  group_by(ano, anos_contrib) |>
  summarise(flow_faixa = sum(n_total_row, na.rm = TRUE), .groups = "drop")

# Estoque ponderado no ano y = soma dos casamentos do ano t cujo cônjuge
# menor ainda seria menor em y, i.e., t <= y E t + anos_contrib > y
build_rc_stock_weighted <- function(flow_age_df) {
  anos_ref <- sort(unique(flow_age_df$ano))
  purrr::map_dfr(anos_ref, function(y) {
    tibble(
      ano      = y,
      rc_stock = flow_age_df |>
        filter(ano <= y, ano + anos_contrib > y) |>
        summarise(s = sum(flow_faixa, na.rm = TRUE)) |>
        pull(s)
    )
  })
}

rc_stock <- build_rc_stock_weighted(rc_flow_by_age)

pnadc_stock <- early_annual |>
  mutate(ano = as.integer(as.character(Ano))) |>
  select(ano,
         pnadc_stock    = total_early,
         pnadc_stock_se = total_early_se,
         pnadc_ci_low   = ci_low,
         pnadc_ci_high  = ci_high)

underrep_df <- inner_join(rc_stock, pnadc_stock, by = "ano") |>
  left_join(rc_flow, by = "ano") |>           # adiciona fluxo anual para daily
  mutate(
    ratio           = round(pnadc_stock / rc_stock, 1),
    underreport_pct = round((1 - rc_stock / pnadc_stock) * 100, 1),
    daily_pnadc     = round(pnadc_stock / 365, 1),
    daily_rc_new    = round(flow        / 365, 1)
  ) |>
  select(ano, rc_stock, pnadc_stock, ratio, underreport_pct,
         daily_pnadc, daily_rc_new)

cat("\n=== Subregistro: RC estoque sintetico vs PNADC estoque ===\n")
cat("  rc_stock        = estoque ponderado por faixa etaria da noiva\n")
cat("  pnadc_stock     = domicilios com conjuge < 18 (formal + informal)\n")
cat("  ratio           = pnadc / rc  (para cada uniao formal, quantas existem)\n")
cat("  underreport_pct = % das unioes nao registradas no cartorio\n")
cat("  daily_pnadc     = estoque PNADC por dia\n")
cat("  daily_rc_new    = novos casamentos RC por dia\n\n")
print(underrep_df)
message("Comparacao de subregistro (estoque vs estoque) impressa.")

# =============================================================================
# =============================================================================
# FIGURA — Prevalência de estoque: RC stock / RC total stock vs PNADC stock / total conjugal
# =============================================================================
# Ambas as séries expressas como proporção do seu próprio denominador de estoque.
#   RC:    rc_stock_child / rc_stock_total
#   PNADC: pnadc_stock    / n_conjugal
#
# Para o total de casamentos RC usamos uma janela deslizante de ADULT_WINDOW anos
# (duração média aproximada de um casamento no Brasil). Isso converte o fluxo
# total do RC num estoque acumulado comparável ao denominador da PNADC.
# Sensibilidade: janelas de 10, 15 e 20 anos produzem resultados muito próximos
# porque o numerador (child stock, 4 anos) escala proporcionalmente.

ADULT_WINDOW <- 15L   # anos de duração média de um casamento — ajuste se necessário

rc_total_flow <- rc_raw |>
  group_by(ano) |>
  summarise(flow_total = sum(n_total_row, na.rm = TRUE), .groups = "drop")

rc_stock_total <- purrr::map_dfr(sort(rc_total_flow$ano), function(y) {
  tibble(
    ano            = y,
    rc_stock_total = sum(
      rc_total_flow$flow_total[
        rc_total_flow$ano >= y - ADULT_WINDOW + 1L &
        rc_total_flow$ano <= y
      ],
      na.rm = TRUE
    )
  )
})

prev_rc_stock <- inner_join(rc_stock, rc_stock_total, by = "ano") |>
  mutate(pct_rc = rc_stock / rc_stock_total * 100)

prev_pnadc <- pnadc_stock |>
  left_join(total_conjugal_yr |> rename(ano = Ano_int), by = "ano") |>
  filter(!is.na(n_conjugal)) |>
  mutate(pct_pnadc = pnadc_stock / n_conjugal * 100)

prev_combined <- inner_join(
  prev_rc_stock    |> select(ano, pct_rc),
  prev_pnadc       |> select(ano, pct_pnadc),
  by = "ano"
) |>
  pivot_longer(c(pct_rc, pct_pnadc),
               names_to = "source", values_to = "pct") |>
  mutate(source = recode(source,
    "pct_rc"    = "Civil Registry (stock-based)",
    "pct_pnadc" = "PNADC (share of conjugal HH)"))

lbl_prev <- prev_combined |>
  filter(ano %in% c(2012, 2015, 2019, max(ano)))

fig_prev_stock <- prev_combined |>
  ggplot(aes(x = ano, y = pct,
             colour = source, linetype = source, group = source)) +
  geom_vline(xintercept = 2019, linetype = "dashed",
             colour = COL_REF, linewidth = 0.5) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.8) +
  geom_text_repel(
    data        = lbl_prev,
    aes(label   = sprintf("%.2f%%", pct)),
    size        = 2.5,
    show.legend = FALSE,
    min.segment.length = 0.3
  ) +
  scale_colour_manual(
    values = c("Civil Registry (stock-based)"  = COL_CONTROL,
               "PNADC (share of conjugal HH)"  = COL_TREAT),
    name = NULL
  ) +
  scale_linetype_manual(
    values = c("Civil Registry (stock-based)"  = "dashed",
               "PNADC (share of conjugal HH)"  = "solid"),
    name = NULL
  ) +
  scale_x_continuous(breaks = c(2012:2019, 2022, 2023)) +
  scale_y_continuous(
    labels = label_number(suffix = "%", accuracy = 0.01),
    limits = c(0, NA),
    expand = expansion(mult = c(0, 0.08))
  ) +
  labs(x = NULL, y = "Share (%)") +
  theme_pub +
  theme(legend.position  = "bottom",
        legend.key.width = unit(1.2, "cm"))

ggsave(file.path(PUB_DIR, "prev_stock_comparison.png"), fig_prev_stock,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")
message("Prevalência de estoque (RC vs PNADC) salva.")

# FIGURA — Subregistro: RC estoque sintético
# =============================================================================
# Ambas as séries são expressas como proporção do total de domicílios
# conjugais (total_conjugal_yr), tornando-as diretamente comparáveis.
# A diferença vertical entre as curvas representa as uniões informais.
# LaTeX note: Source: IBGE (Civil Registry Statistics and PNADC, visit 1).
#   RC synthetic stock: weighted sum of past flows, where each marriage
#   contributes for as many years as the minor spouse remains under 18
#   (4 years for age ≤14, 3 for 15, 2 for 16, 1 for 17).
#   PNADC stock: survey-weighted count of conjugal households with a minor
#   spouse, capturing both formal and informal unions.
#   Both series expressed as a share of total conjugal households (PNADC).
#   The vertical gap represents informal (unregistered) early unions.
#   Dashed vertical line: Lei 13.811/2019.

underrep_plot_df <- underrep_df |>
  left_join(total_conjugal_yr |> rename(ano = Ano_int), by = "ano") |>
  filter(!is.na(n_conjugal)) |>
  mutate(
    pct_rc    = rc_stock    / n_conjugal * 100,
    pct_pnadc = pnadc_stock / n_conjugal * 100
  ) |>
  select(ano, pct_rc, pct_pnadc) |>
  pivot_longer(c(pct_rc, pct_pnadc),
               names_to = "source", values_to = "pct") |>
  mutate(source = recode(source,
    "pct_rc"    = "Formal unions (RC synthetic stock)",
    "pct_pnadc" = "All unions (PNADC stock)"))

LABEL_ANOS_UR <- c(2012, 2015, 2019, 2022)
lbl_underrep <- underrep_plot_df |>
  filter(ano %in% LABEL_ANOS_UR | ano == max(ano))

fig_underreporting <- underrep_plot_df |>
  ggplot(aes(x = ano, y = pct,
             colour = source, linetype = source, group = source)) +
  geom_vline(xintercept = 2019, linetype = "dashed",
             colour = COL_REF, linewidth = 0.5) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.8) +
  geom_text_repel(
    data        = lbl_underrep,
    aes(label   = sprintf("%.2f%%", pct)),
    size        = 2.5,
    show.legend = FALSE,
    min.segment.length = 0.3
  ) +
  scale_colour_manual(
    values = c("All unions (PNADC stock)"          = COL_TREAT,
               "Formal unions (RC synthetic stock)" = COL_CONTROL),
    name = NULL
  ) +
  scale_linetype_manual(
    values = c("All unions (PNADC stock)"          = "solid",
               "Formal unions (RC synthetic stock)" = "dashed"),
    name = NULL
  ) +
  scale_x_continuous(breaks = c(2012:2019, 2022, 2023)) +
  scale_y_continuous(labels = label_number(suffix = "%", accuracy = 0.01),
                     limits = c(0, NA),
                     expand = expansion(mult = c(0, 0.08))) +
  labs(x = NULL, y = "Share of conjugal households (%)") +
  theme_pub +
  theme(legend.position  = "bottom",
        legend.key.width = unit(1.2, "cm"))

ggsave(file.path(PUB_DIR, "underreporting.png"), fig_underreporting,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")
message("Figura de subregistro salva.")

# =============================================================================
# FIGURA — Taxa de formalização: RC stock / PNADC stock ao longo do tempo
# =============================================================================
# Linha única: proporção das uniões com menores que foram formalizadas no RC.
# rc_stock / pnadc_stock × 100 = % das uniões com menores que são formais.
# O complemento (100% - taxa) é a estimativa de subregistro.
# Começa em 2012 (primeiro ano da PNADC); RC stock já completamente
# reconstituído desde 2006 (4 anos após o início do RC em 2003).

formalizacao_df <- underrep_df |>
  filter(!is.na(pnadc_stock), pnadc_stock > 0) |>
  mutate(subregistro = (1 - rc_stock / pnadc_stock) * 100)

lbl_formal <- formalizacao_df |>
  filter(ano %in% c(min(ano), 2015, 2019, max(ano)))

y_min <- floor(min(formalizacao_df$subregistro) / 5) * 5 - 5  # arredonda para baixo em múltiplos de 5

fig_formalizacao <- formalizacao_df |>
  ggplot(aes(x = ano, y = subregistro)) +

  # Área sombreada entre a linha e 100% — representa o gap não registrado
  geom_ribbon(aes(ymin = subregistro, ymax = 100),
              fill = COL_TREAT, alpha = 0.08) +

  # Linha de referência em 100%
  geom_hline(yintercept = 100, linetype = "dotted",
             colour = "gray60", linewidth = 0.4) +

  # Lei 13.811/2019
  geom_vline(xintercept = 2019, linetype = "dashed",
             colour = COL_REF, linewidth = 0.5) +

  # Série principal
  geom_line(colour = COL_MAIN, linewidth = 0.9) +
  geom_point(colour = COL_MAIN, size = 2) +

  # Labels em todos os pontos, alternando direção para evitar sobreposição
  geom_text(
    aes(label = sprintf("%.1f%%", subregistro)),
    vjust   = -0.7,
    size    = 2.4,
    colour  = COL_MAIN
  ) +

  # Anotação da variação total no período
  annotate("text",
           x = 2017, y = y_min + 1,
           label = sprintf("Change: %+.1f pp (2012–2022)",
                           formalizacao_df$subregistro[formalizacao_df$ano == 2022] -
                           formalizacao_df$subregistro[formalizacao_df$ano == 2012]),
           hjust = 0.5, size = 2.8, colour = "gray40", fontface = "italic") +

  scale_x_continuous(breaks = c(2012:2019, 2022, 2023)) +
  scale_y_continuous(
    labels = label_number(suffix = "%", accuracy = 1),
    limits = c(y_min, 100),
    expand = expansion(mult = c(0, 0.01))
  ) +
  labs(x = NULL,
       y = "Unregistered early unions (%)") +
  theme_pub

ggsave(file.path(PUB_DIR, "formalizacao_rate.png"), fig_formalizacao,
       width = 18, height = 12, units = "cm", dpi = 300, bg = "white")
message("Taxa de formalização salva.")

# =============================================================================
# RC — Proporção de casamentos infantis: menina menor vs menino menor
# =============================================================================
# LaTeX note: Source: IBGE, Civil Registry Statistics. Minor wife: marriages
#   where the female spouse is under 18. Minor husband: marriages where the
#   male spouse is under 18 and the female spouse is adult. Dashed line:
#   Lei 13.811/2019.

rc_gender_yr <- rc_raw |>
  group_by(ano) |>
  summarise(
    child_girl = sum(n_total_row[is_minor_w], na.rm = TRUE),
    child_boy  = sum(n_h_minor[!is_minor_w],  na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    total_child = child_girl + child_boy,
    pct_girl    = child_girl / total_child,
    pct_boy     = child_boy  / total_child
  ) |>
  pivot_longer(c(pct_girl, pct_boy),
               names_to = "genero", values_to = "pct") |>
  mutate(genero = recode(genero,
    "pct_girl" = "Minor wife (female)",
    "pct_boy"  = "Minor husband (male)"))

lbl_gender <- rc_gender_yr |>
  filter(ano %in% c(2003, 2010, 2015, 2019, 2022))

fig_rc_gender <- rc_gender_yr |>
  ggplot(aes(x = ano, y = pct,
             colour = genero, linetype = genero, group = genero)) +
  geom_vline(xintercept = 2019, linetype = "dashed",
             colour = COL_REF, linewidth = 0.5) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.8) +
  geom_text_repel(
    data = lbl_gender,
    aes(label = sprintf("%.1f%%", pct * 100)),
    size = 2.5, show.legend = FALSE, min.segment.length = 0.3
  ) +
  scale_colour_manual(
    values = c("Minor wife (female)"  = COL_TREAT,
               "Minor husband (male)" = COL_CONTROL),
    name = NULL
  ) +
  scale_linetype_manual(
    values = c("Minor wife (female)"  = "solid",
               "Minor husband (male)" = "dashed"),
    name = NULL
  ) +
  scale_x_continuous(breaks = seq(2003, 2022, 3)) +
  scale_y_continuous(labels = label_percent(accuracy = 1),
                     limits = c(0, 1),
                     expand = expansion(mult = c(0, 0.03))) +
  labs(x = NULL, y = "Share of child marriages (%)") +
  theme_pub

ggsave(file.path(PUB_DIR, "rc_gender_share.png"), fig_rc_gender,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")
message("RC gender share salva.")

# =============================================================================
# RC — Proporção de casamentos infantis: menina/menino menor — barras empilhadas
# =============================================================================

fig_rc_gender_stacked <- local({
  anos_seq <- sort(unique(rc_gender_yr$ano))
  law_pos  <- which(anos_seq == 2019L) + 0.5

  ggplot(rc_gender_yr,
         aes(x = factor(ano), y = pct, fill = genero)) +
    geom_vline(xintercept = law_pos, linetype = "dashed",
               colour = COL_REF, linewidth = 0.6) +
    geom_col(position = "stack", width = 0.8) +
    geom_text(aes(label = sprintf("%.1f%%", pct * 100)),
              position = position_stack(vjust = 0.5),
              size = 2.4, colour = "white", fontface = "bold") +
    scale_fill_manual(
      values = c("Minor wife (female)"  = COL_BAR_A,
                 "Minor husband (male)" = COL_BAR_B),
      name = NULL
    ) +
    scale_y_continuous(labels = label_percent(accuracy = 1),
                       limits = c(0, 1.01),
                       expand = expansion(mult = c(0, 0))) +
    labs(x = NULL, y = "Share of child marriages (%)") +
    theme_pub +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8))
})

ggsave(file.path(PUB_DIR, "rc_gender_share_stacked.png"), fig_rc_gender_stacked,
       width = 22, height = 12, units = "cm", dpi = 300, bg = "white")
message("RC gender share (stacked) salva.")

# =============================================================================
# RC — CDF da idade da cônjuge menor, antes e depois de 2019
# =============================================================================
# Usa dados do RC (2003–2022), apenas casamentos com a mulher como menor
# (is_minor_w == TRUE), que representam ~91% dos casos.
# Período "Before 2019" abrange 2003–2018 (mais anos que a versão PNADC).
# LaTeX note: Source: IBGE, Civil Registry Statistics. Restricted to
#   marriages where the female spouse is the minor (~91% of child marriages).
#   Left panel: 2003–2018. Right panel: 2019–2022.

COL_EXCEP <- "#B05000"

cdf_rc_data <- rc_raw |>
  filter(is_minor_w) |>
  mutate(
    idade_num = case_when(
      idade_m == "Menos de 15 anos" ~ 14L,
      idade_m == "15 anos"          ~ 15L,
      idade_m == "16 anos"          ~ 16L,
      idade_m == "17 anos"          ~ 17L,
      TRUE                          ~ NA_integer_
    ),
    periodo = case_when(
      ano < 2019L  ~ "Before 2019 (2003–2018)",
      ano >= 2019L ~ "2019 and after (2019–2022)",
      TRUE         ~ NA_character_
    )
  ) |>
  filter(!is.na(idade_num), !is.na(periodo)) |>
  group_by(periodo, idade_num) |>
  summarise(n = sum(n_total_row, na.rm = TRUE), .groups = "drop") |>
  group_by(periodo) |>
  arrange(periodo, idade_num) |>
  mutate(pct = n / sum(n), cdf = cumsum(pct)) |>
  ungroup() |>
  mutate(periodo = factor(periodo,
    levels = c("Before 2019 (2003–2018)",
               "2019 and after (2019–2022)")))

make_cdf_rc_plot <- function(periodo_label) {
  cdf_rc_data |>
    filter(periodo == periodo_label) |>
    ggplot(aes(x = idade_num, y = cdf)) +
    annotate("rect", xmin = 13.5, xmax = 16,   ymin = 0, ymax = Inf,
             fill = "#FCE4D0", alpha = 0.55) +
    annotate("rect", xmin = 16,   xmax = 17.75, ymin = 0, ymax = Inf,
             fill = "#D6E8F5", alpha = 0.55) +
    annotate("text", x = 14.75, y = 0.92,
             label = "Exception zone", colour = COL_EXCEP,
             fontface = "italic", size = 2.8) +
    geom_step(colour = COL_MAIN, linewidth = 0.9, direction = "hv") +
    geom_point(colour = COL_MAIN, size = 2) +
    geom_vline(xintercept = 16, linetype = "dashed",
               colour = COL_EXCEP, linewidth = 0.75) +
    annotate("text", x = 16.08, y = 0.50,
             label = "Age 16\n(parental consent\nthreshold)",
             hjust = 0, size = 2.5, colour = COL_EXCEP, lineheight = 1.1) +
    geom_text(aes(label = sprintf("%.1f%%", cdf * 100)),
              hjust = 0.5, vjust = 1.7, size = 2.5, colour = "gray30") +
    scale_x_continuous(breaks = 14:17,
                       labels = c("≤ 14", "15", "16", "17"),
                       limits = c(13.5, 17.75)) +
    scale_y_continuous(labels = label_percent(accuracy = 1),
                       limits = c(0, 1.05),
                       expand = expansion(mult = c(0, 0))) +
    labs(x = "Age of minor spouse", y = "Cumulative share (%)",
         title = periodo_label) +
    theme_pub +
    theme(plot.title = element_text(hjust = 0.5, size = 10, face = "bold"))
}

fig_cdf_rc_pre  <- make_cdf_rc_plot("Before 2019 (2003–2018)")
fig_cdf_rc_post <- make_cdf_rc_plot("2019 and after (2019–2022)")

ggsave(file.path(PUB_DIR, "rc_cdf_pre2019.png"),  fig_cdf_rc_pre,
       width = 12, height = 12, units = "cm", dpi = 300, bg = "white")
ggsave(file.path(PUB_DIR, "rc_cdf_post2019.png"), fig_cdf_rc_post,
       width = 12, height = 12, units = "cm", dpi = 300, bg = "white")
message("CDF RC (pré e pós 2019) salvas separadamente.")

# =============================================================================
# RC — CDF overlay: antes vs depois de 2019 (mesmo eixo)
# =============================================================================

# Ribbon de preenchimento sob a curva pré-2019
rc_pre2019_ribbon <- cdf_rc_data |>
  filter(periodo == "Before 2019 (2003–2018)") |>
  select(idade_num, cdf)

lbl_periodos_rc <- c(
  "Before 2019 (2003–2018)"      = "Before 2019 (2003–2018)",
  "2019 and after (2019–2022)"   = "2019 and after (2019–2022)"
)

fig_rc_cdf_overlay <- cdf_rc_data |>
  ggplot(aes(x = idade_num, y = cdf,
             colour = periodo, linetype = periodo, group = periodo)) +

  # Shaded fill under pre-2019 curve
  geom_ribbon(data = rc_pre2019_ribbon,
              aes(x = idade_num, ymin = 0, ymax = cdf, group = 1),
              fill = COL_MAIN, alpha = 0.12,
              colour = NA, inherit.aes = FALSE) +

  # Step curves for both periods
  geom_step(linewidth = 0.9, direction = "hv") +
  geom_point(size = 2) +

  # Age-16 parental-consent threshold
  geom_vline(xintercept = 16, linetype = "dashed",
             colour = "gray50", linewidth = 0.75) +
  annotate("text", x = 16.08, y = 0.08,
           label = "Age 16", hjust = 0, size = 2.8, colour = "gray40") +

  scale_colour_manual(
    values = c("Before 2019 (2003–2018)"    = COL_MAIN,
               "2019 and after (2019–2022)" = COL_TREAT),
    labels = lbl_periodos_rc, name = NULL
  ) +
  scale_linetype_manual(
    values = c("Before 2019 (2003–2018)"    = "solid",
               "2019 and after (2019–2022)" = "dashed"),
    labels = lbl_periodos_rc, name = NULL
  ) +
  scale_x_continuous(breaks = 14:17,
                     labels = c("≤ 14", "15", "16", "17"),
                     limits = c(13.5, 17.75),
                     expand = expansion(mult = c(0, 0.05))) +
  scale_y_continuous(labels = label_percent(accuracy = 1),
                     breaks = seq(0, 1, .2),
                     limits = c(0, 1.08)) +
  labs(x = "Age of minor spouse",
       y = "Cumulative share (%)") +
  theme_pub +
  theme(legend.position  = "top",
        legend.key.width = unit(1.2, "cm"))

ggsave(file.path(PUB_DIR, "rc_cdf_overlay.png"), fig_rc_cdf_overlay,
       width = 18, height = 12, units = "cm", dpi = 300, bg = "white")
message("CDF RC overlay salva.")

# =============================================================================
# RC — Série temporal: casamentos infantis / casamentos de mulheres 20–29 anos
# =============================================================================
# Razão que controla pela transição demográfica (declínio geral do casamento).
# Usa rc_ratio_young (já calculado para os mapas) — aqui como série temporal.

rc_ratio_yr <- rc_ratio_young |>
  group_by(ano) |>
  summarise(
    child_marriages  = sum(child_marriages,  na.rm = TRUE),
    young_adult_marr = sum(young_adult_marr, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(ratio_pct = child_marriages / young_adult_marr * 100)

lbl_ratio_yr <- rc_ratio_yr |>
  filter(ano %in% c(2003, 2010, 2015, 2019, 2022))

fig_rc_ratio_young_line <- rc_ratio_yr |>
  ggplot(aes(x = ano, y = ratio_pct)) +
  geom_vline(xintercept = 2019, linetype = "dashed",
             colour = COL_REF, linewidth = 0.5) +
  geom_line(colour = COL_MAIN, linewidth = 0.8) +
  geom_point(colour = COL_MAIN, size = 1.8) +
  geom_text_repel(
    data   = lbl_ratio_yr,
    aes(label = sprintf("%.1f%%", ratio_pct)),
    colour = COL_MAIN, size = 2.5,
    show.legend = FALSE, min.segment.length = 0.3
  ) +
  scale_x_continuous(breaks = seq(2003, 2022, 3)) +
  scale_y_continuous(labels = label_number(suffix = "%", accuracy = 0.1),
                     limits = c(0, NA),
                     expand = expansion(mult = c(0, 0.08))) +
  labs(x = NULL,
       y = "Child marriages per 100\nmarriages of women aged 20–29") +
  theme_pub

ggsave(file.path(PUB_DIR, "rc_ratio_young_line.png"), fig_rc_ratio_young_line,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")
message("RC razão 20-29 (série temporal) salva.")

# =============================================================================
# RC — Série temporal: casamentos infantis por 10.000 menores (10–17 anos)
# =============================================================================
# Já existe rate_per_10k.png (RC somente, denominador = pop_menores.xlsx).
# Adicionamos aqui a mesma lógica desagregada por faixa etária da noiva
# para acompanhar as tendências dentro de cada grupo.

rc_rate_by_age <- rc_raw |>
  filter(is_minor_w) |>
  mutate(faixa = case_when(
    idade_m == "Menos de 15 anos" ~ "≤ 14",
    idade_m == "15 anos"          ~ "15",
    idade_m == "16 anos"          ~ "16",
    idade_m == "17 anos"          ~ "17",
    TRUE ~ NA_character_
  )) |>
  filter(!is.na(faixa)) |>
  group_by(ano, faixa) |>
  summarise(n = sum(n_total_row, na.rm = TRUE), .groups = "drop") |>
  left_join(pop_nacional, by = "ano") |>
  filter(!is.na(pop_10_17)) |>
  mutate(rate = n / pop_10_17 * 10000,
         faixa = factor(faixa, levels = c("≤ 14", "15", "16", "17")))

lbl_rate_age <- rc_rate_by_age |>
  filter(ano %in% c(2003, 2010, 2015, 2019, 2022))

fig_rc_rate_by_age <- rc_rate_by_age |>
  ggplot(aes(x = ano, y = rate,
             colour = faixa, linetype = faixa, group = faixa)) +
  geom_vline(xintercept = 2019, linetype = "dashed",
             colour = COL_REF, linewidth = 0.5) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.8) +
  geom_text_repel(
    data = lbl_rate_age,
    aes(label = sprintf("%.1f", rate)),
    size = 2.3, show.legend = FALSE, min.segment.length = 0.3
  ) +
  scale_colour_manual(
    values = c("≤ 14" = "#8B0000", "15" = COL_TREAT,
               "16"   = COL_MAIN,  "17" = "gray50"),
    name = "Age group"
  ) +
  scale_linetype_manual(
    values = c("≤ 14" = "dotted", "15" = "dashed",
               "16"   = "solid",  "17" = "longdash"),
    name = "Age group"
  ) +
  scale_x_continuous(breaks = seq(2003, 2022, 3)) +
  scale_y_continuous(labels = label_number(accuracy = 0.1),
                     limits = c(0, NA),
                     expand = expansion(mult = c(0, 0.08))) +
  labs(x = NULL,
       y = "Child marriages per 10,000\nminors (ages 10–17)") +
  theme_pub +
  theme(legend.position  = "bottom",
        legend.key.width = unit(1.0, "cm"))

ggsave(file.path(PUB_DIR, "rc_rate_by_age.png"), fig_rc_rate_by_age,
       width = 20, height = 12, units = "cm", dpi = 300, bg = "white")
message("RC taxa por 10.000 por faixa etária salva.")

# =============================================================================
# RC — Mapas regionais: % casamentos infantis / total, 2003 vs 2022
# =============================================================================
# LaTeX note: Source: IBGE, Civil Registry Statistics. Share of child marriages
#   (at least one spouse under 18) in total registered marriages, by state.
#   Comparing 2003 (first year available) and 2022 (most recent year).

rc_state_pct <- rc_raw |>
  filter(ano %in% c(2003L, 2022L)) |>
  group_by(ano, uf) |>
  summarise(
    child_marriages = sum(n_total_row[is_minor_w], na.rm = TRUE),
    total_marriages = sum(n_total_row,             na.rm = TRUE),
    .groups = "drop"
  ) |>
  filter(!is.na(uf), total_marriages > 0) |>
  mutate(
    pct_child  = child_marriages / total_marriages * 100,
    code_state = uf_to_code(uf),
    ano_label  = as.character(ano)
  )

if (has_geobr) {
  estados_sf  <- geobr::read_state(year = 2020, showProgress = FALSE)

  # Produto cartesiano UF × ano para garantir que todos os estados aparecem
  # em ambos os painéis (preenchidos com NA quando sem dados)
  grid_sf <- tidyr::crossing(
    estados_sf |> select(code_state, geom),
    tibble(ano_label = c("2003", "2022"))
  ) |>
    left_join(rc_state_pct |> select(code_state, ano_label, pct_child),
              by = c("code_state", "ano_label"))

  fig_rc_mapa <- ggplot(grid_sf) +
    geom_sf(aes(fill = pct_child, geometry = geom),
            colour = "white", linewidth = 0.2) +
    facet_wrap(~ ano_label, ncol = 2) +
    scale_fill_distiller(
      palette   = "YlOrRd",
      direction = 1,
      name      = "Child marriages\n(% of total)",
      labels    = function(x) sprintf("%.1f%%", x),
      na.value  = "gray85"
    ) +
    labs(x = NULL, y = NULL) +
    theme_pub +
    theme(
      axis.text        = element_blank(),
      axis.ticks       = element_blank(),
      axis.line        = element_blank(),
      legend.position  = "bottom",
      legend.key.width = unit(1.5, "cm"),
      panel.spacing    = unit(0.5, "cm")
    )

  ggsave(file.path(PUB_DIR, "rc_mapa_2003_2022.png"), fig_rc_mapa,
         width = 22, height = 14, units = "cm", dpi = 300, bg = "white")
  message("RC mapas 2003 vs 2022 salvos.")
} else {
  message("AVISO: geobr nao instalado — mapa RC 2003/2022 nao gerado.")
}

# =============================================================================
# RC — Mapa: casamentos infantis por 1.000 casamentos de mulheres 20–29 anos
# =============================================================================
# Motivação: a transição demográfica reduz o total de casamentos, comprimindo o
# denominador de "% do total" mesmo que o comportamento com menores não mude.
# Normalizar pela faixa 20–29 (a que mais casa) isola a mudança real.
#
# Métrica: casamentos infantis (noiva < 18) /
#          casamentos de mulheres 20–29 anos × 1.000
#
# Faixas usadas como denominador: "20 a 24 anos" e "25 a 29 anos" (idade_m).
# LaTeX note: Source: IBGE, Civil Registry Statistics. Numerator: marriages
#   where the female spouse is under 18. Denominator: marriages where the
#   female spouse is aged 20–29 — the peak marriage age group. Expressed per
#   1,000 marriages in the reference group to control for the demographic
#   transition (declining total marriages among young adults).

rc_ratio_young <- rc_raw |>
  mutate(
    young_adult_w = idade_m %in% c("20 a 24 anos", "25 a 29 anos")
  ) |>
  group_by(ano, uf) |>
  summarise(
    child_marriages  = sum(n_total_row[is_minor_w],    na.rm = TRUE),
    young_adult_marr = sum(n_total_row[young_adult_w], na.rm = TRUE),
    .groups = "drop"
  ) |>
  filter(!is.na(uf), young_adult_marr > 0) |>
  mutate(
    ratio_per_1k = child_marriages / young_adult_marr * 1000,
    code_state   = uf_to_code(uf),
    ano_label    = as.character(ano)
  )

if (has_geobr) {
  # Reutiliza estados_sf já carregado; cria se não existir (execução parcial)
  if (!exists("estados_sf"))
    estados_sf <- geobr::read_state(year = 2020, showProgress = FALSE)

  # ── Versão 1: escala compartilhada (contexto absoluto) ────────────────────
  grid_young_sf <- tidyr::crossing(
    estados_sf |> select(code_state, geom),
    tibble(ano_label = c("2003", "2022"))
  ) |>
    left_join(
      rc_ratio_young |>
        filter(ano %in% c(2003L, 2022L)) |>
        select(code_state, ano_label, ratio_per_1k),
      by = c("code_state", "ano_label")
    )

  fig_rc_mapa_young <- ggplot(grid_young_sf) +
    geom_sf(aes(fill = ratio_per_1k, geometry = geom),
            colour = "white", linewidth = 0.2) +
    facet_wrap(~ ano_label, ncol = 2) +
    scale_fill_distiller(
      palette   = "YlOrRd",
      direction = 1,
      name      = "Child marriages\nper 1,000 women\naged 20–29",
      labels    = function(x) sprintf("%.0f", x),
      na.value  = "gray85"
    ) +
    labs(x = NULL, y = NULL) +
    theme_pub +
    theme(
      axis.text        = element_blank(),
      axis.ticks       = element_blank(),
      axis.line        = element_blank(),
      legend.position  = "bottom",
      legend.key.width = unit(1.5, "cm"),
      panel.spacing    = unit(0.5, "cm")
    )

  ggsave(file.path(PUB_DIR, "rc_mapa_young_ratio.png"), fig_rc_mapa_young,
         width = 22, height = 14, units = "cm", dpi = 300, bg = "white")
  message("RC mapa (razão 20–29, escala compartilhada) salvo.")

  # ── Versão 2: escalas independentes por ano (heterogeneidade relativa) ────
  # Cada painel é um ggplot separado com scale_fill calibrada para aquele ano.
  # Combinados com patchwork para manter o layout lado a lado.
  has_patchwork <- requireNamespace("patchwork", quietly = TRUE)
  if (!has_patchwork)
    message("  NOTA: instale patchwork para o mapa de escalas independentes: install.packages('patchwork')")

  make_yr_map <- function(yr, sf_base, data_ratio, show_legend = TRUE) {
    df <- sf_base |>
      left_join(
        data_ratio |>
          filter(ano == yr) |>
          select(code_state, ratio_per_1k),
        by = "code_state"
      )
    lim <- c(0, max(data_ratio$ratio_per_1k[data_ratio$ano == yr], na.rm = TRUE))

    ggplot(df) +
      geom_sf(aes(fill = ratio_per_1k, geometry = geom),
              colour = "white", linewidth = 0.2) +
      scale_fill_distiller(
        palette   = "YlOrRd",
        direction = 1,
        limits    = lim,
        name      = "per 1,000\nwomen 20–29",
        labels    = function(x) sprintf("%.0f", x),
        na.value  = "gray85"
      ) +
      labs(title = as.character(yr), x = NULL, y = NULL) +
      theme_pub +
      theme(
        axis.text        = element_blank(),
        axis.ticks       = element_blank(),
        axis.line        = element_blank(),
        legend.position  = if (show_legend) "bottom" else "none",
        legend.key.width = unit(1.2, "cm"),
        plot.title       = element_text(hjust = 0.5, size = 10, face = "bold")
      )
  }

  if (has_patchwork) {
    library(patchwork)
    p_2003 <- make_yr_map(2003, estados_sf, rc_ratio_young, show_legend = TRUE)
    p_2022 <- make_yr_map(2022, estados_sf, rc_ratio_young, show_legend = TRUE)
    fig_rc_mapa_young_free <- p_2003 + p_2022 +
      plot_layout(ncol = 2)

    ggsave(file.path(PUB_DIR, "rc_mapa_young_free.png"), fig_rc_mapa_young_free,
           width = 22, height = 14, units = "cm", dpi = 300, bg = "white")
    message("RC mapa (razão 20–29, escalas independentes) salvo.")
  }

  # ── Versão 3: mapa de variação — queda percentual 2003→2022 por estado ────
  # Destaca estados que reduziram menos (vermelho) vs mais (azul).
  rc_change_sf <- estados_sf |>
    left_join(
      rc_ratio_young |>
        filter(ano %in% c(2003L, 2022L)) |>
        select(code_state, ano, ratio_per_1k) |>
        tidyr::pivot_wider(names_from = ano,
                           values_from = ratio_per_1k,
                           names_prefix = "y") |>
        mutate(
          pct_change = (y2022 - y2003) / y2003 * 100   # negativo = queda
        ),
      by = "code_state"
    )

  fig_rc_mapa_change <- ggplot(rc_change_sf) +
    geom_sf(aes(fill = pct_change, geometry = geom),
            colour = "white", linewidth = 0.2) +
    scale_fill_distiller(
      palette   = "RdBu",
      direction = 1,             # azul = maior queda, vermelho = menor queda
      name      = "Change\n2003→2022 (%)",
      labels    = function(x) sprintf("%+.0f%%", x),
      na.value  = "gray85"
    ) +
    labs(x = NULL, y = NULL) +
    theme_pub +
    theme(
      axis.text        = element_blank(),
      axis.ticks       = element_blank(),
      axis.line        = element_blank(),
      legend.position  = "bottom",
      legend.key.width = unit(1.5, "cm")
    )

  ggsave(file.path(PUB_DIR, "rc_mapa_young_change.png"), fig_rc_mapa_change,
         width = 14, height = 14, units = "cm", dpi = 300, bg = "white")
  message("RC mapa (variação 2003–2022) salvo.")

} else {
  message("AVISO: geobr nao instalado — mapa RC razao 20-29 nao gerado.")
}

# =============================================================================
# SUMÁRIO DE OUTPUTS
# =============================================================================

outputs_pub <- c(
  "RC_pct_total.png",
  "variation_RC_PNADC.png",
  "pnadc_vs_rc_pct.png",
  "rate_per_10k.png",
  "prevalencia_anual_pnad.png",
  "mapa_regional.png",
  "rural_urbano.png",
  "age_gap.png",
  "age_gap_periodos.png",
  "cdf_idade_conjuge.png",   # PNADC version (kept for comparison)
  "cdf_overlay.png",
  "neet.png",
  "freq_escolar.png",
  "nivel_ensino.png",
  "lm_participacao.png",
  # New RC-based figures
  "prev_stock_comparison.png",
  "underreporting.png",
  "formalizacao_rate.png",
  "rc_gender_share.png",
  "rc_gender_share_stacked.png",
  "rc_cdf_pre2019.png",
  "rc_cdf_post2019.png",
  "rc_cdf_overlay.png",
  "rc_ratio_young_line.png",
  "rc_rate_by_age.png",
  "rc_mapa_2003_2022.png",
  "rc_mapa_young_ratio.png",
  "rc_mapa_young_free.png",
  "rc_mapa_young_change.png"
)

existem <- file.exists(file.path(PUB_DIR, outputs_pub))
cat("\n=== Outputs gerados ===\n")
for (i in seq_along(outputs_pub)) {
  cat(sprintf("  %s  %s\n",
              if (existem[i]) "✓" else "✗",
              outputs_pub[i]))
}
cat(sprintf("\n%d / %d figuras salvas em: %s\n\n",
            sum(existem), length(outputs_pub), PUB_DIR))

# Saída LaTeX: 09_figuras_latex.tex em /draft — compila sozinho com todas as
# figuras no formato \begin{figure}\includegraphics...\end{figure}

message("09_figuras_paper.R concluído.")
