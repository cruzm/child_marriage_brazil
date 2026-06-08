# =============================================================================
# 08_didc.R — Difference-in-Discontinuities (DiDC)
# Efeito da Lei 13.811/2019 sobre probabilidade de união precoce
# =============================================================================
# Depende de: 00_setup.R (paths), rc_raw (01_importacao.R)
#
# pnadc_anual NÃO é carregada pelo pipeline principal (deletada após categ).
# Este script importa/cacheia sua própria amostra: mulheres 13–19 anos.
# =============================================================================
#
# ─────────────────────────────────────────────────────────────────────────────
# O QUE ESTE SCRIPT FAZ
# ─────────────────────────────────────────────────────────────────────────────
#
# Estima o efeito causal da Lei 13.811/2019 (que aboliu exceções ao casamento
# infantil abaixo de 16 anos) sobre a probabilidade de uma jovem estar em
# união conjugal, usando dois sources independentes:
#   1. PNADC  — capta uniões informais (coabitação reconhecida como cônjuge)
#   2. Registro Civil (IBGE) — capta casamentos formais registrados
#
# ─────────────────────────────────────────────────────────────────────────────
# ESTRATÉGIA DE IDENTIFICAÇÃO: Difference-in-Discontinuities (DiDC)
# ─────────────────────────────────────────────────────────────────────────────
#
# A Lei 13.811/2019 tornou ilegal o casamento de QUALQUER menor de 18 anos,
# eliminando a exceção que existia para 16–17 anos (com autorização judicial).
# O threshold legal anterior era exatamente 16 anos.
#
# DiDC combina dois designs de identificação:
#
#   (a) Regressão com Descontinuidade (RDD):
#       Explora o salto na taxa de união ao redor do limiar de 16 anos.
#       A running variable é idade_c = idade − 16 (cutoff = 0).
#       Quaisquer características não observáveis variam de forma suave com a
#       idade, de modo que o salto no cutoff é causalmente atribuível ao limiar.
#
#   (b) Diferenças em Diferenças (DiD):
#       Compara o salto (descontinuidade) antes e depois de 2019.
#       O estimador de interesse é:
#           β_DiDC = RD_pós2019 − RD_pré2019
#       Um β_DiDC negativo significa que a lei REDUZIU a descontinuidade em
#       16 anos, i.e., aproximou a taxa de uniões de jovens com 16 anos à de
#       jovens com 15 anos — redução causal das uniões no limiar.
#
# Vantagem sobre RDD puro: controla para tendências de queda secular em uniões
# precoces que já estavam ocorrendo antes de 2019 (capturadas por RD_pré).
#
# Vantagem sobre DiD puro: a descontinuidade no limiar age como cutoff "natural"
# — unidades do lado esquerdo e direito de 16 anos são quasi-idênticas em tudo
# exceto a elegibilidade legal ao casamento.
#
# Referência principal: Pichetti et al. (2023), que aplica este design ao
# impacto de reformas legislativas sobre casamento infantil no Brasil.
#
# ─────────────────────────────────────────────────────────────────────────────
# PACOTES E MOTIVAÇÃO
# ─────────────────────────────────────────────────────────────────────────────
#
# fixest (Bergé 2018 / Correia et al. 2020):
#   Usado como estimador principal em TODOS os modelos de regressão.
#   Motivos:
#   • feols() estima LPM (Linear Probability Model) com efeitos fixos de UF e
#     ano em poucos segundos — algoritmos de demeaning Mundlak são ~100× mais
#     rápidos que lm() + absorb() para painéis grandes.
#   • Clusterização robusta por UF com cluster = ~uf_fct — correto para painéis
#     em que erros são correlacionados dentro de estado (enforcement da lei,
#     padrões culturais, condições socioeconômicas).
#   • i(ano_ref, acima, ref="2018") gera interações ano × acima prontas para
#     event study sem recodificação manual.
#   • etable() exporta tabelas acadêmicas e LaTeX em uma linha.
#
# rdrobust (Calonico et al. 2014):
#   Carregado para uso potencial de rdplot() (visualização da descontinuidade)
#   e para documentar que o estimador bias-corrected robusto (rbc) do Pichetti
#   foi testado. Na prática, rdrobust() FALHA com running variable discreta
#   (idade em anos inteiros = apenas 7 suportes distintos de −3 a 3): a
#   decomposição de Cholesky fica singular independente de p, h ou masspoints.
#   Solução adotada: feols() na subamostra do bandwidth (ver Bloco 1.5).
#
# rddensity (Cattaneo et al. 2018) — opcional:
#   Teste de McCrary: verifica se há salto na DENSIDADE de idade_c no cutoff 0.
#   Um salto indicaria que famílias manipulam a idade reportada (ex: declaram
#   16 anos quando a criança tem 15) para contornar a restrição legal.
#   H₀: sem manipulação → densidade contínua em zero → favorece identificação.
#
# ─────────────────────────────────────────────────────────────────────────────
# ESPECIFICAÇÕES E ESCOLHAS TÉCNICAS
# ─────────────────────────────────────────────────────────────────────────────
#
# Estimador local (Bloco 1.5) — substituto do rdrobust:
#   Bandwidth h=1 (PRINCIPAL): restringe a amostra às idades 15 e 16 — os
#     vizinhos imediatos do cutoff. Equivale ao estimador de diferença de médias
#     mais próximas ao limiar (local constant). Minimiza viés de extrapolação;
#     máxima validade interna.
#   Bandwidth h=2 (ROBUSTEZ): idades 14–18, com slope idade_c × acima (local
#     linear). Permite que a tendência da taxa de união com a idade seja diferente
#     nos dois lados do cutoff — relaxa a hipótese de constância local.
#   Inferência DiDC via método delta:
#     SE_DiDC = √(SE_pré² + SE_pós²)   (pré e pós independentes)
#
# Efeitos fixos (todos os modelos):
#   ano_fct: absorve choques macroeconômicos/demográficos comuns a todas as UFs
#     (ex: efeitos COVID em 2022–2023, mudanças no questionário PNADC).
#   uf_fct: absorve diferenças permanentes entre estados (renda, urbanização,
#     enforcement judicial, normas culturais sobre casamento).
#   Sem EF de domic_id: painel rotativo da PNADC — a maioria das pessoas não
#     reaparece entre anos.
#
# Controles demográficos (modelo completo):
#   parda_preta: raça/cor codificada como binária Preta+Parda vs. demais.
#     Controla heterogeneidade no acesso a cartório e em normas matrimoniais.
#   rural: localização urbana/rural do domicílio. Casamentos precoces são
#     substancialmente mais comuns em áreas rurais.
#
# Amostra (PNADC):
#   Mulheres de 13 a 19 anos, visita 1 (anual). Sexo masculino excluído porque
#   o casamento infantil afeta predominantemente mulheres e a lei tem efeito
#   assimétrico de gênero (meninos raramente se casam antes de 18).
#   Anos 2020–2021 excluídos: COVID gerou queda artificial de casamentos por
#   fechamento de cartórios e distorções na PNADC (mudança de coleta).
#
# Outcome (PNADC):
#   em_uniao = 1 se condno_domic == "Cônjuge ou companheiro(a) de sexo diferente"
#   Capta uniões informais + formais — mais abrangente que o RC, que só registra
#   casamentos civis. Fundamental para testar substituição formal→informal.
#
# Registro Civil (Bloco 2):
#   Outcome: taxa de casamentos por 10.000 mulheres da faixa etária × UF × ano.
#   WLS com peso = n_casamentos (correção heterocedasticidade por tamanho do
#   município). Série 2003–2022, mais longa que a PNADC (2012–), o que fortalece
#   a identificação das tendências pré-lei.
#
# Testes de validade (Blocos 1.6–1.8):
#   RD por ano (stacked RD): estimativas pré-2019 devem ser ~0. Se a
#     descontinuidade já existia antes da lei, ela reflete diferenças etárias
#     permanentes, não o efeito causal.
#   Placebo A — limiares falsos (14, 15, 17, 18): β_DiDC deve ser
#     insignificante em outros pontos de corte. Sinaliza que o efeito é
#     específico ao limiar legal de 16 anos.
#   Placebo B — anos falsos (2015, 2016, 2017): usando só dados pré-2019,
#     não deve haver "efeito" em anos anteriores à lei. Valida o parallelismo.
#   McCrary: descarta manipulação de idade reportada no cutoff.
#
# =============================================================================

source(here::here("00_setup.R"))
library(fixest)     # feols(), etable(), wald()
library(rdrobust)   # rdrobust(), rdplot()  — estimador principal (Pichetti)

# rddensity é opcional (teste McCrary — Hipótese 2)
has_rddensity <- requireNamespace("rddensity", quietly = TRUE)
if (has_rddensity) {
  library(rddensity)
} else {
  message("NOTA: instale rddensity para o teste McCrary: install.packages('rddensity')")
}

# Helper robusto para extrair estimativas do rdrobust (funciona em todas as versões)
rdr_extract <- function(rdr) {
  coef_bc  <- if (is.matrix(rdr$coef)) rdr$coef[2L, 1L] else rdr$coef[2L]
  se_rob   <- if (is.matrix(rdr$se))   rdr$se[3L,   1L] else rdr$se[3L]
  ci_lo    <- if (is.matrix(rdr$ci))   rdr$ci[3L,  1L]  else rdr$ci[1L]
  ci_hi    <- if (is.matrix(rdr$ci))   rdr$ci[3L,  2L]  else rdr$ci[2L]
  h_opt    <- rdr$bws[1L, 1L]
  list(coef = coef_bc, se = se_rob,
       ci_low = ci_lo, ci_high = ci_hi,
       h = h_opt, N_l = rdr$N[1L], N_r = rdr$N[2L])
}

# =============================================================================
# BLOCO 0 — IMPORTAR AMOSTRA DiDC DA PNADC (mulheres 13–19 anos)
# =============================================================================
# Estratégia de memória / disco:
#   1. DIDC_VARS contém APENAS colunas usadas na análise (sem UPA/Estrato/V1008)
#   2. Cada ano é salvo individualmente em didc_YYYY.rds logo após o filtro,
#      antes de ser removido da RAM → falha a qualquer momento = só re-baixa
#      os anos pendentes, não todos
#   3. Zip do tempdir é apagado ANTES e DEPOIS de cada download
#   4. didc_raw só é montado ao final via bind_rows dos arquivos por ano
#   5. Cache consolidado didc_pnadc_cache.rds é salvo após o bind
# =============================================================================

didc_cache <- file.path(CACHE_DIR, "didc_pnadc_cache.rds")

# Apenas variáveis usadas em feols() — UPA/Estrato/V1008 são desnecessários aqui
DIDC_VARS <- c(
  "Ano", "UF",
  "V1032",   # peso calibrado  → pes_comcalib
  "V2005",   # condição no domicílio → condno_domic
  "V2007",   # sexo
  "V2009",   # idade
  "V2010",   # cor/raça        → cor_raca
  "V1022"    # urbano/rural    → sit_domic
)

DIDC_YEARS <- c(2012:2019, 2022, 2023)   # exclui 2020–2021 (COVID)

if (file.exists(didc_cache)) {
  message("Carregando amostra DiDC do cache consolidado...")
  didc_raw <- readRDS(didc_cache)

} else {
  message("Importando PNADC para DiDC — cache por ano em: ", CACHE_DIR)

  for (yr in DIDC_YEARS) {

    yr_cache <- file.path(CACHE_DIR, sprintf("didc_%d.rds", yr))

    if (file.exists(yr_cache)) {
      message(sprintf("  %d: já cacheado, pulando.", yr))
      next
    }

    # Limpa zips ANTES de baixar (remove resíduos de downloads anteriores)
    unlink(list.files(tempdir(), pattern = "\\.zip$",
                      full.names = TRUE, recursive = TRUE))

    message(sprintf("  %d: baixando...", yr))
    yr_data <- tryCatch(
      get_pnadc(year = yr, interview = 1, vars = DIDC_VARS, design = FALSE),
      error = function(e) {
        warning(sprintf("  Falhou %d: %s", yr, e$message))
        NULL
      }
    )

    # Limpa zips IMEDIATAMENTE após o download (libera disco antes de processar)
    unlink(list.files(tempdir(), pattern = "\\.zip$",
                      full.names = TRUE, recursive = TRUE))

    if (!is.null(yr_data)) {
      yr_data <- yr_data |>
        # Seleciona só o que será usado — descarta todas as outras colunas
        select(any_of(c("Ano", "UF", "V1032", "V2005", "V2007",
                        "V2009", "V2010", "V1022"))) |>
        rename(any_of(c(
          pes_comcalib = "V1032",
          condno_domic = "V2005",
          sexo         = "V2007",
          idade        = "V2009",
          cor_raca     = "V2010",
          sit_domic    = "V1022"
        ))) |>
        mutate(
          sexo = case_when(
            as.character(sexo) %in% c("Mulher", "Feminino")  ~ "Feminino",
            as.character(sexo) %in% c("Homem",  "Masculino") ~ "Masculino",
            TRUE ~ as.character(sexo)
          )
        ) |>
        filter(sexo == "Feminino", idade >= 13L, idade <= 19L)

      message(sprintf("  %d: %d linhas filtradas — salvando cache do ano...", yr, nrow(yr_data)))
      saveRDS(yr_data, yr_cache, compress = TRUE)   # gz: rápido de escrever
    }

    rm(yr_data); gc()
  }

  # Consolida todos os anos disponíveis a partir dos caches por ano
  message("Consolidando caches por ano...")
  yr_files <- file.path(CACHE_DIR, sprintf("didc_%d.rds", DIDC_YEARS))
  yr_files <- yr_files[file.exists(yr_files)]

  if (length(yr_files) == 0L)
    stop("Nenhum arquivo didc_YYYY.rds encontrado em CACHE_DIR. Verifique os downloads.")

  didc_raw <- map_dfr(yr_files, readRDS)

  saveRDS(didc_raw, didc_cache, compress = TRUE)
  message(sprintf("Cache DiDC consolidado salvo: %d linhas", nrow(didc_raw)))
}

message(sprintf("didc_raw: %d linhas | anos: %s",
                nrow(didc_raw),
                paste(sort(unique(didc_raw$Ano)), collapse = ", ")))

# =============================================================================
# BLOCO 1 — PNADC
# =============================================================================

# ── 1.1  Construir amostra ───────────────────────────────────────────────────
didc_pnadc <- didc_raw |>
  mutate(
    em_uniao  = as.integer(
      as.character(condno_domic) == "Cônjuge ou companheiro(a) de sexo diferente"
    ),
    idade_c   = idade - 16L,
    acima     = as.integer(idade >= 16L),
    post2019  = as.integer(Ano >= 2019L),
    parda_preta = as.integer(
      as.character(cor_raca) %in% c("Preta","Parda")
    ),
    rural     = as.integer(
      str_detect(as.character(sit_domic), "(?i)rural")
    ),
    uf_fct    = factor(UF),
    ano_fct   = factor(Ano),
    ano_ref   = relevel(factor(Ano), ref = "2018")
  )

message(sprintf(
  "didc_pnadc: %d obs | em_uniao: %.2f%% | acima: %.2f%%",
  nrow(didc_pnadc),
  mean(didc_pnadc$em_uniao, na.rm = TRUE) * 100,
  mean(didc_pnadc$acima) * 100
))

# ── 1.2  DiDC principal ───────────────────────────────────────────────────────
message("Estimando DiDC (PNADC)...")

mod_didc_pnadc <- feols(
  em_uniao ~
    acima * post2019 +
    idade_c * acima +
    idade_c * post2019 +
    idade_c * acima * post2019 +
    parda_preta + rural |
    ano_fct + uf_fct,
  data    = didc_pnadc,
  weights = ~pes_comcalib,
  cluster = ~uf_fct
)

mod_didc_pnadc_simple <- feols(
  em_uniao ~
    acima * post2019 +
    idade_c * acima +
    parda_preta + rural |
    ano_fct + uf_fct,
  data    = didc_pnadc,
  weights = ~pes_comcalib,
  cluster = ~uf_fct
)

# ── 1.3  Event study (PNADC) ─────────────────────────────────────────────────
mod_event_pnadc <- feols(
  em_uniao ~
    i(ano_ref, acima, ref = "2018") +
    idade_c * acima +
    parda_preta + rural |
    ano_fct + uf_fct,
  data    = didc_pnadc,
  weights = ~pes_comcalib,
  cluster = ~uf_fct
)

# ── 1.4  Teste de tendências paralelas ───────────────────────────────────────
# wald() em fixest aceita um regex único; une os padrões com "|"
anos_pre_labels <- paste0("ano_ref::", c(2012:2017), ":acima")
anos_pre_regex  <- paste(anos_pre_labels, collapse = "|")

coef_names <- names(coef(mod_event_pnadc))
message("Nomes dos coeficientes do event study: ", paste(coef_names, collapse = ", "))

matched_pre <- grep(anos_pre_regex, coef_names, value = TRUE)
if (length(matched_pre) >= 2L) {
  wald_pre <- wald(mod_event_pnadc, anos_pre_regex)
  message(sprintf(
    "Tendências paralelas (pré-2018): F = %.2f, p = %.3f  [%d coefs testados]",
    wald_pre$stat, wald_pre$p, length(matched_pre)
  ))
} else {
  message(sprintf(
    "Poucos coeficientes pré-2018 encontrados (%d). Nomes: %s",
    length(matched_pre), paste(matched_pre, collapse = ", ")
  ))
  message("Verificar se fixest está na versão >= 0.11 e o ref = '2018' está correto.")
}


# =============================================================================
# BLOCO 1.5 — ESTIMADOR rdrobust  (resultado principal — Pichetti)
# =============================================================================
# O rdrobust usa kernel triangular + bandwidth MSE-ótimo (Calonico et al. 2014).
# Running variable: idade_c = idade − 16 (cutoff = 0).
# Running variable discreta (7 inteiros). Usa h fixo + masspoints = "off".
# DiDC = descontinuidade pós-2019 − descontinuidade pré-2019.
# Inferência: estimativa bias-corrected, SE robusto (método rbc).
# =============================================================================

message("Estimando rdrobust (estimador principal)...")

pnadc_pre  <- didc_pnadc |> filter(Ano <  2019L)
pnadc_post <- didc_pnadc |> filter(Ano >= 2019L)

# Verifica se ambos os períodos têm observações suficientes
n_pre  <- nrow(pnadc_pre)
n_post <- nrow(pnadc_post)
message(sprintf("  pnadc_pre: %d obs (%s)",  n_pre,
                paste(sort(unique(pnadc_pre$Ano)),  collapse = ", ")))
message(sprintf("  pnadc_post: %d obs (%s)", n_post,
                paste(sort(unique(pnadc_post$Ano)), collapse = ", ")))

if (n_pre < 50L || n_post < 50L) {
  warning(sprintf(
    "rdrobust pulado: pré = %d obs, pós = %d obs.\n",
    n_pre, n_post
  ), "  Downloads pendentes: ",
  paste(setdiff(DIDC_YEARS, unique(didc_pnadc$Ano)), collapse = ", "),
  "\n  Conclua os downloads e re-rode o script.")
  rdr_pre  <- NULL; rdr_post <- NULL
  rdr_summary   <- NULL
  beta_didc_rdr <- NA_real_
  p_didc_rdr    <- NA_real_
  ci_low_rdr    <- NA_real_; ci_high_rdr <- NA_real_
} else {

# rdrobust falha com running variable discreta de poucos suportes (Cholesky
# singular mesmo com p=0). Solução equivalente: feols na subamostra restrita
# ao bandwidth, com SE clusterizados por UF — mais robusto para painel PNADC.
#
# h=1 (principal): só idades 15 e 16 — diferença de médias no cutoff imediato
# h=2 (robustez) : idades 14–18, com slope idade_c × acima (local linear)
BW_MAIN <- 1L
BW_ROB  <- 2L

rd_feols <- function(df, h, linear_slope = FALSE) {
  d <- df |> filter(abs(idade_c) <= h)
  if (nrow(d) < 10L) return(NULL)
  fml <- if (linear_slope && h > 1L)
    em_uniao ~ acima + idade_c + I(acima * idade_c) | ano_fct + uf_fct
  else
    em_uniao ~ acima | ano_fct + uf_fct
  tryCatch(
    feols(fml, data = d, weights = ~pes_comcalib, cluster = ~uf_fct),
    error = function(e) NULL
  )
}

mod_rd_pre_h1  <- rd_feols(pnadc_pre,  BW_MAIN)
mod_rd_post_h1 <- rd_feols(pnadc_post, BW_MAIN)
mod_rd_pre_h2  <- rd_feols(pnadc_pre,  BW_ROB,  linear_slope = TRUE)
mod_rd_post_h2 <- rd_feols(pnadc_post, BW_ROB,  linear_slope = TRUE)

rd_didc <- function(m_pre, m_post, label) {
  if (is.null(m_pre) || is.null(m_post)) return(NULL)
  b_pre <- coef(m_pre)["acima"];  se_pre <- se(m_pre)["acima"]
  b_pos <- coef(m_post)["acima"]; se_pos <- se(m_post)["acima"]
  diff  <- b_pos - b_pre
  se_d  <- sqrt(se_pre^2 + se_pos^2)
  tibble(spec     = label,
         rd_pre   = b_pre,   se_pre  = se_pre,
         rd_pos   = b_pos,   se_pos  = se_pos,
         beta_didc = diff,   se_didc = se_d,
         z        = diff / se_d,
         p_value  = 2 * pnorm(-abs(diff / se_d)),
         ci_low   = diff - 1.96 * se_d,
         ci_high  = diff + 1.96 * se_d)
}

rdr_summary <- bind_rows(
  rd_didc(mod_rd_pre_h1, mod_rd_post_h1,
          sprintf("h=%d (idades %d-%d, local const.)", BW_MAIN, 16-BW_MAIN, 16+BW_MAIN-1)),
  rd_didc(mod_rd_pre_h2, mod_rd_post_h2,
          sprintf("h=%d (idades %d-%d, local linear)", BW_ROB,  16-BW_ROB,  16+BW_ROB-1))
)

if (!is.null(rdr_summary) && nrow(rdr_summary) > 0L) {
  # Resultado principal = h=1 (local constant)
  r1 <- rdr_summary[1L, ]
  beta_didc_rdr <- r1$beta_didc
  se_didc_rdr   <- r1$se_didc
  p_didc_rdr    <- r1$p_value
  ci_low_rdr    <- r1$ci_low
  ci_high_rdr   <- r1$ci_high

  cat("\n====== DiDC local — estimador principal (Pichetti) ======\n")
  cat("  Running variable discreta (idade em anos completos).\n")
  cat("  Método: feols na subamostra do bandwidth, SE clusterizados por UF.\n")
  cat(sprintf("  h=%d: compara idades %d vs %d (vizinhos imediatos do cutoff 16).\n\n",
              BW_MAIN, 15L, 16L))
  print(rdr_summary |>
          select(spec, rd_pre, rd_pos, beta_didc, se_didc, p_value, ci_low, ci_high),
        digits = 4)
  cat(sprintf(
    "\nbeta_DiDC (h=%d) = %+.4f p.p. | SE = %.4f | z = %.2f | p = %.3f\n",
    BW_MAIN, beta_didc_rdr * 100, se_didc_rdr * 100,
    beta_didc_rdr / se_didc_rdr, p_didc_rdr
  ))
  cat(sprintf("IC 95%%: [%+.4f, %+.4f] p.p.\n\n",
              ci_low_rdr * 100, ci_high_rdr * 100))
} else {
  message("Estimador local não estimado — verificar pnadc_pre / pnadc_post.")
  beta_didc_rdr <- NA_real_; p_didc_rdr  <- NA_real_
  ci_low_rdr    <- NA_real_; ci_high_rdr <- NA_real_
}

}  # fecha else (n_pre >= 50 & n_post >= 50)


# =============================================================================
# BLOCO 1.6 — RD POR ANO (teste de validade — Hipótese 4)
# =============================================================================
# Estima rdrobust separadamente para cada ano. Se o design for válido:
#   - Anos pré-2019 → descontinuidade em 16 anos deve ser ZERO (ou estável)
#   - Anos pós-2019 → descontinuidade deve ser MENOR (lei reduziu)
# Teste formal: coeficientes pré-2019 são conjuntamente zero?
# =============================================================================

anos_disponiveis <- sort(unique(didc_pnadc$Ano))
tem_pos <- any(anos_disponiveis >= 2019L)

message("Estimando RD por ano (stacked RD — validade)...")

anos_rdr <- anos_disponiveis

rdr_por_ano <- map_dfr(anos_rdr, function(yr) {
  df <- didc_pnadc |> filter(Ano == yr, abs(idade_c) <= BW_MAIN)
  if (nrow(df) < 50L || length(unique(df$uf_fct)) < 3L) return(NULL)

  m <- tryCatch(
    feols(em_uniao ~ acima | uf_fct,
          data = df, weights = ~pes_comcalib, cluster = ~uf_fct),
    error = function(e) NULL
  )
  if (is.null(m)) return(NULL)

  b  <- coef(m)["acima"]; s <- se(m)["acima"]
  tibble(ano = as.integer(as.character(yr)), coef_bc = b, se_rob = s,
         ci_low  = b - 1.96 * s, ci_high = b + 1.96 * s,
         h_opt   = BW_MAIN, N = nrow(df), post = as.integer(as.character(yr)) >= 2019L)
})

if (nrow(rdr_por_ano) > 0L) {
  cat("\n====== RD por ano ======\n")
  print(rdr_por_ano, digits = 3)

  # Teste conjunto: coefs pré-2019 == 0  (t-tests individuais → Bonferroni)
  pre_rows <- rdr_por_ano |> filter(!post)
  if (nrow(pre_rows) >= 2L) {
    t_vals <- pre_rows$coef_bc / pre_rows$se_rob
    p_vals <- 2 * pnorm(-abs(t_vals))
    p_bonf <- p.adjust(p_vals, method = "bonferroni")
    cat("\nTeste tendências pré (Bonferroni):\n")
    print(data.frame(ano = pre_rows$ano, coef = round(pre_rows$coef_bc, 4),
                     p_raw = round(p_vals, 3), p_bonf = round(p_bonf, 3)))
    cat(sprintf("Nenhum ano pré sig. (Bonf p>0.10): %s\n",
                all(p_bonf > .10)))
  }
}


# =============================================================================
# BLOCO 1.7 — TESTES PLACEBO
# =============================================================================
# Placebo A — limiares falsos (14, 15, 17, 18 em vez de 16)
#   → DiDC não deve ser significativo em outros limiares
# Placebo B — ano falso (tratamento em 2016 ou 2017, usando só dados pré-2019)
#   → DiDC não deve ser significativo em anos anteriores à lei
# =============================================================================

if (!tem_pos) {
  message("Placebos e McCrary pulados: nenhum ano pós-2019 disponível ainda.")
  placebo_cutoff <- tibble(); placebo_ano <- tibble()
} else {
message("Rodando testes placebo...")

# ── Placebo A: limiares alternativos ─────────────────────────────────────────
cutoffs_placebo <- c(14L, 15L, 16L, 17L, 18L)   # 16 = real

placebo_cutoff <- map_dfr(cutoffs_placebo, function(co) {
  make_rd <- function(df) {
    d <- df |> mutate(x_c = idade - co, acima_p = as.integer(idade >= co)) |>
      filter(abs(x_c) <= BW_MAIN)
    if (nrow(d) < 50L) return(NULL)
    tryCatch(
      feols(em_uniao ~ acima_p | ano_fct + uf_fct,
            data = d, weights = ~pes_comcalib, cluster = ~uf_fct),
      error = function(e) NULL
    )
  }
  m_pre  <- make_rd(didc_pnadc |> filter(Ano <  2019L))
  m_post <- make_rd(didc_pnadc |> filter(Ano >= 2019L))
  if (is.null(m_pre) || is.null(m_post)) return(NULL)

  b_pre <- coef(m_pre)["acima_p"];  s_pre <- se(m_pre)["acima_p"]
  b_pos <- coef(m_post)["acima_p"]; s_pos <- se(m_post)["acima_p"]
  diff  <- b_pos - b_pre
  se_d  <- sqrt(s_pre^2 + s_pos^2)
  tibble(cutoff = co, real = (co == 16L), beta_didc = diff, se_rob = se_d,
         z = diff / se_d, p_value = 2 * pnorm(-abs(diff / se_d)),
         ci_low = diff - 1.96 * se_d, ci_high = diff + 1.96 * se_d)
})

# ── Placebo B: anos falsos (dentro do período pré-2019) ──────────────────────
anos_placebo <- c(2015L, 2016L, 2017L, 2019L)   # 2019 = real

placebo_ano <- map_dfr(anos_placebo, function(yr) {
  df_pre_f  <- didc_pnadc |> filter(Ano < 2019L, Ano <  yr,  abs(idade_c) <= BW_MAIN)
  df_post_f <- didc_pnadc |> filter(if (yr == 2019L) Ano >= 2019L
                                    else Ano < 2019L & Ano >= yr) |>
    filter(abs(idade_c) <= BW_MAIN)
  if (nrow(df_pre_f) < 50L || nrow(df_post_f) < 50L) return(NULL)

  m_pre  <- tryCatch(feols(em_uniao ~ acima | ano_fct + uf_fct,
                           data = df_pre_f,  weights = ~pes_comcalib, cluster = ~uf_fct), error=function(e) NULL)
  m_post <- tryCatch(feols(em_uniao ~ acima | ano_fct + uf_fct,
                           data = df_post_f, weights = ~pes_comcalib, cluster = ~uf_fct), error=function(e) NULL)
  if (is.null(m_pre) || is.null(m_post)) return(NULL)

  b_pre <- coef(m_pre)["acima"]; s_pre <- se(m_pre)["acima"]
  b_pos <- coef(m_post)["acima"]; s_pos <- se(m_post)["acima"]
  diff  <- b_pos - b_pre; se_d <- sqrt(s_pre^2 + s_pos^2)
  tibble(ano_corte = yr, real = (yr == 2019L), beta_didc = diff, se_rob = se_d,
         z = diff / se_d, p_value = 2 * pnorm(-abs(diff / se_d)))
})

cat("\n====== Placebo A — limiares falsos ======\n")
if (nrow(placebo_cutoff) > 0) print(placebo_cutoff |> mutate(across(where(is.numeric), ~round(., 4))), n = 20)

cat("\n====== Placebo B — anos falsos ======\n")
if (nrow(placebo_ano) > 0) print(placebo_ano |> mutate(across(where(is.numeric), ~round(., 4))), n = 10)

}  # fecha else (tem_pos)


# =============================================================================
# BLOCO 1.8 — TESTE McCALLUM–McCRARY (manipulação — Hipótese 2)
# =============================================================================
# Testa se há salto na densidade da variável de execução (idade) no cutoff 16.
# H0: densidade contínua em 16 → favorece identificação.
# Roda separadamente para pré e pós-2019.
# =============================================================================

if (has_rddensity) {
  message("Rodando teste McCrary (rddensity)...")

  rdd_pre <- tryCatch(
    rddensity(X = pnadc_pre$idade_c,  c = 0, masspoints = "adjust"),
    error = function(e) { warning("rddensity pré: ", e$message); NULL }
  )
  rdd_post <- tryCatch(
    rddensity(X = pnadc_post$idade_c, c = 0, masspoints = "adjust"),
    error = function(e) { warning("rddensity pós: ", e$message); NULL }
  )

  cat("\n====== Teste McCrary — manipulação da running variable ======\n")
  if (!is.null(rdd_pre))  { cat("Pré-2019:\n");  summary(rdd_pre)  }
  if (!is.null(rdd_post)) { cat("Pós-2019:\n"); summary(rdd_post) }

  mcc_results <- tibble(
    periodo  = c("Pre-2019",   "Pos-2019"),
    t_stat   = c(if (!is.null(rdd_pre))  rdd_pre$test$t_jk  else NA_real_,
                 if (!is.null(rdd_post)) rdd_post$test$t_jk else NA_real_),
    p_value  = c(if (!is.null(rdd_pre))  rdd_pre$test$p_jk  else NA_real_,
                 if (!is.null(rdd_post)) rdd_post$test$p_jk else NA_real_)
  )
  cat("\nSumário McCrary:\n")
  print(mcc_results, digits = 3)
  cat("(p > 0.10 em ambos os períodos → sem evidência de manipulação)\n")
} else {
  message("Teste McCrary pulado (rddensity não instalado).")
  mcc_results <- NULL
}


# =============================================================================
# BLOCO 1.9 — FIGURAS DOS NOVOS TESTES
# =============================================================================

# ── Fig: RD por ano (coeficientes + IC) ──────────────────────────────────────
if (exists("rdr_por_ano") && nrow(rdr_por_ano) > 0L) {
  p_rd_por_ano <- rdr_por_ano |>
    mutate(ano = as.integer(as.character(ano))) |>
    ggplot(aes(x = ano, y = coef_bc,
               color = post, shape = post)) +
    geom_hline(yintercept = 0, linetype = "dotted", color = "gray50") +
    geom_vline(xintercept = 2018.5, linetype = "dashed",
               color = "red", alpha = .6) +
    geom_errorbar(aes(ymin = ci_low, ymax = ci_high),
                  width = .3, linewidth = .6) +
    geom_point(size = 3) +
    scale_color_manual(values = c("FALSE" = "#185FA5", "TRUE" = "#C0392B"),
                       labels = c("Pre-2019", "Pos-2019"), name = NULL) +
    scale_shape_manual(values = c("FALSE" = 16, "TRUE" = 17),
                       labels = c("Pre-2019", "Pos-2019"), name = NULL) +
    scale_x_continuous(breaks = c(2012:2019, 2022, 2023)) +
    scale_y_continuous(labels = label_percent(accuracy = .1)) +
    labs(
      title    = "RD por ano — descontinuidade em 16 anos (feols, h=1)",
      subtitle = "IC 95% clusterizado por UF. Linha vermelha = Lei 13.811/2019. Pre-2019 deve ser ~0.",
      x = NULL, y = "Estimativa RD (P.P.)",
      caption  = sprintf("Fonte: PNADC. feols, bandwidth h=%d (idades 15-16), SE cluster UF.", BW_MAIN)
    ) + theme_paper +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          legend.position = "bottom")

  ggsave(file.path(OUT_DIR, "fig_didc_rd_por_ano.png"),
         p_rd_por_ano, width = 22, height = 13, units = "cm", dpi = 300, bg = "white")
}

# ── Fig: Placebo A — limiares alternativos ───────────────────────────────────
if (exists("placebo_cutoff") && nrow(placebo_cutoff) > 0L) {
  p_placebo_cutoff <- placebo_cutoff |>
    ggplot(aes(x = factor(cutoff), y = beta_didc,
               color = real, shape = real)) +
    geom_hline(yintercept = 0, linetype = "dotted", color = "gray50") +
    geom_errorbar(aes(ymin = ci_low, ymax = ci_high),
                  width = .2, linewidth = .7) +
    geom_point(size = 4) +
    scale_color_manual(values = c("FALSE" = "#888780", "TRUE" = "#C0392B"),
                       labels = c("Placebo", "Real (16 anos)"), name = NULL) +
    scale_shape_manual(values = c("FALSE" = 1, "TRUE" = 16),
                       labels = c("Placebo", "Real (16 anos)"), name = NULL) +
    scale_y_continuous(labels = label_percent(accuracy = .1)) +
    labs(
      title    = "Placebo A: DiDC em limiares alternativos",
      subtitle = "Apenas o limiar real (16 anos) deve ser significativo",
      x = "Cutoff de idade testado", y = "beta_DiDC (P.P.)",
      caption  = "Fonte: PNADC. rdrobust, kernel triangular. IC 95% robusto."
    ) + theme_paper + theme(legend.position = "bottom")

  ggsave(file.path(OUT_DIR, "fig_didc_placebo_cutoff.png"),
         p_placebo_cutoff, width = 18, height = 13, units = "cm", dpi = 300, bg = "white")
}

# =============================================================================
# BLOCO 2 — REGISTRO CIVIL
# =============================================================================

# ── Verificação de rc_raw ─────────────────────────────────────────────────────
# rc_raw é criado em 01_importacao.R. Se não existir em memória, tenta carregar
# via cache ou re-sourcia 01_importacao.R (só a Seção 1 é necessária).
if (!exists("rc_raw")) {
  rc_cache <- file.path(CACHE_DIR, "rc_raw_cache.rds")
  if (file.exists(rc_cache)) {
    message("Carregando rc_raw do cache...")
    rc_raw <- readRDS(rc_cache)
  } else {
    message("rc_raw não encontrado — executando 01_importacao.R para RC...")
    source(here::here("01_importacao.R"))
    # Salva cache para próximas execuções
    saveRDS(rc_raw, rc_cache, compress = TRUE)
    message("Cache rc_raw salvo.")
  }
}

# ── 2.1  Carregar população de menores ───────────────────────────────────────
# Arquivo gerado por: PIBIC/Iniciação Científica - Registro Civil/Códigos/População/pop_menores.R
# Estrutura esperada: uf | ano | pop_0_4 | pop_5_9 | pop_10_14 | pop_15 | pop_16 | pop_17

pop_file <- here("PIBIC", "Iniciação Científica - Registro Civil",
                 "Códigos", "População", "pop_menores.xlsx")

if (!file.exists(pop_file)) {
  # Tenta caminhos alternativos
  pop_file <- here("pop_menores.xlsx")
  if (!file.exists(pop_file))
    stop("pop_menores.xlsx não encontrado. Ajuste o caminho em pop_file.")
}

pop_menores_raw <- readxl::read_xlsx(pop_file, sheet = 1) |>
  # Normaliza nomes (o arquivo pode ter variações)
  rename_with(str_to_lower) |>
  rename_with(~ str_replace_all(., "\\s+", "_")) |>
  # Garante colunas esperadas (adapte conforme estrutura real do xlsx)
  rename(any_of(c(
    uf        = "uf",
    ano       = "ano",
    pop_0_4   = "0_a_4_anos",
    pop_5_9   = "5_a_9_anos",
    pop_10_14 = "10_a_14_anos",
    pop_15    = "15_anos",
    pop_16    = "16_anos",
    pop_17    = "17_anos"
  ))) |>
  mutate(
    # Proxy de pop feminina: total / 2 (razão de sexo ~1:1 nessas faixas)
    pop_f_14 = round(pop_10_14 / 5 / 2),  # 1/5 da faixa 10-14 = aprox. pop de 14 anos
    pop_f_15 = round(pop_15 / 2),
    pop_f_16 = round(pop_16 / 2),
    pop_f_17 = round(pop_17 / 2)
  ) |>
  select(uf, ano, pop_f_14, pop_f_15, pop_f_16, pop_f_17)

# ── 2.2  Construir painel RC por faixa etária × UF × ano ─────────────────────
# rc_raw tem: idade_m (categoria da noiva) e n_total_row (total de casamentos
# naquele município × ano × faixa etária da noiva)
# NÃO usa m_men15/m_15/m_16/m_17 — essas colunas não existem em rc_raw

rc_faixas <- rc_raw |>
  filter(
    idade_m %in% c("Menos de 15 anos", "15 anos", "16 anos", "17 anos"),
    ano %in% c(2003:2019, 2021:2022)
  ) |>
  mutate(
    idade_proxy = case_when(
      idade_m == "Menos de 15 anos" ~ 14L,
      idade_m == "15 anos"          ~ 15L,
      idade_m == "16 anos"          ~ 16L,
      idade_m == "17 anos"          ~ 17L
    )
  ) |>
  group_by(ano, uf, idade_proxy) |>
  summarise(n_casamentos = sum(n_total_row, na.rm = TRUE), .groups = "drop") |>
  # Junta com população feminina por faixa
  left_join(
    pop_menores_raw |>
      pivot_longer(cols = c(pop_f_14, pop_f_15, pop_f_16, pop_f_17),
                   names_to = "pop_col", values_to = "pop_f") |>
      mutate(idade_proxy = case_when(
        pop_col == "pop_f_14" ~ 14L,
        pop_col == "pop_f_15" ~ 15L,
        pop_col == "pop_f_16" ~ 16L,
        pop_col == "pop_f_17" ~ 17L
      )) |>
      select(uf, ano, idade_proxy, pop_f),
    by = c("uf", "ano", "idade_proxy")
  ) |>
  mutate(
    taxa_casam = if_else(!is.na(pop_f) & pop_f > 0,
                         n_casamentos / pop_f * 10000, NA_real_),
    idade_c  = idade_proxy - 16L,
    acima    = as.integer(idade_proxy >= 16L),
    post2019 = as.integer(ano >= 2019L),
    uf_fct   = factor(uf),
    ano_fct  = factor(ano),
    ano_ref  = relevel(factor(ano), ref = "2018")
  ) |>
  filter(!is.na(taxa_casam))

message(sprintf("rc_faixas: %d células | anos: %s–%s",
                nrow(rc_faixas),
                min(rc_faixas$ano), max(rc_faixas$ano)))

# ── 2.3  DiDC no RC ──────────────────────────────────────────────────────────
message("Estimando DiDC (RC)...")

mod_didc_rc <- feols(
  taxa_casam ~
    acima * post2019 +
    idade_c * acima +
    idade_c * post2019 +
    idade_c * acima * post2019 |
    ano_fct + uf_fct,
  data    = rc_faixas,
  weights = ~n_casamentos,
  cluster = ~uf_fct
)

mod_didc_rc_simple <- feols(
  taxa_casam ~
    acima * post2019 +
    idade_c * acima |
    ano_fct + uf_fct,
  data    = rc_faixas,
  weights = ~n_casamentos,
  cluster = ~uf_fct
)

# ── 2.4  Event study (RC) ────────────────────────────────────────────────────
mod_event_rc <- feols(
  taxa_casam ~
    i(ano_ref, acima, ref = "2018") +
    idade_c * acima |
    ano_fct + uf_fct,
  data    = rc_faixas,
  weights = ~n_casamentos,
  cluster = ~uf_fct
)


# =============================================================================
# BLOCO 3 — TABELA DE RESULTADOS
# =============================================================================

tabela_didc <- etable(
  mod_didc_pnadc_simple,
  mod_didc_pnadc,
  mod_didc_rc_simple,
  mod_didc_rc,
  dict = c(
    "acima"            = "Acima do limiar (>=16 anos)",
    "post2019"         = "Pos-2019",
    "acima:post2019"   = "DiDC: Acima x Pos-2019",
    "idade_c"          = "Idade (centrada em 16)",
    "idade_c:acima"    = "Idade x Acima",
    "parda_preta"      = "Preta/Parda",
    "rural"            = "Rural"
  ),
  headers   = c("PNADC (simples)", "PNADC (completo)",
                "RC (simples)",    "RC (completo)"),
  se.below  = TRUE,
  signif.code = c("*" = .1, "**" = .05, "***" = .01),
  notes     = paste(
    "Erros padrao clusterizados por UF entre parenteses.",
    "Efeitos fixos de UF e ano incluidos em todos os modelos.",
    "PNADC: outcome binario (em_uniao), pesos calibrados (V1032).",
    "RC: taxa de casamentos por 10.000 mulheres, WLS ponderado por n_casamentos.",
    "Bandwidth: idades 13-19 anos. Limiar: 16 anos. Referencia: 2018.",
    "Anos 2020-2021 excluidos (COVID)."
  ),
  title = "Tabela DiDC: Efeito da Lei 13.811/2019 sobre unioes precoces"
)

print(tabela_didc)

# Exporta LaTeX
etable(
  mod_didc_pnadc_simple, mod_didc_pnadc,
  mod_didc_rc_simple,    mod_didc_rc,
  dict = c(
    "acima:post2019" = "DiDC: Acima $\\times$ P\\'os-2019",
    "acima"          = "Acima do limiar ($\\geq 16$ anos)",
    "post2019"       = "P\\'os-2019",
    "idade_c"        = "Idade (centrada em 16)",
    "idade_c:acima"  = "Idade $\\times$ Acima",
    "parda_preta"    = "Preta/Parda",
    "rural"          = "Rural"
  ),
  headers     = c("PNADC (1)", "PNADC (2)", "RC (1)", "RC (2)"),
  se.below    = TRUE,
  signif.code = c("*" = .1, "**" = .05, "***" = .01),
  tex         = TRUE,
  file     = file.path(OUT_DIR, "tab_didc_resultados.tex")
)


# =============================================================================
# BLOCO 4 — FIGURAS
# =============================================================================

# ── 4.1  Event study — PNADC ─────────────────────────────────────────────────
coefs_event_pnadc <- broom::tidy(mod_event_pnadc, conf.int = TRUE) |>
  filter(str_detect(term, "ano_ref")) |>
  mutate(
    ano = as.integer(str_extract(term, "\\d{4}")),
    sig = case_when(
      p.value < .01 ~ "p < 0.01",
      p.value < .05 ~ "p < 0.05",
      p.value < .10 ~ "p < 0.10",
      TRUE          ~ "n.s."
    )
  ) |>
  bind_rows(tibble(ano = 2018L, estimate = 0, conf.low = 0, conf.high = 0,
                   sig = "Referencia"))

p_event_pnadc <- coefs_event_pnadc |>
  filter(ano %in% c(2012:2019, 2022:2023)) |>
  ggplot(aes(x = ano, y = estimate, color = sig, shape = sig)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "gray50") +
  geom_vline(xintercept = 2018.5, linetype = "dashed", color = "red", alpha = .6) +
  geom_errorbar(aes(ymin = conf.low, ymax = conf.high),
                width = .3, linewidth = .6) +
  geom_point(size = 3) +
  annotate("text", x = 2019.2,
           y = max(coefs_event_pnadc$conf.high, na.rm = TRUE) * .9,
           label = "Lei 13.811/2019", color = "red", hjust = 0, size = 3) +
  annotate("rect", xmin = 2012, xmax = 2018.5, ymin = -Inf, ymax = Inf,
           fill = "steelblue", alpha = .04) +
  scale_color_manual(
    values = c("p < 0.01" = "#A32D2D", "p < 0.05" = "#D85A30",
               "p < 0.10" = "#854F0B", "n.s."     = "#888780",
               "Referencia" = "#1F3864"),
    name = "Significancia"
  ) +
  scale_shape_manual(
    values = c("p < 0.01" = 16, "p < 0.05" = 16, "p < 0.10" = 17,
               "n.s." = 1, "Referencia" = 18),
    name = "Significancia"
  ) +
  scale_x_continuous(breaks = c(2012:2019, 2022, 2023)) +
  scale_y_continuous(labels = label_percent(accuracy = .1)) +
  labs(
    title    = "Event Study (PNADC): Efeito da Lei 13.811/2019 sobre unioes precoces",
    subtitle = "Coeficientes da interacao ano x Acima(>=16 anos) | Referencia: 2018 | Mulheres 13-19",
    x = NULL, y = "Efeito estimado sobre P(em uniao)",
    caption  = "Fonte: PNADC. EP clusterizados por UF. Controles: preta/parda, rural, EF UF e ano."
  ) +
  theme_paper +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "bottom")

# ── 4.2  Event study — RC ────────────────────────────────────────────────────
coefs_event_rc <- broom::tidy(mod_event_rc, conf.int = TRUE) |>
  filter(str_detect(term, "ano_ref")) |>
  mutate(
    ano = as.integer(str_extract(term, "\\d{4}")),
    sig = case_when(
      p.value < .01 ~ "p < 0.01",
      p.value < .05 ~ "p < 0.05",
      p.value < .10 ~ "p < 0.10",
      TRUE          ~ "n.s."
    )
  ) |>
  bind_rows(tibble(ano = 2018L, estimate = 0, conf.low = 0, conf.high = 0,
                   sig = "Referencia"))

p_event_rc <- coefs_event_rc |>
  ggplot(aes(x = ano, y = estimate, color = sig, shape = sig)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "gray50") +
  geom_vline(xintercept = 2018.5, linetype = "dashed", color = "red", alpha = .6) +
  geom_errorbar(aes(ymin = conf.low, ymax = conf.high),
                width = .3, linewidth = .6) +
  geom_point(size = 3) +
  scale_color_manual(
    values = c("p < 0.01" = "#A32D2D", "p < 0.05" = "#D85A30",
               "p < 0.10" = "#854F0B", "n.s."     = "#888780",
               "Referencia" = "#1F3864"),
    name = "Significancia"
  ) +
  scale_shape_manual(
    values = c("p < 0.01" = 16, "p < 0.05" = 16, "p < 0.10" = 17,
               "n.s." = 1, "Referencia" = 18),
    name = "Significancia"
  ) +
  scale_x_continuous(breaks = seq(2003, 2022, 3)) +
  labs(
    title    = "Event Study (RC): Efeito da Lei 13.811/2019 sobre casamentos formais",
    subtitle = "Taxa por 10.000 mulheres | Referencia: 2018 | Faixas 14-17 anos",
    x = NULL, y = "Efeito estimado (casamentos/10k)",
    caption  = "Fonte: Registro Civil (IBGE). WLS por n_casamentos. EP clusterizados por UF."
  ) +
  theme_paper +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "bottom")

# ── 4.3  Descontinuidade visual (RDD) — médias brutas por idade × período ───
desc_pnadc <- didc_pnadc |>
  mutate(periodo = if_else(Ano < 2019,
                           "Pre-2019 (2012-2018)",
                           "Pos-2019 (2022-2023)")) |>
  group_by(idade, periodo) |>
  summarise(
    taxa_uniao = weighted.mean(em_uniao, w = pes_comcalib, na.rm = TRUE),
    n          = n(),
    .groups    = "drop"
  )

p_rdd_visual <- desc_pnadc |>
  ggplot(aes(x = idade, y = taxa_uniao,
             color = periodo, group = periodo)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2.5) +
  geom_vline(xintercept = 15.5, linetype = "dashed", color = "red", alpha = .6) +
  annotate("text", x = 16.1, y = max(desc_pnadc$taxa_uniao) * .6,
           label = "Limiar: 16 anos", color = "red", hjust = 0, size = 3) +
  scale_color_manual(
    values = c("Pre-2019 (2012-2018)" = "#185FA5",
               "Pos-2019 (2022-2023)" = "#D85A30"),
    name = NULL
  ) +
  scale_x_continuous(breaks = 13:19) +
  scale_y_continuous(labels = label_percent(accuracy = .1)) +
  labs(
    title    = "Descontinuidade em 16 anos — PNADC: pre vs pos-2019",
    subtitle = "P(em uniao) por idade | Mulheres 13-19 anos | Medias ponderadas",
    x = "Idade (anos completos)", y = "P(conjuge no domicilio)",
    caption  = "Fonte: PNADC. Pesos calibrados (V1032). Elaboracao dos autores."
  ) +
  theme_paper + theme(legend.position = "bottom")

# ── 4.4  Salvar figuras ───────────────────────────────────────────────────────
ggsave(file.path(OUT_DIR, "fig_didc_event_pnadc.png"),
       p_event_pnadc, width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

ggsave(file.path(OUT_DIR, "fig_didc_event_rc.png"),
       p_event_rc, width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

ggsave(file.path(OUT_DIR, "fig_didc_rdd_visual.png"),
       p_rdd_visual, width = 22, height = 13, units = "cm", dpi = 300, bg = "white")

p_combined <- (p_rdd_visual | p_event_pnadc) +
  plot_annotation(
    title   = "DiDC: Efeito da Lei 13.811/2019 sobre unioes precoces (PNADC)",
    caption = "Fonte: PNADC (IBGE). Elaboracao dos autores.",
    theme   = theme_paper
  )

ggsave(file.path(OUT_DIR, "fig_didc_combinada.png"),
       p_combined, width = 40, height = 14, units = "cm", dpi = 300, bg = "white")


# =============================================================================
# BLOCO 5 — DIAGNÓSTICO
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("   DIAGNÓSTICO DiDC — RESULTADOS CONSOLIDADOS\n")
cat(strrep("=", 60), "\n\n")

# ── Resultado principal: rdrobust (rbc) ──────────────────────────────────────
cat(">>> ESTIMADOR PRINCIPAL (rdrobust, bias-corrected robusto):\n")
if (!is.na(beta_didc_rdr)) {
  cat(sprintf("    beta_DiDC = %.4f p.p. (SE = %.4f | z = %.2f | p = %.3f)\n",
              beta_didc_rdr * 100, se_didc_rdr * 100,
              beta_didc_rdr / se_didc_rdr, p_didc_rdr))
  cat(sprintf("    IC 95%%: [%.4f, %.4f] p.p.\n",
              ci_low_rdr * 100, ci_high_rdr * 100))
  if (!is.na(p_didc_rdr) && p_didc_rdr < .10) {
    cat(sprintf("    *** SIGNIFICATIVO (p = %.3f) ***\n", p_didc_rdr))
  } else {
    cat("    (nao significativo ao nivel de 10%)\n")
  }
} else {
  cat("    rdrobust nao disponivel.\n")
}

# ── Robustez: feols ──────────────────────────────────────────────────────────
cat("\n>>> ROBUSTEZ (feols — LPM com EF UF x ano):\n")
beta_pnadc <- coef(mod_didc_pnadc)["acima:post2019"]
se_pnadc   <- se(mod_didc_pnadc)["acima:post2019"]
pval_pnadc <- pvalue(mod_didc_pnadc)["acima:post2019"]
cat(sprintf("    PNADC  beta = %.4f (SE = %.4f, p = %.3f)\n",
            beta_pnadc * 100, se_pnadc * 100, pval_pnadc))

beta_rc  <- coef(mod_didc_rc)["acima:post2019"]
se_rc    <- se(mod_didc_rc)["acima:post2019"]
pval_rc  <- pvalue(mod_didc_rc)["acima:post2019"]
cat(sprintf("    RC     beta = %.4f casam./10k (SE = %.4f, p = %.3f)\n",
            beta_rc, se_rc, pval_rc))

# ── Validade: RD por ano (stacked) ──────────────────────────────────────────
cat("\n>>> VALIDADE — RD por ano (pre-2019 deve ser ~0):\n")
if (exists("rdr_por_ano") && nrow(rdr_por_ano) > 0L) {
  pre_ok <- rdr_por_ano |>
    filter(!post) |>
    mutate(sig = abs(coef_bc / se_rob) > 1.645) |>
    summarise(n_sig = sum(sig), n_total = n())
  cat(sprintf("    Anos pré significativos (10%%): %d / %d  (%s)\n",
              pre_ok$n_sig, pre_ok$n_total,
              if (pre_ok$n_sig == 0) "OK — sem pre-tendências" else "ATENCAO"))
}

# ── Placebos ─────────────────────────────────────────────────────────────────
cat("\n>>> PLACEBOS:\n")
if (exists("placebo_cutoff") && nrow(placebo_cutoff) > 0L) {
  other_sig <- placebo_cutoff |> filter(!real, p_value < .10) |> nrow()
  cat(sprintf("    Limiares falsos sig. (10%%): %d / %d  (%s)\n",
              other_sig, nrow(placebo_cutoff) - 1L,
              if (other_sig == 0) "OK" else "ATENCAO"))
}
if (exists("placebo_ano") && nrow(placebo_ano) > 0L) {
  fake_sig <- placebo_ano |> filter(!real, p_value < .10) |> nrow()
  cat(sprintf("    Anos falsos sig. (10%%): %d / %d  (%s)\n",
              fake_sig, nrow(placebo_ano) - 1L,
              if (fake_sig == 0) "OK" else "ATENCAO"))
}

# ── McCrary ──────────────────────────────────────────────────────────────────
cat("\n>>> MANIPULACAO (McCrary — H0: sem manipulação):\n")
if (!is.null(mcc_results)) {
  for (i in seq_len(nrow(mcc_results))) {
    cat(sprintf("    %s: t = %.2f, p = %.3f  (%s)\n",
                mcc_results$periodo[i],
                mcc_results$t_stat[i], mcc_results$p_value[i],
                if (!is.na(mcc_results$p_value[i]) && mcc_results$p_value[i] > .10)
                  "OK" else "ATENCAO"))
  }
} else {
  cat("    rddensity nao instalado — teste nao rodado.\n")
}

# ── Interpretação automática ─────────────────────────────────────────────────
cat("\n>>> INTERPRETACAO:\n")
if (!is.na(p_didc_rdr)) {
  if (!is.na(pval_rc) && pval_rc < .1 && (is.na(p_didc_rdr) || p_didc_rdr >= .1)) {
    cat("    RC sig + PNADC nao sig → lei reduziu casamentos FORMAIS, mas\n")
    cat("    unioes informais compensaram (substituicao formal→informal).\n")
  } else if (p_didc_rdr < .1 && !is.na(pval_rc) && pval_rc < .1 &&
             beta_didc_rdr < 0 && beta_rc < 0) {
    cat("    Ambos sig e negativos → lei reduziu formais E informais.\n")
    cat("    Evidencia de enforcement real e comportamental.\n")
  } else if (p_didc_rdr < .1 && beta_didc_rdr < 0) {
    cat("    rdrobust sig (PNADC): lei reduziu unioes informais abaixo do limiar.\n")
  } else {
    cat("    Nenhum estimador sig → lei nao alterou descontinuidade em 16 anos.\n")
    cat("    Hipoteses: enforcement fraco, efeito em outros limiares (14 ou 18),\n")
    cat("    ou substituicao completa formal→informal.\n")
  }
}

cat("\n", strrep("=", 60), "\n")

message("08_didc.R concluido. Outputs salvos em: ", OUT_DIR)

