# =============================================================================
# 10_prep_discrete_choice.R — Preparação dos dados para modelo de escolha
#                              discreta (casamento infantil)
# =============================================================================
#
# MODELO DE REFERÊNCIA
#   Furtado, Fortunato & Martins (2026). "Between Law and Numbers".
#   Seção 3: escolha entre M ∈ {F=formal, I=informal, W=esperar}.
#   Estado: (a, p) — idade da menor [10..17] e gravidez [0,1].
#   Covariáveis-chave: ∆ (gap de idade), Yᵢ (renda domiciliar), normas sociais
#   (κᵢ, μᵢ), s(a) (retorno da escolaridade), ϕ_F / ϕ_I (custos legais).
#
# UNIDADES DE OBSERVAÇÃO
#   dc_pnadc_dcm : menina de 10–17 anos — escolha = in_union (F∪I) ou wait (W)
#                  • "in_union" → categ_domic == C, condição = cônjuge/companheira
#                  • "wait"     → menina 10–17 NÃO cônjuge em nenhum domicílio
#                  Observação: F e I são indistinguíveis individualmente na PNADC.
#                  A distinção é feita em nível agregado via dc_rc_dcm (ver abaixo).
#
#   dc_rc_dcm    : célula UF × ano × faixa_etária_noiva
#                  Registro Civil é censo administrativo — não há microdados
#                  individuais. Cada linha tem a contagem de casamentos formais
#                  naquela célula. Permite calcular a taxa de formalidade por
#                  (UF, ano, faixa_etária) para usar como regressor em dc_pnadc_dcm.
#
# DATASETS EXPORTADOS (em DATA_OUT_DIR = data/discrete_choice/)
#   dc_pnadc_dcm.rds / .csv   — PNADC individual (meninas 10–17)
#   dc_rc_dcm.rds    / .csv   — RC célula agregada
#   formal_rate.rds  / .csv   — taxa de formalidade UF × ano × faixa (join key)
#   codebook.txt               — dicionário completo
#
# DEPENDÊNCIAS
#   pnadc_categ_cache.rds   ← 01_importacao.R / 02_preparacao.R
#   rc_raw_cache.rds        ← 01_importacao.R
#   parte3_cache.rds        ← 04_analises_PNADC.R (para pnadc_stock)
#
# =============================================================================

source(here::here("00_setup.R"))
library(purrr)

DATA_OUT_DIR <- here("data", "discrete_choice")
dir.create(DATA_OUT_DIR, showWarnings = FALSE, recursive = TRUE)

message("=== 10_prep_discrete_choice.R ===")
message("Saída: ", DATA_OUT_DIR)

# =============================================================================
# VERIFICAÇÃO DOS CACHES
# =============================================================================

caches_needed <- c("pnadc_categ_cache.rds", "rc_raw_cache.rds", "parte3_cache.rds")
faltando <- caches_needed[!file.exists(file.path(CACHE_DIR, caches_needed))]
if (length(faltando) > 0L)
  stop("Caches ausentes em CACHE_DIR (", CACHE_DIR, "):\n",
       paste(" ✗", faltando, collapse = "\n"),
       "\n\nRode: 01_importacao.R → 02_preparacao.R → 04_analises_PNADC.R")

# =============================================================================
# BASE 1 — PNADC: unidade = menina de 10–17 anos
# =============================================================================
# Estrutura de pnadc_categ:
#   • Múltiplos membros por domicílio (chefe + cônjuge + outros)
#   • categ_domic  : categoria do domicílio (A/B/C/D), replicada para todos os membros
#   • condno_domic : papel da pessoa (chefe / cônjuge / filho / etc.)
#   • dif_idade    : diferença de idade HEAD–CÔNJUGE; armazenada no registro do chefe
# =============================================================================

message("\n[1/3] Carregando pnadc_categ...")
pnadc_categ <- readRDS(file.path(CACHE_DIR, "pnadc_categ_cache.rds"))
message(sprintf("  %d linhas × %d variáveis", nrow(pnadc_categ), ncol(pnadc_categ)))

# ── Helpers ------------------------------------------------------------------

is_spouse <- function(x)
  stringr::str_detect(as.character(x), "(?i)c[oô]njuge|companheiro")

is_child_rel <- function(x)
  stringr::str_detect(as.character(x), "(?i)filho|enteado|parente|outro")

to_int <- function(x) suppressWarnings(as.integer(as.character(x)))

# Colunas brutas disponíveis em pnadc_categ (de cols_survey em 02_preparacao.R,
# mais UF). Todas exportadas sem transformação — o modelador constrói o que precisar.
COLS_PNADC_RAW <- c(
  # Design amostral
  "UPA", "Estrato", "pes_comcalib",
  # Identificadores
  "domic_id", "pessoa_id", "Ano",
  # Localização
  "UF", "regiao", "sit_domic",
  # Papel e categoria do domicílio
  "condno_domic", "categ_domic",
  # Características individuais
  "idade", "sexo_bin", "parda_preta_bin", "ler_escrever_bin",
  # Trabalho e renda (brutos)
  "trab_remun", "trab_remun_bin", "afastd_bin",
  "horas_trabalhadas_seman", "rend",
  # Cuidado e maternidade (insumos para construir p)
  "matern_bin", "cuidado_provid_bin", "cuidado_trab_bin",
  # Educação
  "freq_esc",
  # Gap de idade HEAD–CÔNJUGE (armazenado no registro do chefe)
  "dif_idade"
)

# Filtra para colunas que de fato existem no cache (tolerante a versões)
cols_ok <- intersect(COLS_PNADC_RAW, names(pnadc_categ))
cols_ausentes <- setdiff(COLS_PNADC_RAW, names(pnadc_categ))
if (length(cols_ausentes) > 0L)
  message("  AVISO — colunas não encontradas (ignoradas): ",
          paste(cols_ausentes, collapse = ", "))

# ── 1A: Meninas em união (categ C, cônjuge, 10–17 anos) ─────────────────────
# Unidade principal do modelo. Todas as variáveis brutas da menor são exportadas.
# choice = "in_union" (F ou I — indistinguíveis na PNADC ao nível individual).
# a = idade como inteiro; faixa_menor = chave de join com dc_rc_dcm.

message("  Extraindo meninas em união (categ C, cônjuge, 10–17)...")

minor_in_union <- pnadc_categ |>
  filter(
    categ_domic == "C",
    is_spouse(condno_domic),
    to_int(idade) >= 10L,
    to_int(idade) <= 17L
  ) |>
  select(all_of(cols_ok)) |>
  rename(idade_menor = idade) |>
  mutate(
    choice      = "in_union",
    ano         = to_int(as.character(Ano)),
    a           = to_int(idade_menor),          # inteiro — variável de estado
    faixa_menor = case_when(                    # chave de join com RC
      a <= 14L ~ "Menos de 15 anos",
      a == 15L ~ "15 anos",
      a == 16L ~ "16 anos",
      a == 17L ~ "17 anos",
      TRUE     ~ NA_character_
    )
  )

message(sprintf("  in_union: %d observações", nrow(minor_in_union)))

# ── 1B: Características do parceiro adulto (chefe categ C) ──────────────────
# dif_idade (= ∆ no modelo) fica no registro do CHEFE. Todas as variáveis brutas
# do parceiro são incluídas com prefixo "parc_" para evitar conflito de nomes.

message("  Extraindo características do parceiro adulto...")

adult_head <- pnadc_categ |>
  filter(
    categ_domic == "C",
    condno_domic == "Pessoa responsável pelo domicílio"
  ) |>
  select(all_of(intersect(cols_ok, names(pnadc_categ)))) |>
  rename(
    parc_idade           = idade,
    delta                = dif_idade,       # ∆ do modelo — age gap HEAD–CÔNJUGE
    parc_sexo_bin        = sexo_bin,
    parc_parda_preta_bin = parda_preta_bin,
    parc_ler_escrever    = ler_escrever_bin,
    parc_trab_remun      = trab_remun,
    parc_trab_remun_bin  = trab_remun_bin,
    parc_afastd_bin      = afastd_bin,
    parc_horas_trab      = horas_trabalhadas_seman,
    parc_rend            = rend,            # renda bruta (R$) — proxy de w(∆)
    parc_matern_bin      = matern_bin,
    parc_cuidado_provid  = cuidado_provid_bin,
    parc_cuidado_trab    = cuidado_trab_bin,
    parc_freq_esc        = freq_esc
  ) |>
  select(domic_id, Ano, delta, starts_with("parc_"))

message(sprintf("  adult_head: %d domicílios", nrow(adult_head)))

# ── 1C: Join menor + parceiro ------------------------------------------------

minor_in_union <- minor_in_union |>
  left_join(adult_head, by = c("domic_id", "Ano"))

# ── 1D: Grupo W — meninas 10–17 NÃO em união ────────────────────────────────
# Filtro: sexo feminino, 10–17 anos, condno_domic ≠ cônjuge/companheira.
# Todas as variáveis brutas da menor exportadas. Colunas do parceiro = NA.
# NOTA: pnadc_categ pode não conter meninas de domicílios sem arranjo conjugal.
# Nesses casos o grupo W estará subestimado — ver codebook.

message("  Extraindo grupo W (meninas 10–17 não em união)...")

girls_wait <- tryCatch({
  pnadc_categ |>
    filter(
      to_int(idade) >= 10L,
      to_int(idade) <= 17L,
      sexo_bin == 1L | as.character(sexo_bin) %in% c("1", "Feminino", "Mulher"),
      !is_spouse(condno_domic)
    ) |>
    select(all_of(cols_ok)) |>
    rename(idade_menor = idade) |>
    mutate(
      choice      = "wait",
      ano         = to_int(as.character(Ano)),
      a           = to_int(idade_menor),
      faixa_menor = case_when(
        a <= 14L ~ "Menos de 15 anos",
        a == 15L ~ "15 anos",
        a == 16L ~ "16 anos",
        a == 17L ~ "17 anos",
        TRUE     ~ NA_character_
      ),
      # Colunas do parceiro: NA para quem não está em união
      delta                = NA_integer_,
      parc_idade           = NA_character_,
      parc_sexo_bin        = NA_integer_,
      parc_parda_preta_bin = NA_integer_,
      parc_ler_escrever    = NA_integer_,
      parc_trab_remun      = NA_character_,
      parc_trab_remun_bin  = NA_integer_,
      parc_afastd_bin      = NA_integer_,
      parc_horas_trab      = NA_real_,
      parc_rend            = NA_real_,
      parc_matern_bin      = NA_integer_,
      parc_cuidado_provid  = NA_integer_,
      parc_cuidado_trab    = NA_integer_,
      parc_freq_esc        = NA_character_
    )
}, error = function(e) {
  warning("Grupo W não pôde ser extraído: ", conditionMessage(e),
          "\n  Verifique se pnadc_categ contém filhas/parentes ou se sexo_bin",
          " tem valores diferentes de 1L.")
  NULL
})

if (!is.null(girls_wait)) {
  message(sprintf("  wait: %d observações", nrow(girls_wait)))
} else {
  message("  AVISO: grupo W não disponível neste cache.")
}

# ── 1E: Combinar in_union + wait ---------------------------------------------
# bind_rows() exige tipos idênticos por coluna. Como as colunas parc_* em
# girls_wait foram definidas como NA (tipo pode divergir do join de adult_head),
# alinhamos os tipos de girls_wait para bater com minor_in_union antes de unir.

cols_comuns <- intersect(names(minor_in_union), names(girls_wait))

align_types <- function(df_target, df_ref, cols) {
  for (col in cols) {
    ref_class <- class(df_ref[[col]])[1]
    tgt_class <- class(df_target[[col]])[1]
    if (!identical(ref_class, tgt_class)) {
      df_target[[col]] <- switch(ref_class,
        "numeric"   = as.numeric(df_target[[col]]),
        "double"    = as.double(df_target[[col]]),
        "integer"   = as.integer(df_target[[col]]),
        "character" = as.character(df_target[[col]]),
        "logical"   = as.logical(df_target[[col]]),
        df_target[[col]]
      )
    }
  }
  df_target
}

dc_pnadc_dcm <- if (!is.null(girls_wait)) {
  girls_wait_aligned <- align_types(girls_wait, minor_in_union, cols_comuns)
  bind_rows(
    minor_in_union    |> select(all_of(cols_comuns)),
    girls_wait_aligned |> select(all_of(cols_comuns))
  )
} else {
  minor_in_union |> select(all_of(cols_comuns))
}

# ── 1F: Estatísticas de verificação -----------------------------------------
n_in_union <- sum(dc_pnadc_dcm$choice == "in_union", na.rm = TRUE)
n_wait     <- sum(dc_pnadc_dcm$choice == "wait",     na.rm = TRUE)
message(sprintf("  dc_pnadc_dcm: %s obs | in_union=%s | wait=%s",
                format(nrow(dc_pnadc_dcm), big.mark = "."),
                format(n_in_union, big.mark = "."),
                format(n_wait, big.mark = ".")))
message(sprintf("  Idade média (in_union): %.1f | Média delta (∆): %.1f anos",
                mean(dc_pnadc_dcm$a[dc_pnadc_dcm$choice == "in_union"], na.rm = TRUE),
                mean(dc_pnadc_dcm$delta[dc_pnadc_dcm$choice == "in_union"], na.rm = TRUE)))

rm(pnadc_categ, minor_in_union, adult_head, girls_wait); gc()

# =============================================================================
# BASE 2 — REGISTRO CIVIL: unidade = célula UF × ano × faixa etária da noiva
# =============================================================================
# O RC não tem microdados — o IBGE publica apenas tabelas de frequência.
# Cada linha é a contagem de casamentos formais naquela célula.
# Para o modelo, o RC identifica o FLUXO formal (margem F).
# A taxa de formalidade formal_rate = rc_cell / pnadc_stock permite estimar
# a probabilidade P(F | in_union) usada na distinção F vs I.
# =============================================================================

message("\n[2/3] Carregando rc_raw...")
rc_raw <- readRDS(file.path(CACHE_DIR, "rc_raw_cache.rds"))
message(sprintf("  %d células × %d variáveis", nrow(rc_raw), ncol(rc_raw)))
message("  Variáveis disponíveis: ", paste(names(rc_raw), collapse = ", "))

# ── 2A: Denominador 20–29 por UF × ano (controla transição demográfica) -----
# N casamentos de mulheres 20–29 é o denominador do modelo para normalizar
# o fluxo por algo que reflete o "mercado de casamentos" regional.

n_2029 <- rc_raw |>
  mutate(is_2029 = grepl("20 a 24|25 a 29", as.character(idade_m),
                         ignore.case = TRUE)) |>
  group_by(ano, uf) |>
  summarise(n_casamentos_2029 = sum(n_total_row[is_2029], na.rm = TRUE),
            .groups = "drop")

# ── 2B: Construir dc_rc_dcm -------------------------------------------------

COLS_RC_BASE <- c("ano", "uf", "idade_m", "n_total_row", "is_minor_w")
cols_rc_ok   <- intersect(COLS_RC_BASE, names(rc_raw))

# Adiciona n_h_minor se existir
if ("n_h_minor" %in% names(rc_raw)) cols_rc_ok <- c(cols_rc_ok, "n_h_minor")

dc_rc_dcm <- rc_raw |>
  select(all_of(cols_rc_ok)) |>
  left_join(n_2029, by = c("ano", "uf")) |>
  mutate(
    # Faixa etária numérica (14 = "Menos de 15 anos")
    idade_m_num = case_when(
      grepl("Menos de 15|men.*15", as.character(idade_m), ignore.case = TRUE) ~ 14L,
      grepl("^15", as.character(idade_m))  ~ 15L,
      grepl("^16", as.character(idade_m))  ~ 16L,
      grepl("^17", as.character(idade_m))  ~ 17L,
      grepl("^18", as.character(idade_m))  ~ 18L,
      TRUE ~ NA_integer_
    ),
    # Anos que a menor ainda será menor após o casamento (∆ para estoque ponderado)
    anos_contrib = case_when(
      idade_m_num == 14L ~ 4L,
      idade_m_num == 15L ~ 3L,
      idade_m_num == 16L ~ 2L,
      idade_m_num == 17L ~ 1L,
      TRUE               ~ 0L
    ),
    # Indicadores de política
    pos_lei2019  = as.integer(ano >= 2019L),
    below_16     = as.integer(idade_m_num < 16L),
    # Custo legal ativo para casamento FORMAL (ϕ_F no modelo)
    # Antes de 2019: risco judicial se a < 16 (depende de gravidez — não obs. no RC)
    # Após 2019:     custo certo se a < 16
    phi_F_active = as.integer(below_16 == 1L & (pos_lei2019 == 1L | TRUE)),
    # Taxa normalizada: casamentos infantis / casamentos de mulheres 20–29
    rate_per_1k_2029 = if_else(
      !is.na(n_casamentos_2029) & n_casamentos_2029 > 0,
      n_total_row / n_casamentos_2029 * 1000,
      NA_real_
    )
  )

message(sprintf("  dc_rc_dcm: %d células × %d variáveis",
                nrow(dc_rc_dcm), ncol(dc_rc_dcm)))
message(sprintf("  Anos: %d a %d | UFs: %d",
                min(dc_rc_dcm$ano, na.rm = TRUE),
                max(dc_rc_dcm$ano, na.rm = TRUE),
                n_distinct(dc_rc_dcm$uf)))
message(sprintf("  Total casamentos infantis formais (toda série): %s",
                format(sum(dc_rc_dcm$n_total_row[dc_rc_dcm$is_minor_w],
                           na.rm = TRUE), big.mark = ".")))

# =============================================================================
# TABELA AUXILIAR — Taxa de formalidade por UF × ano × faixa
# =============================================================================
# Permite calcular P(F | in_union) = RC_casamentos_célula / PNADC_stock_célula
# para usar como regressor na distinção F vs I em dc_pnadc_dcm.
# A proporção formal é calculada ao nível UF × ano (sem faixa, para ter massa).
# Para granularidade por faixa, usar rate_per_1k_2029 em dc_rc_dcm.

message("\n[3/3] Construindo tabela formal_rate (UF × ano)...")

p3           <- readRDS(file.path(CACHE_DIR, "parte3_cache.rds"))
early_annual <- p3$early_annual
rm(p3); gc()

# Estoque PNADC por ano (nacional) para referência
pnadc_stock_yr <- early_annual |>
  mutate(ano = as.integer(as.character(Ano))) |>
  select(ano, pnadc_stock = total_early)

# Estoque RC ponderado (nacional) por ano
ANOS_CONTRIB_VEC <- c("Menos de 15 anos" = 4L, "15 anos" = 3L,
                      "16 anos" = 2L,          "17 anos" = 1L)

rc_flow_by_age <- dc_rc_dcm |>
  filter(is_minor_w, !is.na(anos_contrib), anos_contrib > 0L) |>
  group_by(ano, anos_contrib) |>
  summarise(flow = sum(n_total_row, na.rm = TRUE), .groups = "drop")

anos_seq <- sort(unique(rc_flow_by_age$ano))
rc_stock_yr <- map_dfr(anos_seq, function(y) {
  tibble(
    ano      = y,
    rc_stock = rc_flow_by_age |>
      filter(ano <= y, ano + anos_contrib > y) |>
      summarise(s = sum(flow, na.rm = TRUE)) |>
      pull(s)
  )
})

formal_rate <- inner_join(rc_stock_yr, pnadc_stock_yr, by = "ano") |>
  mutate(
    ratio_pnadc_rc   = round(pnadc_stock / rc_stock, 2),
    underreport_pct  = round((1 - rc_stock / pnadc_stock) * 100, 1),
    # P(F | in_union) ≈ rc_stock / pnadc_stock (proxy de formalidade)
    formal_rate      = round(rc_stock / pnadc_stock, 4),
    pos_lei2019      = as.integer(ano >= 2019L)
  ) |>
  select(ano, rc_stock, pnadc_stock, formal_rate,
         ratio_pnadc_rc, underreport_pct, pos_lei2019)

message("  formal_rate:")
print(formal_rate)

# =============================================================================
# EXPORTAR
# =============================================================================

message("\n=== Exportando ===")

saveRDS(dc_pnadc_dcm, file.path(DATA_OUT_DIR, "dc_pnadc_dcm.rds"))
saveRDS(dc_rc_dcm,    file.path(DATA_OUT_DIR, "dc_rc_dcm.rds"))
saveRDS(formal_rate,  file.path(DATA_OUT_DIR, "formal_rate.rds"))

readr::write_csv(dc_pnadc_dcm, file.path(DATA_OUT_DIR, "dc_pnadc_dcm.csv"))
readr::write_csv(dc_rc_dcm,    file.path(DATA_OUT_DIR, "dc_rc_dcm.csv"))
readr::write_csv(formal_rate,  file.path(DATA_OUT_DIR, "formal_rate.csv"))

message("  ✓ dc_pnadc_dcm  (.rds + .csv)")
message("  ✓ dc_rc_dcm     (.rds + .csv)")
message("  ✓ formal_rate   (.rds + .csv)")

# =============================================================================
# CODEBOOK
# =============================================================================

codebook_lines <- c(
  "=============================================================================",
  "CODEBOOK — Dados para modelo de escolha discreta (casamento infantil)",
  paste0("Gerado em: ", format(Sys.time(), "%Y-%m-%d %H:%M")),
  "Script:    10_prep_discrete_choice.R",
  "Modelo:    Furtado, Fortunato & Martins (2026) — Between Law and Numbers",
  "=============================================================================",
  "",
  "─────────────────────────────────────────────────────────────────────────────",
  "BASE 1: dc_pnadc_dcm (.rds / .csv)",
  "─────────────────────────────────────────────────────────────────────────────",
  "Fonte:    IBGE, PNADC — Visita 1, 1º trimestre",
  "Cobertura: Brasil, 2012–2019 e 2022–2023 (2020–2021 excluídos — COVID-19)",
  "Unidade:  Menina de 10–17 anos (a variável de estado 'a' do modelo)",
  sprintf("Linhas:   %s", format(nrow(dc_pnadc_dcm), big.mark = ".")),
  sprintf("  in_union (F∪I): %s", format(n_in_union, big.mark = ".")),
  sprintf("  wait     (W):   %s", format(n_wait, big.mark = ".")),
  "",
  "DESIGN AMOSTRAL (obrigatório em toda estimação):",
  "  srvyr::as_survey_design(ids=UPA, strata=Estrato, weights=pes_comcalib)",
  "",
  "FILOSOFIA DESTA BASE",
  "  Exportamos o máximo de variáveis brutas da PNADC para que o modelador",
  "  construa as variáveis que precisar. Apenas duas colunas foram derivadas:",
  "    choice      : 'in_union' ou 'wait' — classifica a observação no modelo",
  "    a           : idade_menor convertida para inteiro [10..17]",
  "    faixa_menor : chave de join com dc_rc_dcm (mesma nomenclatura do IBGE)",
  "  Todas as demais variáveis (indicadores de política, renda em SM, urbanização,",
  "  fator de região, custos legais, proxy de gravidez, etc.) devem ser",
  "  construídas pelo modelador a partir das variáveis brutas abaixo.",
  "",
  "VARIÁVEL DE RESULTADO:",
  "  choice         'in_union' — categ C, condição = cônjuge, idade 10–17",
  "                 'wait'     — menina 10–17 não cônjuge",
  "                 Nota: F e I são indistinguíveis na PNADC ao nível individual.",
  "                 Para decompor em {F, I, W}, usar formal_rate.rds (ver abaixo).",
  "",
  "VARIÁVEIS DE ESTRUTURA (derivadas, necessárias para o modelo):",
  "  a              Idade da menor como inteiro [10..17]",
  "  faixa_menor    Faixa etária no padrão do IBGE/RC — join key com dc_rc_dcm",
  "",
  "VARIÁVEIS BRUTAS DA MENOR:",
  "  idade_menor    Idade (formato original do cache — factor ou character)",
  "  sexo_bin       Sexo: 1=Feminino, 0=Masculino",
  "  parda_preta_bin  Cor/raça: 1=Parda ou Preta",
  "  ler_escrever_bin Alfabetização: 1=sabe ler e escrever",
  "  freq_esc       Frequência escolar (formato original da PNADC)",
  "  trab_remun     Tipo de trabalho remunerado (categórica original)",
  "  trab_remun_bin Trabalho remunerado: 1=sim, 0=não",
  "  afastd_bin     Afastamento do trabalho na semana ref.: 1=sim",
  "  horas_trabalhadas_seman  Horas trabalhadas na semana de referência",
  "  rend           Rendimento mensal (R$ nominais brutos)",
  "  matern_bin     Afastamento por maternidade na semana ref.: 1=sim",
  "                 → insumo para construir p (gravidez) — ver nota abaixo",
  "  cuidado_provid_bin  Cuidou de pessoa doente/idosa/com deficiência: 1=sim",
  "                 → insumo adicional para construir p",
  "  cuidado_trab_bin    Deixou de trabalhar ou trabalhou menos por cuidados: 1=sim",
  "",
  "NOTA SOBRE p (GRAVIDEZ — não incluída):",
  "  Nenhuma variável da PNADC visita 1 captura gravidez corrente de forma",
  "  confiável. Os insumos acima (matern_bin, cuidado_provid_bin) são os mais",
  "  próximos disponíveis. Alternativas mais robustas:",
  "    (1) Presença de filho < 1 ano no domic_id (via pnadc_categ completo)",
  "    (2) Taxa de gravidez por UF × faixa_menor × ano via SINASC",
  "",
  "LOCALIZAÇÃO:",
  "  UF             Unidade Federativa (nome completo)",
  "  regiao         Macrorregião (Norte/Nordeste/Sudeste/Sul/Centro-Oeste)",
  "  sit_domic      Situação do domicílio: 1=Urbano, 2=Rural (original PNADC)",
  "  Ano            Ano de referência (factor original) | ano = inteiro",
  "",
  "IDENTIFICADORES E DESIGN AMOSTRAL:",
  "  UPA            Unidade Primária de Amostragem (cluster)",
  "  Estrato        Estrato amostral",
  "  pes_comcalib   Peso amostral calibrado (OBRIGATÓRIO em toda estimação)",
  "  domic_id       ID do domicílio (para joins com outros membros do domicílio)",
  "  pessoa_id      ID da pessoa",
  "  condno_domic   Condição no domicílio (cônjuge / filha / etc.)",
  "  categ_domic    Categoria do domicílio (C=choice:in_union; W=choice:wait)",
  "",
  "VARIÁVEIS BRUTAS DO PARCEIRO ADULTO (prefixo parc_ | NA se choice='wait'):",
  "  delta          ∆ — diferença de idade HEAD–CÔNJUGE (anos) [do modelo]",
  "  parc_idade     Idade do parceiro (formato original)",
  "  parc_sexo_bin  Sexo do parceiro",
  "  parc_parda_preta_bin  Cor/raça do parceiro",
  "  parc_ler_escrever     Alfabetização do parceiro",
  "  parc_trab_remun       Tipo de trabalho (categórica original)",
  "  parc_trab_remun_bin   Trabalho remunerado: 1=sim",
  "  parc_afastd_bin       Afastamento do trabalho",
  "  parc_horas_trab       Horas trabalhadas semanais",
  "  parc_rend             Renda bruta (R$) — proxy de w(∆) no modelo",
  "  parc_matern_bin       Licença-maternidade",
  "  parc_cuidado_provid   Cuidou de dependente",
  "  parc_cuidado_trab     Afastou-se por cuidados",
  "  parc_freq_esc         Frequência escolar do parceiro",
  "",
  "LOCALIZAÇÃO:",
  "  UF             Unidade Federativa (nome completo PNADC)",
  "  regiao         Macrorregião",
  "  regiao_f       regiao como factor (levels: Norte, Nordeste, Centro-Oeste,",
  "                 Sul, Sudeste — ordenado por prevalência decrescente)",
  "  sit_domic      Situação: 1=Urbano, 2=Rural (original PNADC)",
  "  urbano         1=Urbano, 0=Rural",
  "  Ano            Ano como factor original | ano = inteiro",
  "  sm_ano         Salário mínimo nominal vigente no ano",
  "",
  "NOTA SOBRE FORMALIDADE (F vs I):",
  "  A PNADC não permite distinguir uniões formais de informais ao nível",
  "  individual. A variável 'choice' identifica apenas in_union vs wait.",
  "  Para a distinção F/I, usar formal_rate.rds (ver abaixo).",
  "",
  "─────────────────────────────────────────────────────────────────────────────",
  "BASE 2: dc_rc_dcm (.rds / .csv)",
  "─────────────────────────────────────────────────────────────────────────────",
  "Fonte:    IBGE, Estatísticas do Registro Civil",
  "Cobertura: Brasil, 2003–2022",
  "Unidade:  Célula UF × ano × faixa_etária_noiva (censo administrativo)",
  sprintf("Linhas:   %s", format(nrow(dc_rc_dcm), big.mark = ".")),
  "",
  "VARIÁVEIS:",
  "  ano            Ano de registro",
  "  uf             UF (sigla)",
  "  idade_m        Faixa etária da noiva (original IBGE)",
  "  idade_m_num    Inteiro: 14=≤14, 15, 16, 17, 18=≥18",
  "  n_total_row    Contagem de casamentos nesta célula",
  "  is_minor_w     TRUE se noiva < 18",
  "  n_h_minor      Casamentos com noivo < 18 e noiva adulta (se disponível)",
  "  n_casamentos_2029  Casamentos de mulheres 20–29 na mesma UF × ano",
  "                     (denominador para controlar transição demográfica)",
  "  anos_contrib   Anos restantes até a noiva completar 18 (para estoque ponderado)",
  "                 14→4, 15→3, 16→2, 17→1, ≥18→0",
  "  rate_per_1k_2029  Taxa: n_total_row / n_casamentos_2029 × 1000",
  "  pos_lei2019    1 se ano >= 2019 (construída — necessária para estoque)",
  "  below_16       1 se idade_m_num < 16 (construída — necessária para estoque)",
  "  phi_F_active   1 se below_16 == 1 (indicador de zona de custo legal formal)",
  "",
  "─────────────────────────────────────────────────────────────────────────────",
  "TABELA AUXILIAR: formal_rate (.rds / .csv)",
  "─────────────────────────────────────────────────────────────────────────────",
  "Unidade:  Ano (nacional)",
  "Uso:      Join com dc_pnadc_dcm pela coluna 'ano' para decompor in_union",
  "          em F e I.",
  "",
  "  ano              Ano",
  "  rc_stock         Estoque sintético ponderado de casamentos formais infantis",
  "                   (cada casamento contribui por anos_contrib anos)",
  "  pnadc_stock      Estoque PNADC (formal + informal)",
  "  formal_rate      P(F | in_union) ≈ rc_stock / pnadc_stock",
  "  ratio_pnadc_rc   pnadc_stock / rc_stock (≈ 4–6×)",
  "  underreport_pct  (1 - formal_rate) × 100 — share de uniões não registradas",
  "  pos_lei2019      1 se ano >= 2019",
  "",
  "=============================================================================",
  "COMO USAR EM R",
  "=============================================================================",
  "library(tidyverse); library(srvyr)",
  "",
  "# Carregar",
  "pnadc <- readRDS('data/discrete_choice/dc_pnadc_dcm.rds')",
  "rc    <- readRDS('data/discrete_choice/dc_rc_dcm.rds')",
  "fr    <- readRDS('data/discrete_choice/formal_rate.rds')",
  "",
  "# Adicionar taxa de formalidade como proxy de P(F | in_union)",
  "pnadc <- pnadc |> left_join(fr |> select(ano, formal_rate), by = 'ano')",
  "",
  "# Design amostral (obrigatório)",
  "svy <- pnadc |>",
  "  as_survey_design(ids=UPA, strata=Estrato, weights=pes_comcalib)",
  "",
  "# Logit binário (W vs in_union) com design correto",
  "m1 <- svy |>",
  "  svyglm(I(choice == 'in_union') ~ a + p_proxy + delta +",
  "         rend_parceiro_sm + parda_preta_bin + urbano +",
  "         regiao_f + phi_F_active,",
  "         family = quasibinomial('logit'))",
  "",
  "# Para multinomial {F, I, W}: usar mlogit ou apollo",
  "# Estratégia de identificação F vs I:",
  "#   P(F | in_union, UF, ano) = formal_rate[UF, ano] (de formal_rate.rds)",
  "#   → construir variável latente ou usar mixture model",
  "============================================================================="
)

writeLines(codebook_lines, file.path(DATA_OUT_DIR, "codebook.txt"))
message("  ✓ codebook.txt")

# =============================================================================
# SUMÁRIO FINAL
# =============================================================================

cat("\n=== Outputs em:", DATA_OUT_DIR, "===\n\n")
cat(sprintf("  dc_pnadc_dcm : %s obs | in_union=%s | wait=%s\n",
            format(nrow(dc_pnadc_dcm), big.mark = "."),
            format(n_in_union, big.mark = "."),
            format(n_wait, big.mark = ".")))
cat(sprintf("    Idade média (in_union): %.1f anos\n",
            mean(dc_pnadc_dcm$a[dc_pnadc_dcm$choice == "in_union"], na.rm = TRUE)))
cat(sprintf("    Delta médio  (in_union): %.1f anos\n",
            mean(dc_pnadc_dcm$delta[dc_pnadc_dcm$choice == "in_union"], na.rm = TRUE)))
cat(sprintf("  dc_rc_dcm    : %s células\n",
            format(nrow(dc_rc_dcm), big.mark = ".")))
cat(sprintf("  formal_rate  : %d anos (%.0f%% a %.0f%% formalidade)\n",
            nrow(formal_rate),
            min(formal_rate$formal_rate, na.rm = TRUE) * 100,
            max(formal_rate$formal_rate, na.rm = TRUE) * 100))
cat("\n  codebook.txt — dicionário completo + exemplo de código R\n\n")

message("10_prep_discrete_choice.R concluído.")
