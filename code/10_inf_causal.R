# =============================================================================
# 09_did_robustez.R
# Efeito da Lei 13.811/2019 sobre Casamento Infantil — Análise de Robustez
# =============================================================================
#
# A Lei 13.811/2019 aboliu todas as exceções ao casamento infantil, proibindo
# uniões formais abaixo de 16 anos sem qualquer exceção legal.
#
# SEQUÊNCIA DE ANÁLISES:
# ─────────────────────────────────────────────────────────────────────────────
# Bloco 0  Preparação: dados, constantes, funções auxiliares
#
# Bloco 1  Event Study 15 vs 16 [FEOLS/TWFE]
#          Diagnóstico rápido: o limiar de 16 anos cria violação estrutural
#          de tendências paralelas antes de 2019?
#          → Sim: χ²=131, p≈0. Motiva o DiDC (Bloco 6).
#
# Bloco 2  DR-DiD 14–15 vs 16–17 [Callaway & Sant'Anna, 2021]
#          Estimador duplamente robusto. "DR" = consistente se o modelo de
#          propensity score OU o de outcome for correto — não precisa de ambos.
#          Event study completo + ATT agregado pós-2019.
#
# Bloco 3  HonestDiD 14–15 vs 16–17 [Rambachan & Roth, 2023]
#          Quão sensíveis são os ATTs do Bloco 2 a violações de tendências
#          paralelas? → Frágil: IC inclui zero mesmo em M → 0.
#
# Bloco 4  DR-DiD 14–15 vs 17–18 [Callaway & Sant'Anna — robustez]
#          Replica Bloco 2 com controle mais distante do cutoff legal (17-18),
#          evitando contaminação de quem estava exatamente no limiar.
#
# Bloco 5  HonestDiD 14–15 vs 17–18 [Rambachan & Roth — robustez]
#
# Bloco 6  DiDC com idade contínua [rdrobust — ESTIMADOR PRINCIPAL]
#          β_DiDC = RD_pós − RD_pré no cutoff de 16 anos.
#          Não exige tendências paralelas entre grupos etários distintos.
#
# REFERÊNCIAS:
#   Callaway & Sant'Anna (2021) — J. Econometrics 225(2), 200–230
#   Rambachan & Roth (2023)     — Rev. Econ. Studies 90(5), 2555–2591
#   Sant'Anna & Zhao (2020)     — J. Econometrics 219(1), 101–122
# =============================================================================

source(here::here("00_setup.R"))

library(tidyverse)
library(fixest)
library(patchwork)

# ── Instalar/carregar pacotes adicionais ──────────────────────────────────────
for (pkg in c("did", "DRDID", "HonestDiD", "rdrobust", "remotes")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    if (pkg == "HonestDiD") {
      if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")
      remotes::install_github("asheshrambachan/HonestDiD")
    } else {
      install.packages(pkg)
    }
  }
}
library(did)       # Callaway & Sant'Anna (2021): att_gt(), aggte()
library(HonestDiD) # Rambachan & Roth (2023): createSensitivityResults*()
library(rdrobust)  # DiDC: rdrobust()

if (!exists("path_figs")) path_figs <- OUT_DIR

if (!exists("didc_pnadc") || !is.data.frame(didc_pnadc))
  stop("'didc_pnadc' não encontrado. Execute 08_didc.R antes deste script.")

# =============================================================================
# BLOCO 0 — PREPARAÇÃO
# =============================================================================
cat("\n", strrep("=", 70), "\n", sep = "")
cat("BLOCO 0 — PREPARAÇÃO\n")
cat(strrep("=", 70), "\n\n")

# ── Períodos ──────────────────────────────────────────────────────────────────
ANO_REF  <- 2018L                       # último ano antes da lei (referência)
ANOS_PRE <- 2012L:2017L                 # pré-tratamento
ANOS_POS <- c(2019L, 2022L, 2023L)     # pós-tratamento (sem COVID 2020-2021)
ANOS_EVT <- sort(c(ANOS_PRE, ANOS_POS))

# ── Grupos etários ────────────────────────────────────────────────────────────
# Tratadas (D=1): 14–15 anos — vedação ABSOLUTA pela nova lei
# Controle 1:     16–17 anos — imediatamente acima do cutoff (mais comparável)
# Controle 2:     17–18 anos — mais distante do cutoff (robustez)
IDADES_TRAT  <- c(14L, 15L)
IDADES_CTRL1 <- c(16L, 17L)
IDADES_CTRL2 <- c(17L, 18L)

# ── Covariáveis ───────────────────────────────────────────────────────────────
# Usadas no propensity score e na regressão de outcome do DR-DiD.
# Para ampliar: adicionar freq_esc_bin, rend_log (ver 08_didc.R).
COVAR_FORMULA <- ~ parda_preta + rural + uf_fct

# ── Cores padrão ─────────────────────────────────────────────────────────────
COR_TRAT <- "#993C1D"
COR_CTRL <- "#2E5FA3"

cat(sprintf("  Referência: %d | Pré: %d–%d | Pós: %s\n",
            ANO_REF, min(ANOS_PRE), max(ANOS_PRE),
            paste(ANOS_POS, collapse = ", ")))
cat(sprintf("  Tratadas: %s | Ctrl-1: %s | Ctrl-2: %s\n\n",
            paste(IDADES_TRAT,  collapse = "–"),
            paste(IDADES_CTRL1, collapse = "–"),
            paste(IDADES_CTRL2, collapse = "–")))

# =============================================================================
# FUNÇÕES AUXILIARES
# =============================================================================

# Cabeçalho de bloco
bloco <- function(num, titulo) {
  cat("\n", strrep("=", 70), "\n", sep = "")
  cat(sprintf("BLOCO %s — %s\n", num, titulo))
  cat(strrep("=", 70), "\n\n")
}

# Linha formatada de tabela
fmt_linha <- function(label, att, se, pval, w = 42) {
  if (is.na(att) || is.na(se)) {
    cat(sprintf("  %-*s  %8s  %8s  %8s\n", w, label, "—", "—", "—"))
  } else {
    sig <- ifelse(pval < 0.01, "***",
                  ifelse(pval < 0.05, "**",
                         ifelse(pval < 0.10, "*", " ")))
    cat(sprintf("  %-*s  %+7.3f%3s  %7.3f  %7.4f  [%+.3f, %+.3f]\n",
                w, label, att * 100, sig, se * 100, pval,
                (att - 1.96*se)*100, (att + 1.96*se)*100))
  }
}

# Estimar Callaway & Sant'Anna 2021 com checkpoint em disco
# ── Como funciona o att_gt(): ─────────────────────────────────────────────────
# 1. Para cada par (cohort g, período t), estima ATT(g,t) via estimador DR
# 2. panel=FALSE: trata dados como cortes transversais repetidos (RC), não painel
# 3. G=2019 para tratadas, G=0 para nunca tratadas (controle)
# 4. base_period="universal": normaliza todos os períodos relativos a 2018 (G-1)
# 5. bstrap=FALSE: SEs analíticos (mais rápidos que bootstrap)
estimar_cs <- function(dados, label, tag, force = FALSE,
                       xformla = COVAR_FORMULA) {
  ckpt <- file.path(CACHE_DIR, sprintf(".ckpt_cs_%s.rds", tag))
  if (file.exists(ckpt) && !force) {
    cat(sprintf("  att_gt [%s]: carregando do cache.\n", label))
    return(readRDS(ckpt))
  }
  cat(sprintf("  att_gt [%s]: estimando (1-2 min)...\n", label))
  # Converte para data.frame puro: att_gt/data.table têm comportamento
  # imprevisível com tibbles (avaliação de colunas em subsets internos).
  dados_df <- as.data.frame(dados)
  dados_df$Ano    <- as.integer(as.character(dados_df$Ano))
  dados_df$G      <- as.double(dados_df$G)
  # Pré-computa uf_fct para evitar avaliação de factor(UF) no contexto data.table do did
  if ("UF" %in% names(dados_df)) dados_df$uf_fct <- factor(dados_df$UF)
  res <- tryCatch(
    att_gt(
      yname         = "em_uniao",
      tname         = "Ano",
      idname        = "id_obs",
      gname         = "G",
      data          = dados_df,
      panel         = FALSE,            # RC: cada obs é única em cada período
      control_group = "nevertreated",   # G=0: nunca diretamente afetadas pela lei
      xformla       = xformla,          # raça + rural no PS e outcome regression
      weightsname   = "pes_comcalib",   # pesos amostrais PNADC
      est_method    = "dr",             # doubly robust
      base_period   = "universal",      # 2018 como base (G-1 = 2019-1)
      bstrap        = FALSE,
      cband         = FALSE
    ),
    error = function(e) { cat("  ERRO att_gt:", conditionMessage(e), "\n"); NULL }
  )
  if (!is.null(res)) saveRDS(res, ckpt)
  res
}

# Extrair betahat e sigma diagonal do resultado do aggte(type="dynamic")
# para alimentar o HonestDiD.
# A VCV diagonal (SE²) é conservadora: ignora correlação entre períodos,
# mas nunca produz matrizes singulares nem erros de Cholesky.
extrair_honestdid_inputs <- function(att_es) {
  egt   <- att_es$egt
  att_v <- att_es$att.egt
  se_v  <- att_es$se.egt
  
  # Remover período base (SE=0 por normalização) e NAs
  valid <- !is.na(se_v) & se_v > 0 & !is.na(att_v)
  egt_v <- egt[valid]
  att_v <- att_v[valid]
  se_v  <- se_v[valid]
  
  # Ordenar por tempo de evento (pré primeiro, depois pós)
  ord        <- order(egt_v)
  betahat_rr <- att_v[ord]
  Sigma_rr   <- diag(se_v[ord]^2)
  numPre     <- sum(egt_v[ord] < 0)
  numPost    <- sum(egt_v[ord] >= 0)
  
  list(betahat = betahat_rr, Sigma = Sigma_rr,
       numPre = numPre, numPost = numPost, egt = egt_v[ord])
}

# Executar HonestDiD (restrições ΔRM e ΔSD)
rodar_honestdid <- function(betahat_rr, Sigma_rr, numPre, numPost) {
  betas_pre <- betahat_rr[seq_len(numPre)]
  M_cal <- if (numPre >= 2) max(abs(diff(betas_pre))) else abs(betas_pre[1])
  cat(sprintf("  M calibrado (Δ pré máximo): %.5f (%.3f pp)\n",
              M_cal, M_cal * 100))
  
  # ΔRM: violações pós ≤ Mbar × máxima violação pré (Mbar ∈ 0..2)
  sens_rm <- tryCatch(
    createSensitivityResults_relativeMagnitudes(
      betahat = betahat_rr, sigma = Sigma_rr,
      numPrePeriods = numPre, numPostPeriods = numPost,
      Mbarvec = seq(0, 2, by = 0.25)
    ),
    error = function(e) { cat("  ERRO ΔRM:", conditionMessage(e), "\n"); NULL }
  )
  
  # ΔSD: suavidade — método C-LF (não exige sigma positivo-definido)
  Sigma_sm <- Sigma_rr; Sigma_sm[is.na(Sigma_sm)] <- 0
  sens_sm <- tryCatch(
    createSensitivityResults(
      betahat = betahat_rr, sigma = Sigma_sm,
      numPrePeriods = numPre, numPostPeriods = numPost,
      Mvec = seq(0, max(M_cal * 3, 0.005), length.out = 9),
      method = "C-LF"
    ),
    error = function(e) { cat("  ERRO ΔSD:", conditionMessage(e), "\n"); NULL }
  )
  
  # Diagnóstico de robustez
  for (info in list(list(sens_rm, "ΔRM"), list(sens_sm, "ΔSD"))) {
    sens <- info[[1]]; nome <- info[[2]]
    if (is.null(sens)) next
    col_lb <- intersect(c("lb","CI_lower","lower"), names(sens))[1]
    col_ub <- intersect(c("ub","CI_upper","upper"), names(sens))[1]
    col_m  <- intersect(c("Mbar","M","m"),          names(sens))[1]
    if (is.na(col_lb)) next
    rob  <- sens[!is.na(sens[[col_lb]]) &
                   (sens[[col_lb]] > 0 | sens[[col_ub]] < 0), ]
    Mrob <- if (nrow(rob) > 0 && !is.na(col_m)) max(rob[[col_m]]) else 0
    cat(sprintf("  [%s] M_max robusto = %.2f | M_cal = %.4f → %s\n",
                nome, Mrob, M_cal,
                if (Mrob >= M_cal) "ROBUSTO ✓" else "FRÁGIL ✗"))
  }
  
  list(rm = sens_rm, sm = sens_sm, M_cal = M_cal)
}

# Gráfico HonestDiD (ΔRM ou ΔSD)
plot_honestdid <- function(sens, titulo, M_cal, subtitulo = NULL,
                           cor = COR_CTRL, cor_zero = COR_TRAT) {
  if (is.null(sens)) return(NULL)
  col_lb <- intersect(c("lb","CI_lower","lower"), names(sens))[1]
  col_ub <- intersect(c("ub","CI_upper","upper"), names(sens))[1]
  col_m  <- intersect(c("Mbar","M","m"),          names(sens))[1]
  if (is.na(col_lb) || is.na(col_m)) return(NULL)
  sens |>
    rename(lb=all_of(col_lb), ub=all_of(col_ub), Mval=all_of(col_m)) |>
    ggplot(aes(x = Mval)) +
    geom_ribbon(aes(ymin = lb*100, ymax = ub*100), fill = cor, alpha = 0.25) +
    geom_line(aes(y = lb*100), color = cor, linewidth = 0.8) +
    geom_line(aes(y = ub*100), color = cor, linewidth = 0.8) +
    geom_hline(yintercept = 0, linetype = "dashed",
               color = cor_zero, linewidth = 0.8) +
    geom_vline(xintercept = M_cal, linetype = "dotted", color = "gray40") +
    annotate("text", x = M_cal * 1.05,
             y = max(sens[[col_ub]] * 100, na.rm = TRUE) * 0.85,
             label = sprintf("M calibrado\n(%.3f pp)", M_cal * 100),
             hjust = 0, size = 3, color = "gray40") +
    scale_y_continuous(labels = scales::label_number(suffix = " pp")) +
    labs(title = titulo, subtitle = subtitulo, x = "M", y = "IC robusto (pp)",
         caption = "Tracejado = 0. Pontilhado = M calibrado pelos dados pré-2018.") +
    theme_minimal(base_size = 11)
}

# =============================================================================
# BLOCO 1 — EVENT STUDY 15 vs 16 ANOS (diagnóstico de tendências paralelas)
# =============================================================================
# Pergunta: o design mais restrito (apenas vizinhos imediatos do cutoff legal)
# sustenta tendências paralelas entre 2012 e 2018?
#
# Método: FEOLS (LPM com efeitos fixos de UF e ano, cluster UF).
# Teste Wald conjunto sobre os coeficientes pré-2018 (β_2012 = ... = β_2017 = 0).
#
# Por que 15 vs 16?
# Antes de 2019, o limiar legal era exatamente 16 anos. Meninas de 16 podiam
# se casar com consentimento parental; meninas de 15 não (em tese). Por isso,
# espera-se uma descontinuidade na prevalência de uniões em torno de 16 anos
# ANTES de 2019 — e essa descontinuidade é estrutural, não ruído amostral.
bloco("1", "EVENT STUDY 15 vs 16 ANOS (diagnóstico)")

dados_1516 <- didc_pnadc |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  filter(
    idade %in% c(15L, 16L),
    Ano   %in% c(ANO_REF, ANOS_EVT)
  ) |>
  mutate(
    D_15    = as.integer(idade == 15L),   # 1 = tratada (15 anos); 0 = controle (16)
    ano_fct = factor(Ano),
    uf_fct  = factor(UF)
  )

cat(sprintf("  N = %d | 15 anos (tratada): %d | 16 anos (controle): %d\n\n",
            nrow(dados_1516),
            sum(dados_1516$D_15 == 1L),
            sum(dados_1516$D_15 == 0L)))

# ── Tendências visuais ────────────────────────────────────────────────────────
cor_15 <- COR_TRAT; cor_16 <- COR_CTRL

tend_1516 <- dados_1516 |>
  group_by(Ano, D_15) |>
  summarise(prev = weighted.mean(em_uniao, pes_comcalib, na.rm = TRUE),
            .groups = "drop") |>
  mutate(grupo = if_else(D_15==1L, "15 anos (tratada)", "16 anos (controle)"))

fig_1516_niveis <- tend_1516 |>
  ggplot(aes(x=Ano, y=prev, color=grupo, group=grupo)) +
  geom_vline(xintercept=2018.5, linetype="dashed", color="gray40", linewidth=0.7) +
  annotate("text", x=2018.7, y=max(tend_1516$prev, na.rm=TRUE)*0.98,
           label="Lei 13.811/2019", hjust=0, size=3, color="gray40") +
  geom_line(linewidth=0.9) + geom_point(size=2.5) +
  scale_color_manual(values=c("15 anos (tratada)"=cor_15, "16 anos (controle)"=cor_16),
                     name=NULL) +
  scale_y_continuous(labels=scales::percent_format(accuracy=0.1)) +
  scale_x_continuous(breaks=sort(unique(dados_1516$Ano))) +
  labs(title="Prevalência de uniões — 15 vs 16 anos",
       x=NULL, y="Prevalência (%)",
       caption="PNADC. Médias ponderadas por pes_comcalib.") +
  theme_minimal(base_size=11) + theme(legend.position="bottom")

dif_1516 <- tend_1516 |>
  select(Ano, D_15, prev) |>
  pivot_wider(names_from=D_15, values_from=prev, names_prefix="D") |>
  mutate(dif=D1-D0, periodo=if_else(Ano<2019L,"pré-2019","pós-2019"))

lm_pre_1516 <- lm(dif ~ Ano, data=filter(dif_1516, Ano<2019L))
slope_1516  <- coef(lm_pre_1516)["Ano"] * 100
cat(sprintf("  Inclinação pré-2019 (dif 15−16): %+.4f pp/ano\n\n", slope_1516))

fig_1516_dif <- dif_1516 |>
  ggplot(aes(x=Ano, y=dif)) +
  geom_hline(yintercept=0, linetype="dotted", color="gray60") +
  geom_vline(xintercept=2018.5, linetype="dashed", color="gray40", linewidth=0.7) +
  geom_smooth(data=filter(dif_1516, Ano<2019L),
              method="lm", se=TRUE, color=cor_16, fill=cor_16, alpha=0.15, linewidth=0.8) +
  geom_line(aes(color=periodo), linewidth=1) +
  geom_point(aes(color=periodo), size=2.5) +
  scale_color_manual(values=c("pré-2019"=cor_16, "pós-2019"=cor_15), name="Período") +
  scale_y_continuous(labels=scales::percent_format(accuracy=0.1)) +
  scale_x_continuous(breaks=sort(unique(dif_1516$Ano))) +
  labs(title="Diferença (15) − (16) ao longo do tempo",
       x=NULL, y="Diferença (pp)",
       caption=sprintf("Azul = tendência linear pré-2019. Inclinação: %+.3f pp/ano.", slope_1516)) +
  theme_minimal(base_size=11) + theme(legend.position="bottom")

fig_1516_tend <- (fig_1516_niveis | fig_1516_dif) +
  plot_annotation(title="Diagnóstico de tendências paralelas — 15 vs 16 anos",
                  theme=theme(plot.title=element_text(size=13, face="bold")))
ggsave(file.path(path_figs, "fig_1516_tend_painel.png"),
       fig_1516_tend, width=36, height=13, units="cm", dpi=300, bg="white")
cat("  fig_1516_tend_painel.png salvo.\n\n")

# ── FEOLS event study ─────────────────────────────────────────────────────────
# i(Ano, D_15, ref=ANO_REF): interação ano × indicador de tratada
# Coeficiente em cada ano = diferença no gap tratada−controle relativo a 2018
mod_1516 <- feols(
  em_uniao ~ i(Ano, D_15, ref = ANO_REF) + parda_preta + rural |
    ano_fct + uf_fct,
  data    = dados_1516,
  weights = ~pes_comcalib,
  cluster = ~uf_fct
)

nm_all  <- names(coef(mod_1516))
idx_evt <- str_detect(nm_all, ":D_15$")

coef_1516 <- tibble(
  term     = nm_all[idx_evt],
  estimate = coef(mod_1516)[idx_evt],
  se       = se(mod_1516)[idx_evt]
) |>
  mutate(
    ano   = as.integer(str_extract(term, "\\d{4}")),
    ci_lo = estimate - qnorm(0.975)*se,
    ci_hi = estimate + qnorm(0.975)*se,
    pre   = ano < 2019L
  ) |>
  bind_rows(tibble(term="ref", ano=ANO_REF, estimate=0, se=0,
                   ci_lo=0, ci_hi=0, pre=TRUE)) |>
  arrange(ano)

# Teste Wald conjunto nos coeficientes pré-2018
evt_pre_1516 <- coef_1516 |> filter(pre, ano != ANO_REF, !is.na(se), se > 0)
chi2_1516 <- sum((evt_pre_1516$estimate / evt_pre_1516$se)^2)
pval_1516 <- pchisq(chi2_1516, df=nrow(evt_pre_1516), lower.tail=FALSE)

cat(sprintf("  Wald pré-tendências (15 vs 16): χ²(%d) = %.2f, p = %.4f\n\n",
            nrow(evt_pre_1516), chi2_1516, pval_1516))

if (pval_1516 < 0.05) {
  cat("  ══════════════════════════════════════════════════════════════\n")
  cat("  REJEIÇÃO: tendências paralelas não sustentadas para 15 vs 16.\n")
  cat("  Razão estrutural: o limiar de 16 anos já era o limiar legal\n")
  cat("  de casamento antes de 2019. Não é violação corrigível por\n")
  cat("  covariáveis — é a própria norma que a lei alterou.\n")
  cat("  → Motivação empírica para o DiDC com idade contínua (Bloco 6).\n")
  cat("  ══════════════════════════════════════════════════════════════\n\n")
}

fig_1516_evt <- coef_1516 |>
  mutate(periodo=if_else(pre | ano==ANO_REF, "pré/ref", "pós")) |>
  ggplot(aes(x=ano, y=estimate*100, color=periodo, fill=periodo)) +
  geom_hline(yintercept=0, linetype="dashed", color="gray50") +
  geom_vline(xintercept=2018.5, linetype="dashed", color="gray30", linewidth=0.7) +
  annotate("text", x=2018.7, y=max(coef_1516$ci_hi*100, na.rm=TRUE)*0.92,
           label="Lei 13.811/2019", hjust=0, size=3, color="gray30") +
  geom_ribbon(aes(ymin=ci_lo*100, ymax=ci_hi*100), alpha=0.2, color=NA) +
  geom_line(linewidth=0.9) + geom_point(size=3) +
  geom_point(data=filter(coef_1516, ano==ANO_REF),
             aes(x=ano, y=0), color="gray40", size=3, shape=21, fill="white") +
  scale_color_manual(values=c("pré/ref"=cor_16, "pós"=cor_15), name=NULL) +
  scale_fill_manual(values=c("pré/ref"=cor_16, "pós"=cor_15), guide="none") +
  scale_x_continuous(breaks=sort(unique(coef_1516$ano))) +
  scale_y_continuous(labels=scales::label_number(suffix=" pp")) +
  labs(
    title    = "Event Study FEOLS — Design 15 vs 16 anos",
    subtitle = "LPM com EF Ano + UF, cluster UF | Tratada: 15 anos | Controle: 16 anos",
    x=NULL, y="Coeficiente (pp)",
    caption = sprintf(
      "Wald pré-tendências: χ²(%d) = %.2f, p = %.4f.\nControles: raça, rural. Banda = IC 95%%.",
      nrow(evt_pre_1516), chi2_1516, pval_1516)
  ) +
  theme_minimal(base_size=11) + theme(legend.position="bottom")

ggsave(file.path(path_figs, "fig_1516_event_study.png"),
       fig_1516_evt, width=22, height=13, units="cm", dpi=300, bg="white")
cat("  fig_1516_event_study.png salvo.\n\n")

# =============================================================================
# BLOCO 1b — DR-DiD 15 vs 16 [Callaway & Sant'Anna 2021]
# =============================================================================
# Mesmo que o event study (Bloco 1) já aponte rejeição forte de tendências
# paralelas, estimamos o DR-DiD aqui por completude — e para mostrar
# explicitamente que o duplamente robusto também não resolve a violação
# estrutural. O HonestDiD (Bloco 1c) confirma que o IC inclui zero para
# qualquer M razoável, fornecendo a motivação formal para o DiDC (Bloco 6).
#
# Tratada: 15 anos | Controle: 16 anos | G=2019 | Panel=FALSE (RC)
bloco("1b", "DR-DiD 15 vs 16 [Callaway & Sant'Anna 2021]")

# Reutiliza dados_1516 construído no Bloco 1 — apenas adiciona colunas CS
dados_cs_1516 <- dados_1516 |>
  mutate(
    G      = if_else(D_15 == 1L, 2019, 0),    # double: did converte G=0 → Inf internamente
    id_obs = row_number()
  )

cs_1516 <- estimar_cs(dados_cs_1516, "15 vs 16", "1516")

if (!is.null(cs_1516)) {
  att_es_1516 <- aggte(cs_1516, type = "dynamic", na.rm = TRUE)
  att_ov_1516 <- aggte(cs_1516, type = "simple",  na.rm = TRUE)
  
  ATT_CS_1516  <- att_ov_1516$overall.att
  SE_CS_1516   <- att_ov_1516$overall.se
  PVAL_CS_1516 <- 2 * pnorm(-abs(ATT_CS_1516 / SE_CS_1516))
  
  cat("  Event study (tempo de evento relativo a 2019):\n")
  tibble(
    e       = att_es_1516$egt,
    ano     = att_es_1516$egt + 2019L,
    att_pp  = att_es_1516$att.egt * 100,
    se_pp   = att_es_1516$se.egt  * 100,
    periodo = if_else(att_es_1516$egt < 0, "PRÉ", "PÓS")
  ) |> mutate(across(c(att_pp, se_pp), ~round(., 3))) |> print()
  
  cat(sprintf("\n  ATT geral pós-2019: %+.4f pp (SE=%.4f, p=%.4f)\n",
              ATT_CS_1516*100, SE_CS_1516*100, PVAL_CS_1516))
  cat(sprintf("  IC 95%%: [%+.3f, %+.3f] pp\n\n",
              (ATT_CS_1516 - 1.96*SE_CS_1516)*100,
              (ATT_CS_1516 + 1.96*SE_CS_1516)*100))
  
  # Gráfico event study DR-DiD 15 vs 16
  es_df_1516 <- tibble(
    e     = att_es_1516$egt,
    att   = att_es_1516$att.egt,
    se    = att_es_1516$se.egt,
    ci_lo = att_es_1516$att.egt - qnorm(0.975)*att_es_1516$se.egt,
    ci_hi = att_es_1516$att.egt + qnorm(0.975)*att_es_1516$se.egt,
    pre   = att_es_1516$egt < 0
  )
  
  fig_es_drdid_1516 <- es_df_1516 |>
    filter(!is.na(att)) |>
    mutate(periodo = if_else(pre, "pré", "pós")) |>
    ggplot(aes(x=e, y=att*100, color=periodo, fill=periodo)) +
    geom_hline(yintercept=0, linetype="dashed", color="gray50") +
    geom_vline(xintercept=-0.5, linetype="dashed", color="gray30", linewidth=0.7) +
    annotate("text", x=-0.4, y=max(es_df_1516$ci_hi*100, na.rm=TRUE)*0.92,
             label="Lei 2019", hjust=0, size=3, color="gray30") +
    geom_ribbon(aes(ymin=ci_lo*100, ymax=ci_hi*100), alpha=0.2, color=NA) +
    geom_line(linewidth=0.9) + geom_point(size=3) +
    scale_color_manual(values=c("pré"=cor_16, "pós"=cor_15), name=NULL) +
    scale_fill_manual(values=c("pré"=cor_16, "pós"=cor_15), guide="none") +
    scale_x_continuous(breaks=sort(unique(es_df_1516$e)),
                       labels=~paste0("e=", .)) +
    scale_y_continuous(labels=scales::label_number(suffix=" pp")) +
    labs(
      title    = "DR-DiD Event Study — 15 vs 16 anos",
      subtitle = "Callaway & Sant'Anna (2021) | Tratada: 15 anos | Controle: 16 anos | Ref: e=−1 (2018)",
      x        = "Tempo de evento (e = t − 2019)", y = "ATT (pp)",
      caption  = "Estimador duplamente robusto. Banda = IC 95%. Covariáveis: raça, rural."
    ) +
    theme_minimal(base_size=11) + theme(legend.position="bottom")
  
  ggsave(file.path(path_figs, "fig_drDiD_1516_event_study.png"),
         fig_es_drdid_1516, width=22, height=13, units="cm", dpi=300, bg="white")
  cat("  fig_drDiD_1516_event_study.png salvo.\n\n")
} else {
  ATT_CS_1516 <- SE_CS_1516 <- PVAL_CS_1516 <- NA_real_
  cat("  att_gt falhou — resultados do Bloco 1b indisponíveis.\n\n")
}

# =============================================================================
# BLOCO 1c — HonestDiD 15 vs 16 [Rambachan & Roth 2023]
# =============================================================================
# Esperado: IC inclui zero para qualquer M razoável, confirmando que a
# violação de tendências paralelas no design 15 vs 16 é estrutural e não
# pode ser "absorvida" pelo estimador DR-DiD — independentemente de quão
# generosa for a tolerância a desvios da hipótese de tendências paralelas.
# Isso reforça formalmente a necessidade do DiDC (Bloco 6).
bloco("1c", "HonestDiD 15 vs 16 [Rambachan & Roth 2023]")

if (!is.null(cs_1516) && exists("att_es_1516")) {
  hd_inp_1516 <- extrair_honestdid_inputs(att_es_1516)
  
  cat(sprintf("  Períodos usados: %d pré + %d pós\n\n",
              hd_inp_1516$numPre, hd_inp_1516$numPost))
  
  if (hd_inp_1516$numPre >= 1 && hd_inp_1516$numPost >= 1) {
    hd_1516 <- rodar_honestdid(
      hd_inp_1516$betahat, hd_inp_1516$Sigma,
      hd_inp_1516$numPre,  hd_inp_1516$numPost
    )
    
    fig_hd_rm_1516 <- plot_honestdid(
      hd_1516$rm,
      "HonestDiD ΔRM — 15 vs 16",
      hd_1516$M_cal,
      subtitulo = "IC válido para violações de até Mbar × máxima violação pré-2018 | Tratada: 15 | Controle: 16"
    )
    fig_hd_sm_1516 <- plot_honestdid(
      hd_1516$sm,
      "HonestDiD ΔSD — 15 vs 16",
      hd_1516$M_cal,
      subtitulo = "IC válido permitindo desvio de até M pp por período | Tratada: 15 | Controle: 16"
    )
    
    if (!is.null(fig_hd_rm_1516)) {
      ggsave(file.path(path_figs, "fig_drDiD_1516_roth_magnitude.png"),
             fig_hd_rm_1516, width=22, height=13, units="cm", dpi=300, bg="white")
      cat("\n  fig_drDiD_1516_roth_magnitude.png salvo.\n")
    }
    if (!is.null(fig_hd_sm_1516)) {
      ggsave(file.path(path_figs, "fig_drDiD_1516_roth_smooth.png"),
             fig_hd_sm_1516, width=22, height=13, units="cm", dpi=300, bg="white")
      cat("  fig_drDiD_1516_roth_smooth.png salvo.\n")
    }
    cat("\n")
  } else {
    hd_1516 <- NULL
    cat("  Períodos insuficientes — HonestDiD pulado.\n\n")
  }
} else {
  hd_1516 <- NULL
  cat("  Bloco 1b sem resultado — HonestDiD pulado.\n\n")
}

# =============================================================================
# BLOCO 2 — DR-DiD 14–15 vs 16–17: Callaway & Sant'Anna (2021)
# =============================================================================
# O att_gt() estima ATT(g, t) para cada cohort g e período t:
#   ATT(2019, t) = efeito médio do tratamento em t para as tratadas em 2019
#
# Como só temos um cohort (G=2019), o "event study" é simplesmente
# ATT(2019, t) para t ∈ {2012, ..., 2023}, normalizado em relação a 2018.
#
# O aggte(type="dynamic") agrega por tempo de evento e = t − g:
#   e < 0 → pré-tratamento (deveria ser ≈ 0 se tendências paralelas valem)
#   e ≥ 0 → pós-tratamento (efeito da lei)
bloco("2", "DR-DiD 14–15 vs 16–17 [Callaway & Sant'Anna 2021]")

cat("  Tratadas: 14–15 anos | Controle: 16–17 anos\n")
cat("  Lei vedou absolutamente casamentos < 16 anos (grupo tratado)\n")
cat("  Controle (16–17) permaneceu com regras inalteradas\n\n")

# Preparar dados: incluir 2018 (base_period universal usa G-1 = 2019-1 = 2018)
dados_cs_1617 <- didc_pnadc |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  filter(
    idade %in% c(IDADES_TRAT, IDADES_CTRL1),
    Ano   %in% c(ANO_REF, ANOS_EVT)
  ) |>
  mutate(
    D      = as.integer(idade %in% IDADES_TRAT),
    G      = if_else(D == 1L, 2019, 0),     # double: did converte G=0 → Inf internamente
    id_obs = row_number(),                   # ID único por observação (RC)
    uf_fct = factor(UF),
    ano_fct= factor(Ano)
  )

cat(sprintf("  N = %d | Tratadas (14-15): %d | Controles (16-17): %d\n\n",
            nrow(dados_cs_1617), sum(dados_cs_1617$D==1), sum(dados_cs_1617$D==0)))

# ── Tendências paralelas visuais ──────────────────────────────────────────────
tend_1617 <- dados_cs_1617 |>
  group_by(Ano, D) |>
  summarise(prev=weighted.mean(em_uniao, pes_comcalib, na.rm=TRUE), .groups="drop") |>
  mutate(grupo=if_else(D==1,"Tratadas (14–15)","Controle (16–17)"),
         periodo=if_else(Ano<2019,"pré-2019","pós-2019"))

tend_id_1617 <- dados_cs_1617 |>
  group_by(Ano, idade, D) |>
  summarise(prev=weighted.mean(em_uniao, pes_comcalib, na.rm=TRUE), .groups="drop")

cores_id <- c("14"="#993C1D","15"="#F4A460","16"="#2E5FA3","17"="#87CEEB")

fig_A_1617 <- tend_id_1617 |>
  ggplot(aes(x=Ano, y=prev, color=factor(idade), group=factor(idade),
             linetype=factor(D))) +
  geom_vline(xintercept=2018.5, linetype="dashed", color="gray40", linewidth=0.7) +
  geom_line(linewidth=0.9) + geom_point(size=2) +
  scale_color_manual(values=cores_id, name="Idade") +
  scale_linetype_manual(values=c("0"="solid","1"="dashed"),
                        labels=c("0"="Controle","1"="Tratada"), name="Grupo") +
  scale_y_continuous(labels=scales::percent_format(accuracy=0.1)) +
  scale_x_continuous(breaks=sort(unique(tend_id_1617$Ano))) +
  labs(title="Prevalência por idade — 14-15 vs 16-17", x=NULL, y="Prevalência (%)") +
  theme_minimal(base_size=10) + theme(legend.position="bottom")

dif_1617 <- tend_1617 |>
  select(Ano, D, prev) |>
  pivot_wider(names_from=D, values_from=prev, names_prefix="D") |>
  mutate(dif=D1-D0, periodo=if_else(Ano<2019,"pré-2019","pós-2019"))

lm_pre_1617 <- lm(dif ~ Ano, data=filter(dif_1617, Ano<2019))
slope_1617  <- coef(lm_pre_1617)["Ano"] * 100

fig_B_1617 <- dif_1617 |>
  ggplot(aes(x=Ano, y=dif)) +
  geom_hline(yintercept=0, linetype="dotted", color="gray60") +
  geom_vline(xintercept=2018.5, linetype="dashed", color="gray40", linewidth=0.7) +
  geom_smooth(data=filter(dif_1617, Ano<2019), method="lm", se=TRUE,
              color=COR_CTRL, fill=COR_CTRL, alpha=0.15, linewidth=0.8) +
  geom_line(aes(color=periodo), linewidth=1) +
  geom_point(aes(color=periodo), size=2.5) +
  scale_color_manual(values=c("pré-2019"=COR_CTRL,"pós-2019"=COR_TRAT), name="Período") +
  scale_y_continuous(labels=scales::percent_format(accuracy=0.1)) +
  scale_x_continuous(breaks=sort(unique(dif_1617$Ano))) +
  labs(title="Diferença (14-15) − (16-17)",
       x=NULL, y="Diferença (pp)",
       caption=sprintf("Inclinação pré: %+.3f pp/ano.", slope_1617)) +
  theme_minimal(base_size=10) + theme(legend.position="bottom")

fig_tend_1617 <- (fig_A_1617 | fig_B_1617) +
  plot_annotation(title="Tendências paralelas — 14–15 vs 16–17",
                  theme=theme(plot.title=element_text(size=12, face="bold")))
ggsave(file.path(path_figs, "fig_drDiD_tend_painel.png"),
       fig_tend_1617, width=36, height=13, units="cm", dpi=300, bg="white")
cat("  fig_drDiD_tend_painel.png salvo.\n\n")

# ── Estimação Callaway & Sant'Anna ────────────────────────────────────────────
cs_1617 <- estimar_cs(dados_cs_1617, "14-15 vs 16-17", "1617")

if (!is.null(cs_1617)) {
  # Event study por tempo de evento (e = t − 2019)
  att_es_1617 <- aggte(cs_1617, type="dynamic", na.rm=TRUE)
  # ATT geral pós-2019 (média simples sobre todos os e ≥ 0)
  att_ov_1617 <- aggte(cs_1617, type="simple",  na.rm=TRUE)
  
  ATT_CS_1617  <- att_ov_1617$overall.att
  SE_CS_1617   <- att_ov_1617$overall.se
  PVAL_CS_1617 <- 2 * pnorm(-abs(ATT_CS_1617 / SE_CS_1617))
  
  cat("  Event study (tempo de evento relativo a 2019):\n")
  tibble(
    e       = att_es_1617$egt,
    ano     = att_es_1617$egt + 2019L,
    att_pp  = att_es_1617$att.egt * 100,
    se_pp   = att_es_1617$se.egt  * 100,
    periodo = if_else(att_es_1617$egt < 0, "PRÉ", "PÓS")
  ) |> mutate(across(c(att_pp, se_pp), ~round(., 3))) |> print()
  
  cat(sprintf("\n  ATT geral pós-2019: %+.4f pp (SE=%.4f, p=%.4f)\n",
              ATT_CS_1617*100, SE_CS_1617*100, PVAL_CS_1617))
  cat(sprintf("  IC 95%%: [%+.3f, %+.3f] pp\n\n",
              (ATT_CS_1617-1.96*SE_CS_1617)*100,
              (ATT_CS_1617+1.96*SE_CS_1617)*100))
  
  # Gráfico event study
  es_df_1617 <- tibble(
    e      = att_es_1617$egt,
    att    = att_es_1617$att.egt,
    se     = att_es_1617$se.egt,
    ci_lo  = att_es_1617$att.egt - qnorm(0.975)*att_es_1617$se.egt,
    ci_hi  = att_es_1617$att.egt + qnorm(0.975)*att_es_1617$se.egt,
    pre    = att_es_1617$egt < 0
  )
  
  fig_es_1617 <- es_df_1617 |>
    filter(!is.na(att)) |>
    mutate(periodo=if_else(pre, "pré", "pós")) |>
    ggplot(aes(x=e, y=att*100, color=periodo, fill=periodo)) +
    geom_hline(yintercept=0, linetype="dashed", color="gray50") +
    geom_vline(xintercept=-0.5, linetype="dashed", color="gray30", linewidth=0.7) +
    annotate("text", x=-0.4, y=max(es_df_1617$ci_hi*100, na.rm=TRUE)*0.92,
             label="Lei 2019", hjust=0, size=3, color="gray30") +
    geom_ribbon(aes(ymin=ci_lo*100, ymax=ci_hi*100), alpha=0.2, color=NA) +
    geom_line(linewidth=0.9) + geom_point(size=3) +
    scale_color_manual(values=c("pré"=COR_CTRL,"pós"=COR_TRAT), name=NULL) +
    scale_fill_manual(values=c("pré"=COR_CTRL,"pós"=COR_TRAT), guide="none") +
    scale_x_continuous(breaks=sort(unique(es_df_1617$e)),
                       labels=~paste0("e=", .)) +
    scale_y_continuous(labels=scales::label_number(suffix=" pp")) +
    labs(
      title    = "DR-DiD Event Study — 14–15 vs 16–17",
      subtitle = "Callaway & Sant'Anna (2021) | Tempo de evento relativo a 2019 | Ref: e = −1 (2018)",
      x        = "Tempo de evento (e = t − 2019)", y = "ATT (pp)",
      caption  = "Estimador duplamente robusto. Banda = IC 95%. Covariáveis: raça, rural."
    ) +
    theme_minimal(base_size=11) + theme(legend.position="bottom")
  
  ggsave(file.path(path_figs, "fig_drDiD_event_study.png"),
         fig_es_1617, width=22, height=13, units="cm", dpi=300, bg="white")
  cat("  fig_drDiD_event_study.png salvo.\n\n")
} else {
  ATT_CS_1617 <- SE_CS_1617 <- PVAL_CS_1617 <- NA_real_
  cat("  att_gt falhou — resultados do Bloco 2 indisponíveis.\n\n")
}

# =============================================================================
# BLOCO 3 — HonestDiD 14–15 vs 16–17 [Rambachan & Roth, 2023]
# =============================================================================
# Teste: o resultado do Bloco 2 é robusto a violações de tendências paralelas?
#
# Dois tipos de restrição:
#   ΔRM (Magnitude Relativa): as violações no pós podem ser no máximo Mbar
#        vezes maiores que a maior violação observada no pré.
#        M=0 exige paralelas exatas; M=1 permite violações tão grandes
#        quanto as maiores violações pré-2019.
#   ΔSD (Suavidade): a tendência pré pode continuar no pós, mas com desvio
#        de no máximo M pp por período adicional.
bloco("3", "HonestDiD 14–15 vs 16–17 [Rambachan & Roth 2023]")

if (!is.null(cs_1617) && exists("att_es_1617")) {
  hd_inp_1617 <- extrair_honestdid_inputs(att_es_1617)
  
  cat(sprintf("  Períodos usados: %d pré + %d pós\n\n",
              hd_inp_1617$numPre, hd_inp_1617$numPost))
  
  if (hd_inp_1617$numPre >= 1 && hd_inp_1617$numPost >= 1) {
    hd_1617 <- rodar_honestdid(
      hd_inp_1617$betahat, hd_inp_1617$Sigma,
      hd_inp_1617$numPre,  hd_inp_1617$numPost
    )
    
    fig_hd_rm_1617 <- plot_honestdid(
      hd_1617$rm,
      "HonestDiD ΔRM — 14–15 vs 16–17",
      hd_1617$M_cal,
      subtitulo = "IC válido para violações de até Mbar × máxima violação pré-2018"
    )
    fig_hd_sm_1617 <- plot_honestdid(
      hd_1617$sm,
      "HonestDiD ΔSD — 14–15 vs 16–17",
      hd_1617$M_cal,
      subtitulo = "IC válido permitindo desvio de até M pp por período na tendência pré"
    )
    
    if (!is.null(fig_hd_rm_1617)) {
      ggsave(file.path(path_figs, "fig_drDiD_roth_magnitude_novo.png"),
             fig_hd_rm_1617, width=22, height=13, units="cm", dpi=300, bg="white")
      cat("\n  fig_drDiD_roth_magnitude_novo.png salvo.\n")
    }
    if (!is.null(fig_hd_sm_1617)) {
      ggsave(file.path(path_figs, "fig_drDiD_roth_smooth_novo.png"),
             fig_hd_sm_1617, width=22, height=13, units="cm", dpi=300, bg="white")
      cat("  fig_drDiD_roth_smooth_novo.png salvo.\n")
    }
  } else {
    hd_1617 <- NULL
    cat("  Períodos insuficientes — HonestDiD pulado.\n")
  }
  cat("\n")
} else {
  hd_1617 <- NULL
  cat("  Bloco 2 sem resultado — HonestDiD pulado.\n\n")
}

# =============================================================================
# BLOCO 4 — DR-DiD 14–15 vs 17–18 [Callaway & Sant'Anna — robustez]
# =============================================================================
# Por que um grupo controle alternativo?
# O grupo 16–17 está imediatamente acima do cutoff legal de 16 anos. Isso
# pode criar "contaminação" do controle: meninas de 16 que estavam prestes a
# se casar aos 15 (antes da lei) podem ter adiado o casamento para 16 — o que
# introduziria viés no controle. O grupo 17–18 está mais distante do cutoff,
# sendo menos suscetível a esse tipo de efeito.
#
# Custo: 17–18 é menos comparável a 14–15 (maior distância etária).
bloco("4", "DR-DiD 14–15 vs 17–18 [Callaway & Sant'Anna — robustez]")

cat("  Tratadas: 14–15 anos | Controle: 17–18 anos\n")
cat("  Razão: evitar contaminação do controle pela descontinuidade no cutoff de 16\n\n")

dados_cs_1718 <- didc_pnadc |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  filter(
    idade %in% c(IDADES_TRAT, IDADES_CTRL2),
    Ano   %in% c(ANO_REF, ANOS_EVT)
  ) |>
  mutate(
    D      = as.integer(idade %in% IDADES_TRAT),
    G      = if_else(D == 1L, 2019, 0),     # double: did converte G=0 → Inf internamente
    id_obs = row_number(),
    uf_fct = factor(UF),
    ano_fct= factor(Ano)
  )

cat(sprintf("  N = %d | Tratadas (14-15): %d | Controles (17-18): %d\n\n",
            nrow(dados_cs_1718), sum(dados_cs_1718$D==1), sum(dados_cs_1718$D==0)))

# Tendências visuais 17-18
tend_1718 <- dados_cs_1718 |>
  group_by(Ano, D) |>
  summarise(prev=weighted.mean(em_uniao, pes_comcalib, na.rm=TRUE), .groups="drop") |>
  mutate(grupo=if_else(D==1,"Tratadas (14–15)","Controle (17–18)"),
         periodo=if_else(Ano<2019,"pré-2019","pós-2019"))

dif_1718 <- tend_1718 |>
  select(Ano, D, prev) |>
  pivot_wider(names_from=D, values_from=prev, names_prefix="D") |>
  mutate(dif=D1-D0, periodo=if_else(Ano<2019,"pré-2019","pós-2019"))

slope_1718 <- coef(lm(dif~Ano, data=filter(dif_1718, Ano<2019)))["Ano"]*100

fig_tend_dif_1718 <- dif_1718 |>
  ggplot(aes(x=Ano, y=dif)) +
  geom_hline(yintercept=0, linetype="dotted", color="gray60") +
  geom_vline(xintercept=2018.5, linetype="dashed", color="gray40", linewidth=0.7) +
  geom_smooth(data=filter(dif_1718, Ano<2019), method="lm", se=TRUE,
              color=COR_CTRL, fill=COR_CTRL, alpha=0.15, linewidth=0.8) +
  geom_line(aes(color=periodo), linewidth=1) + geom_point(aes(color=periodo), size=2.5) +
  scale_color_manual(values=c("pré-2019"=COR_CTRL,"pós-2019"=COR_TRAT), name="Período") +
  scale_y_continuous(labels=scales::percent_format(accuracy=0.1)) +
  scale_x_continuous(breaks=sort(unique(dif_1718$Ano))) +
  labs(title="Diferença (14-15) − (17-18) ao longo do tempo",
       x=NULL, y="Diferença (pp)",
       caption=sprintf("Inclinação pré: %+.3f pp/ano.", slope_1718)) +
  theme_minimal(base_size=11) + theme(legend.position="bottom")

ggsave(file.path(path_figs, "fig_drDiD_tend_painel_1718.png"),
       fig_tend_dif_1718, width=22, height=13, units="cm", dpi=300, bg="white")
cat("  fig_drDiD_tend_painel_1718.png salvo.\n\n")

# Estimação CS 17-18
cs_1718 <- estimar_cs(dados_cs_1718, "14-15 vs 17-18", "1718")

if (!is.null(cs_1718)) {
  att_es_1718 <- aggte(cs_1718, type="dynamic", na.rm=TRUE)
  att_ov_1718 <- aggte(cs_1718, type="simple",  na.rm=TRUE)
  
  ATT_CS_1718  <- att_ov_1718$overall.att
  SE_CS_1718   <- att_ov_1718$overall.se
  PVAL_CS_1718 <- 2 * pnorm(-abs(ATT_CS_1718 / SE_CS_1718))
  
  cat(sprintf("  ATT geral pós-2019: %+.4f pp (SE=%.4f, p=%.4f)\n",
              ATT_CS_1718*100, SE_CS_1718*100, PVAL_CS_1718))
  cat(sprintf("  IC 95%%: [%+.3f, %+.3f] pp\n\n",
              (ATT_CS_1718-1.96*SE_CS_1718)*100,
              (ATT_CS_1718+1.96*SE_CS_1718)*100))
  
  es_df_1718 <- tibble(
    e     = att_es_1718$egt,
    att   = att_es_1718$att.egt,
    se    = att_es_1718$se.egt,
    ci_lo = att_es_1718$att.egt - qnorm(0.975)*att_es_1718$se.egt,
    ci_hi = att_es_1718$att.egt + qnorm(0.975)*att_es_1718$se.egt,
    pre   = att_es_1718$egt < 0
  )
  
  fig_es_1718 <- es_df_1718 |>
    filter(!is.na(att)) |>
    mutate(periodo=if_else(pre,"pré","pós")) |>
    ggplot(aes(x=e, y=att*100, color=periodo, fill=periodo)) +
    geom_hline(yintercept=0, linetype="dashed", color="gray50") +
    geom_vline(xintercept=-0.5, linetype="dashed", color="gray30", linewidth=0.7) +
    geom_ribbon(aes(ymin=ci_lo*100, ymax=ci_hi*100), alpha=0.2, color=NA) +
    geom_line(linewidth=0.9) + geom_point(size=3) +
    scale_color_manual(values=c("pré"=COR_CTRL,"pós"=COR_TRAT), name=NULL) +
    scale_fill_manual(values=c("pré"=COR_CTRL,"pós"=COR_TRAT), guide="none") +
    scale_x_continuous(breaks=sort(unique(es_df_1718$e)),
                       labels=~paste0("e=", .)) +
    scale_y_continuous(labels=scales::label_number(suffix=" pp")) +
    labs(
      title    = "DR-DiD Event Study — 14–15 vs 17–18 (robustez)",
      subtitle = "Callaway & Sant'Anna (2021) | Tratada: 14–15 | Controle: 17–18",
      x        = "Tempo de evento (e = t − 2019)", y = "ATT (pp)",
      caption  = "Estimador duplamente robusto. Banda = IC 95%. Covariáveis: raça, rural."
    ) +
    theme_minimal(base_size=11) + theme(legend.position="bottom")
  
  ggsave(file.path(path_figs, "fig_drDiD_event_study_1718.png"),
         fig_es_1718, width=22, height=13, units="cm", dpi=300, bg="white")
  cat("  fig_drDiD_event_study_1718.png salvo.\n\n")
} else {
  ATT_CS_1718 <- SE_CS_1718 <- PVAL_CS_1718 <- NA_real_
  cat("  att_gt falhou — resultados do Bloco 4 indisponíveis.\n\n")
}

# ── Tabela comparativa dos dois designs DR-DiD ────────────────────────────────
# TWFE como benchmmark (mais simples, não corrige viés de heterogeneidade)
mod_twfe_1617 <- feols(
  em_uniao ~ D * as.integer(Ano %in% ANOS_POS) + parda_preta + rural |
    ano_fct + uf_fct,
  data    = filter(dados_cs_1617, Ano %in% c(ANO_REF, ANOS_EVT)),
  weights = ~pes_comcalib, cluster = ~uf_fct
)
att_twfe  <- coef(mod_twfe_1617)["D:as.integer(Ano %in% ANOS_POS)"]
se_twfe   <- se(mod_twfe_1617)["D:as.integer(Ano %in% ANOS_POS)"]
pval_twfe <- pvalue(mod_twfe_1617)["D:as.integer(Ano %in% ANOS_POS)"]

cat("\n  ── Tabela Comparativa: Estimadores DiD ─────────────────────────────\n")
cat(sprintf("  %-44s  %8s  %8s  %8s  %s\n","Estimador","ATT (pp)","SE","p-valor","IC 95%"))
cat("  ", strrep("-", 82), "\n", sep="")
fmt_linha("TWFE — 14-15 vs 16-17 (benchmark)",      att_twfe, se_twfe, pval_twfe)
fmt_linha("CS (2021) — 14-15 vs 16-17",              ATT_CS_1617, SE_CS_1617, PVAL_CS_1617)
fmt_linha("CS (2021) — 14-15 vs 17-18 (robustez)",   ATT_CS_1718, SE_CS_1718, PVAL_CS_1718)
cat("  ", strrep("-", 82), "\n", sep="")
cat("  *** p<0.01  ** p<0.05  * p<0.10\n")
cat("  TWFE: LPM com EF Ano+UF, cluster UF.\n")
cat("  CS (2021): doubly robust RC. Covariáveis: raça, rural.\n\n")

# =============================================================================
# BLOCO 5 — HonestDiD 14–15 vs 17–18 [Rambachan & Roth — robustez]
# =============================================================================
bloco("5", "HonestDiD 14–15 vs 17–18 [Rambachan & Roth — robustez]")

if (!is.null(cs_1718) && exists("att_es_1718")) {
  hd_inp_1718 <- extrair_honestdid_inputs(att_es_1718)
  
  cat(sprintf("  Períodos usados: %d pré + %d pós\n\n",
              hd_inp_1718$numPre, hd_inp_1718$numPost))
  
  if (hd_inp_1718$numPre >= 1 && hd_inp_1718$numPost >= 1) {
    hd_1718 <- rodar_honestdid(
      hd_inp_1718$betahat, hd_inp_1718$Sigma,
      hd_inp_1718$numPre,  hd_inp_1718$numPost
    )
    
    fig_hd_rm_1718 <- plot_honestdid(
      hd_1718$rm, "HonestDiD ΔRM — 14–15 vs 17–18 (robustez)",
      hd_1718$M_cal,
      subtitulo = "IC válido para violações de até Mbar × máxima violação pré-2018"
    )
    if (!is.null(fig_hd_rm_1718)) {
      ggsave(file.path(path_figs, "fig_drDiD_roth_magnitude_1718.png"),
             fig_hd_rm_1718, width=22, height=13, units="cm", dpi=300, bg="white")
      cat("\n  fig_drDiD_roth_magnitude_1718.png salvo.\n\n")
    }
  } else {
    hd_1718 <- NULL
    cat("  Períodos insuficientes — HonestDiD pulado.\n\n")
  }
} else {
  hd_1718 <- NULL
  cat("  Bloco 4 sem resultado — HonestDiD pulado.\n\n")
}

# =============================================================================
# BLOCO 6 — DiDC DESIGN INVERTIDO [Pichetti et al., 2023]
# =============================================================================
# Design invertido (Pichetti et al., 2023):
#   Running variable: c = 16 − idade_cont  (anos decimais, precisão mensal)
#   c > 0 ↔ idade_cont < 16  →  tratadas (vedação abolida pela lei)
#   c < 0 ↔ idade_cont ≥ 16  →  controle (regra inalterada)
#
# Estimador: regressão local linear (rdrobust, p=1, kernel triangular)
#   pooled pré: 2012–2018  |  pooled pós: 2019, 2022, 2023
#
# β_DiDC = RD_pós − RD_pré
#   RD = E[Y | c → 0⁺] − E[Y | c → 0⁻]
#      = E[Y | age → 16⁻] − E[Y | age → 16⁺]
#   β < 0  →  lei REDUZIU uniões entre as meninas abaixo de 16 anos
#
# Tabela de robustez: β e SE para h ∈ {0.50, 0.75, 1.00, 1.50, 2.00, 2.50, 3.00}
#   Coeficiente estável + SE decrescente com h  →  resultado robusto
bloco("6", "DiDC DESIGN INVERTIDO [Pichetti] + ROBUSTEZ POR BANDWIDTH")

tem_cont <- "idade_cont" %in% names(didc_pnadc) &&
  !all(is.na(didc_pnadc$idade_cont))

if (!tem_cont) {
  cat("  AVISO: 'idade_cont' não disponível.\n\n")
  cat("  Para habilitar:\n")
  cat(sprintf("  1. Em 08_didc.R, confirme que V2008, V20081, V20082 estão em DIDC_VARS\n"))
  cat(sprintf("  2. Delete os caches: didc_pnadc_cache.rds e didc_YYYY.rds em %s\n", CACHE_DIR))
  cat("  3. Re-execute 08_didc.R e depois este script.\n\n")
  cat("  Bloco 6 pulado.\n\n")
} else {
  
  prop_cont <- mean(!is.na(didc_pnadc$idade_cont))
  cat(sprintf("  idade_cont disponível: %.1f%% das obs.\n\n", prop_cont * 100))

  ANOS_DIDC <- sort(c(ANOS_PRE, ANOS_POS))
  BW_MAIN   <- 1.00   # bandwidth principal (resultado preferido)
  BW_rob    <- 1.50   # bandwidth para gráfico visual
  BWS       <- c(0.50, 0.75, 1.00, 1.50, 2.00, 2.50, 3.00)

  # Dados base com running variable invertida (design Pichetti)
  dados_cont <- didc_pnadc |>
    mutate(Ano = as.integer(as.character(Ano))) |>
    filter(
      Ano %in% ANOS_DIDC,
      !is.na(idade_cont), !is.na(em_uniao), !is.na(pes_comcalib)
    ) |>
    mutate(
      c_inv    = 16 - idade_cont,         # invertida: c>0 = abaixo de 16 = tratadas
      below16  = as.integer(idade_cont < 16),
      post2019 = as.integer(Ano >= 2019L),
      ano_fct  = factor(Ano),
      uf_fct   = factor(UF)
    )

  cat(sprintf("  Amostra DiDC: %d obs | Anos: %d–%d\n\n",
              nrow(dados_cont), min(dados_cont$Ano), max(dados_cont$Ano)))

  # Helper: extrair coeficiente bias-corrected e SE robusto do rdrobust
  rdr_ext <- function(rdr) {
    coef_bc <- tryCatch(
      if (is.matrix(rdr$coef)) rdr$coef[2L,1L] else rdr$coef[2L],
      error=function(e) NA_real_)
    se_rob <- tryCatch(
      if (is.matrix(rdr$se)) rdr$se[3L,1L] else rdr$se[3L],
      error=function(e) NA_real_)
    ci_lo <- tryCatch(
      if (is.matrix(rdr$ci)) rdr$ci[3L,1L] else rdr$ci[1L],
      error=function(e) NA_real_)
    ci_hi <- tryCatch(
      if (is.matrix(rdr$ci)) rdr$ci[3L,2L] else rdr$ci[2L],
      error=function(e) NA_real_)
    list(coef=coef_bc, se=se_rob, ci_lo=ci_lo, ci_hi=ci_hi,
         N_l=rdr$N[1L], N_r=rdr$N[2L])
  }

  # Helper: rdrobust com design invertido (c_inv como running variable)
  rdr_inv <- function(df, h) {
    df_bw <- df |> filter(abs(c_inv) <= h)
    if (nrow(df_bw) < 50L) return(NULL)
    tryCatch(
      rdrobust(
        y          = df_bw$em_uniao,
        x          = df_bw$c_inv,
        c          = 0,
        h          = h,
        p          = 1,
        kernel     = "triangular",
        weights    = df_bw$pes_comcalib,
        masspoints = "adjust"
      ),
      error = function(e) NULL
    )
  }
  
  # ── Tabela de robustez: β_DiDC por bandwidth (pooled pré vs pós) ─────────────
  # Abordagem pooled (Pichetti): todos os anos pré juntos, todos os pós juntos.
  # Para cada h: rdrobust(pré) → RD_pré; rdrobust(pós) → RD_pós;
  #              β_DiDC = RD_pós − RD_pré; SE = √(SE_pré² + SE_pós²)
  cat("  Estimando DiDC pooled para cada bandwidth...\n\n")

  dat_pre <- dados_cont |> filter(Ano %in% ANOS_PRE)
  dat_pos <- dados_cont |> filter(Ano %in% ANOS_POS)

  bw_tab <- map_dfr(BWS, function(h) {
    rd_pre <- rdr_inv(dat_pre, h)
    rd_pos <- rdr_inv(dat_pos, h)

    if (is.null(rd_pre) || is.null(rd_pos)) {
      return(tibble(h=h, N_pre=NA_integer_, N_pos=NA_integer_,
                    RD_pre=NA_real_, RD_pos=NA_real_,
                    beta=NA_real_, se=NA_real_, pval=NA_real_))
    }
    e_pre <- rdr_ext(rd_pre)
    e_pos <- rdr_ext(rd_pos)
    beta  <- e_pos$coef - e_pre$coef
    se    <- sqrt(e_pre$se^2 + e_pos$se^2)
    pval  <- 2 * pnorm(-abs(beta / se))
    tibble(h       = h,
           N_pre   = as.integer(e_pre$N_l + e_pre$N_r),
           N_pos   = as.integer(e_pos$N_l + e_pos$N_r),
           RD_pre  = e_pre$coef * 100,
           RD_pos  = e_pos$coef * 100,
           beta    = beta * 100,
           se      = se   * 100,
           pval    = pval)
  })

  cat("  ── Robustez por bandwidth (design invertido Pichetti) ───────────────\n")
  cat(sprintf("  %-6s  %7s  %7s  %10s  %10s  %9s  %7s  %s\n",
              "h (a)", "N_pré", "N_pós", "RD_pré(pp)", "RD_pós(pp)",
              "β_DiDC(pp)", "SE(pp)", "Sig"))
  cat("  ", strrep("-", 76), "\n", sep="")
  for (i in seq_len(nrow(bw_tab))) {
    r   <- bw_tab[i, ]
    sig <- if (is.na(r$pval)) "" else
           if (r$pval < 0.01) "***" else
           if (r$pval < 0.05) "**"  else
           if (r$pval < 0.10) "*"   else ""
    mark <- if (r$h == BW_MAIN) " ←" else ""
    cat(sprintf("  %-6.2f  %7s  %7s  %+10.3f  %+10.3f  %+9.3f  %7.3f  %s%s\n",
                r$h,
                if(is.na(r$N_pre)) "—" else as.character(r$N_pre),
                if(is.na(r$N_pos)) "—" else as.character(r$N_pos),
                r$RD_pre, r$RD_pos, r$beta, r$se, sig, mark))
  }
  cat("  ", strrep("-", 76), "\n", sep="")
  cat("  * p<0.10  ** p<0.05  *** p<0.01  ← = resultado principal\n")
  cat("  RD = E[Y|<16] − E[Y|≥16]. β < 0 → lei reduziu uniões abaixo de 16.\n\n")

  # Resultado principal (h = BW_MAIN)
  res_main     <- bw_tab |> filter(h == BW_MAIN)
  didc_rd      <- res_main$beta[1L] / 100
  se_didc_rd   <- res_main$se[1L]   / 100
  pval_didc_rd <- res_main$pval[1L]

  cat(sprintf("  ══ Resultado principal (h = %.2f ano) ══\n", BW_MAIN))
  fmt_linha(sprintf("DiDC invertido rdrobust BW=%.2f (PRINCIPAL)", BW_MAIN),
            didc_rd, se_didc_rd, pval_didc_rd)
  cat("\n")

  # ── DiDC feols pooled (auxiliar: EF ano + UF, cluster UF) ────────────────────
  dados_bw <- dados_cont |> filter(abs(c_inv) <= BW_MAIN)

  mod_didc <- tryCatch(
    feols(
      em_uniao ~
        below16 * post2019 +
        c_inv * below16 +
        c_inv * post2019 +
        c_inv * below16 * post2019 +
        parda_preta + rural | ano_fct + uf_fct,
      data=dados_bw, weights=~pes_comcalib, cluster=~uf_fct
    ),
    error=function(e) NULL
  )
  att_feols_didc  <- if (!is.null(mod_didc)) coef(mod_didc)["below16:post2019"]   else NA_real_
  se_feols_didc   <- if (!is.null(mod_didc)) se(mod_didc)["below16:post2019"]     else NA_real_
  pval_feols_didc <- if (!is.null(mod_didc)) pvalue(mod_didc)["below16:post2019"] else NA_real_

  fmt_linha(sprintf("DiDC feols BW=%.2f + EF ano/UF (auxiliar)", BW_MAIN),
            att_feols_didc, se_feols_didc, pval_feols_didc)
  cat("  rdrobust: p=1, kernel triangular, masspoints='adjust'. SE: método delta.\n")
  cat("  feols: slope linear local, EF ano e UF, cluster UF.\n\n")

  # ── Bandwidth ótimo (MSE-optimal, Calonico, Cattaneo & Titiunik 2014) ─────────
  # Sem h fixo: rdrobust escolhe automaticamente o bandwidth que minimiza o MSE.
  rdr_opt <- function(df) {
    tryCatch(
      rdrobust(y=df$em_uniao, x=df$c_inv, c=0, p=1, kernel="triangular",
               weights=df$pes_comcalib, masspoints="adjust"),
      error=function(e) NULL
    )
  }

  rd_pre_opt <- rdr_opt(dat_pre)
  rd_pos_opt <- rdr_opt(dat_pos)

  if (!is.null(rd_pre_opt) && !is.null(rd_pos_opt)) {
    h_opt_pre     <- rd_pre_opt$bws[1, 1]
    h_opt_pos     <- rd_pos_opt$bws[1, 1]
    h_opt_evt     <- mean(c(h_opt_pre, h_opt_pos))   # h médio para event study
    beta_didc_opt <- rd_pos_opt$coef[2] - rd_pre_opt$coef[2]
    se_didc_opt   <- sqrt(rd_pre_opt$se[3]^2 + rd_pos_opt$se[3]^2)
    pval_didc_opt <- 2 * pnorm(-abs(beta_didc_opt / se_didc_opt))

    cat(sprintf("  ══ Resultado com bandwidth ótimo ══\n"))
    cat(sprintf("  h_pré = %.2f ano | h_pós = %.2f ano\n", h_opt_pre, h_opt_pos))
    fmt_linha(sprintf("DiDC ótimo (h_pré=%.2f, h_pós=%.2f)", h_opt_pre, h_opt_pos),
              beta_didc_opt, se_didc_opt, pval_didc_opt)
    cat("\n")

    # Event study com h médio ótimo
    rd_opt_ano <- map_dfr(ANOS_DIDC, function(yr) {
      df_yr <- dados_cont |> filter(Ano == yr)
      rd <- tryCatch(
        rdrobust(y=df_yr$em_uniao, x=df_yr$c_inv, c=0, h=h_opt_evt,
                 p=1, kernel="triangular", weights=df_yr$pes_comcalib,
                 masspoints="adjust"),
        error=function(e) NULL)
      if (is.null(rd)) return(NULL)
      e <- rdr_ext(rd)
      tibble(ano=yr, rd=e$coef, se=e$se, ci_lo=e$ci_lo, ci_hi=e$ci_hi,
             pre=yr<2019L, metodo="rdrobust")
    })

    # Figura event study com h ótimo
    if (!is.null(rd_opt_ano) && nrow(rd_opt_ano) > 0) {
      fig_didc_evt_opt <- rd_opt_ano |>
        mutate(periodo=if_else(pre,"pré-2019","pós-2019")) |>
        ggplot(aes(x=ano, y=rd*100, color=periodo, fill=periodo)) +
        geom_hline(yintercept=0, linetype="dashed", color="gray50") +
        geom_vline(xintercept=2018.5, linetype="dashed", color="gray30", linewidth=0.7) +
        annotate("text", x=2018.7, y=max(rd_opt_ano$ci_hi*100, na.rm=TRUE)*0.92,
                 label="Lei 13.811/2019", hjust=0, size=3, color="gray30") +
        geom_ribbon(aes(ymin=ci_lo*100, ymax=ci_hi*100), alpha=0.2, color=NA) +
        geom_line(linewidth=0.9) + geom_point(size=3) +
        scale_color_manual(values=c("pré-2019"=COR_CTRL,"pós-2019"=COR_TRAT), name=NULL) +
        scale_fill_manual(values=c("pré-2019"=COR_CTRL,"pós-2019"=COR_TRAT), guide="none") +
        scale_x_continuous(breaks=sort(unique(rd_opt_ano$ano))) +
        scale_y_continuous(labels=scales::label_number(suffix=" pp")) +
        labs(
          title    = "Event Study DiDC — Bandwidth Ótimo (MSE)",
          subtitle = sprintf(
            "RD = E[Y|<16] − E[Y|≥16] | h = %.2f ano (h_pré=%.2f, h_pós=%.2f)",
            h_opt_evt, h_opt_pre, h_opt_pos),
          x=NULL, y="RD invertido no cutoff 16 anos (pp)",
          caption  = "Banda = IC 95% bias-corrected robusto."
        ) +
        theme_minimal(base_size=11) + theme(legend.position="bottom")
      ggsave(file.path(path_figs, "fig_didc_evt_opt.png"),
             fig_didc_evt_opt, width=22, height=13, units="cm", dpi=300, bg="white")
      cat("  fig_didc_evt_opt.png salvo.\n")
    }

    # Figura visual RD com h ótimo
    h_vis_opt    <- max(h_opt_pre, h_opt_pos)
    prev_bins_opt <- dados_cont |>
      filter(abs(c_inv) <= h_vis_opt) |>
      mutate(bin_cont = round((16 - c_inv) * 6) / 6,
             lbl_post = if_else(Ano >= 2019L, "pós-2019", "pré-2019")) |>
      group_by(bin_cont, lbl_post) |>
      summarise(prev=weighted.mean(em_uniao, pes_comcalib, na.rm=TRUE),
                n=n(), .groups="drop")

    fig_didc_rd_opt <- prev_bins_opt |>
      ggplot(aes(x=bin_cont, y=prev, color=lbl_post, group=lbl_post)) +
      geom_vline(xintercept=16, linetype="dashed", color="gray40", linewidth=0.8) +
      annotate("text", x=16.05, y=max(prev_bins_opt$prev, na.rm=TRUE)*0.97,
               label="Cutoff 16 anos", hjust=0, size=3, color="gray40") +
      geom_point(aes(size=n), alpha=0.6) +
      geom_smooth(method="lm", se=TRUE, alpha=0.15, linewidth=0.9,
                  data=~filter(.x, bin_cont < 16)) +
      geom_smooth(method="lm", se=TRUE, alpha=0.15, linewidth=0.9,
                  data=~filter(.x, bin_cont >= 16)) +
      scale_color_manual(values=c("pré-2019"=COR_CTRL,"pós-2019"=COR_TRAT), name=NULL) +
      scale_size_continuous(guide="none") +
      scale_y_continuous(labels=scales::percent_format(accuracy=0.1)) +
      labs(
        title   = "Descontinuidade no cutoff de 16 anos — Bandwidth Ótimo (MSE)",
        x = "Idade (anos decimais)", y = "Prevalência de uniões (%)",
        caption = sprintf(
          "Bins de ~2 meses. BW = %.2f (max(h_pré=%.2f, h_pós=%.2f)).\nβ_DiDC = %+.3f pp (SE=%.3f, p=%.3f)",
          h_vis_opt, h_opt_pre, h_opt_pos,
          beta_didc_opt*100, se_didc_opt*100, pval_didc_opt)
      ) +
      theme_minimal(base_size=11) + theme(legend.position="bottom")
    ggsave(file.path(path_figs, "fig_didc_rd_opt.png"),
           fig_didc_rd_opt, width=22, height=13, units="cm", dpi=300, bg="white")
    cat("  fig_didc_rd_opt.png salvo.\n\n")

  } else {
    h_opt_pre <- h_opt_pos <- beta_didc_opt <- se_didc_opt <- pval_didc_opt <- NA_real_
    cat("  Estimação com bandwidth ótimo falhou.\n\n")
  }

  # ── Event study DiDC por ano (design invertido) ───────────────────────────────
  cat("  Estimando RD por ano (event study DiDC — design invertido)...\n\n")

  rd_por_ano <- map_dfr(ANOS_DIDC, function(yr) {
    df_yr <- dados_cont |> filter(Ano == yr, abs(c_inv) <= BW_MAIN)
    if (nrow(df_yr) < 50L) return(NULL)

    rd <- rdr_inv(df_yr, BW_MAIN)

    if (is.null(rd)) {
      mod_loc <- tryCatch(
        feols(em_uniao ~ below16 + c_inv + I(c_inv * below16),
              data=df_yr, weights=~pes_comcalib),
        error=function(e) NULL)
      if (is.null(mod_loc)) return(NULL)
      rd_est <- coef(mod_loc)["below16"]
      rd_se  <- se(mod_loc)["below16"]
      cat(sprintf("  %d: RD = %+.4f pp (feols fallback)\n", yr, rd_est*100))
      return(tibble(ano=yr, rd=rd_est, se=rd_se,
                    ci_lo=rd_est-qnorm(0.975)*rd_se,
                    ci_hi=rd_est+qnorm(0.975)*rd_se,
                    pre=yr<2019L, metodo="feols"))
    }
    e <- rdr_ext(rd)
    cat(sprintf("  %d: RD = %+.4f pp (SE = %.4f) [N_esq=%d, N_dir=%d]\n",
                yr, e$coef*100, e$se*100, e$N_l, e$N_r))
    tibble(ano=yr, rd=e$coef, se=e$se, ci_lo=e$ci_lo, ci_hi=e$ci_hi,
           pre=yr<2019L, metodo="rdrobust")
  })
  
  # ── Gráfico event study DiDC (design invertido) ──────────────────────────────
  if (!is.null(rd_por_ano) && nrow(rd_por_ano) > 0) {
    fig_didc_evt <- rd_por_ano |>
      mutate(periodo=if_else(pre,"pré-2019","pós-2019")) |>
      ggplot(aes(x=ano, y=rd*100, color=periodo, fill=periodo)) +
      geom_hline(yintercept=0, linetype="dashed", color="gray50") +
      geom_vline(xintercept=2018.5, linetype="dashed", color="gray30", linewidth=0.7) +
      annotate("text", x=2018.7, y=max(rd_por_ano$ci_hi*100, na.rm=TRUE)*0.92,
               label="Lei 13.811/2019", hjust=0, size=3, color="gray30") +
      geom_ribbon(aes(ymin=ci_lo*100, ymax=ci_hi*100), alpha=0.2, color=NA) +
      geom_line(linewidth=0.9) + geom_point(size=3) +
      scale_color_manual(values=c("pré-2019"=COR_CTRL,"pós-2019"=COR_TRAT), name=NULL) +
      scale_fill_manual(values=c("pré-2019"=COR_CTRL,"pós-2019"=COR_TRAT), guide="none") +
      scale_x_continuous(breaks=sort(unique(rd_por_ano$ano))) +
      scale_y_continuous(labels=scales::label_number(suffix=" pp")) +
      labs(
        title    = "Event Study DiDC — Design Invertido (Pichetti)",
        subtitle = sprintf(
          "RD = E[Y|<16] − E[Y|≥16] por rdrobust (h=%.2f, p=1) | β_DiDC = RD_pós − RD_pré",
          BW_MAIN),
        x=NULL, y="RD invertido no cutoff 16 anos (pp)",
        caption  = "Banda = IC 95% bias-corrected robusto. β < 0 indica redução de uniões abaixo de 16."
      ) +
      theme_minimal(base_size=11) + theme(legend.position="bottom")

    ggsave(file.path(path_figs, "fig_didc_cont_event_study.png"),
           fig_didc_evt, width=22, height=13, units="cm", dpi=300, bg="white")
    cat("  fig_didc_cont_event_study.png salvo.\n")
  }

  # ── Gráfico visual RD: prevalência vs idade, pré vs pós ──────────────────────
  prev_bins <- dados_cont |>
    filter(abs(c_inv) <= BW_rob) |>
    mutate(
      bin_cont = round((16 - c_inv) * 6) / 6,   # idade_cont em bins de ~2 meses
      lbl_post = if_else(Ano >= 2019L, "pós-2019", "pré-2019")
    ) |>
    group_by(bin_cont, lbl_post) |>
    summarise(prev=weighted.mean(em_uniao, pes_comcalib, na.rm=TRUE),
              n=n(), .groups="drop")

  fig_didc_rd_vis <- prev_bins |>
    ggplot(aes(x=bin_cont, y=prev, color=lbl_post, group=lbl_post)) +
    geom_vline(xintercept=16, linetype="dashed", color="gray40", linewidth=0.8) +
    annotate("text", x=16.05, y=max(prev_bins$prev, na.rm=TRUE)*0.97,
             label="Cutoff 16 anos", hjust=0, size=3, color="gray40") +
    geom_point(aes(size=n), alpha=0.6) +
    geom_smooth(method="lm", se=TRUE, alpha=0.15, linewidth=0.9,
                data=~filter(.x, bin_cont < 16)) +
    geom_smooth(method="lm", se=TRUE, alpha=0.15, linewidth=0.9,
                data=~filter(.x, bin_cont >= 16)) +
    scale_color_manual(values=c("pré-2019"=COR_CTRL,"pós-2019"=COR_TRAT), name=NULL) +
    scale_size_continuous(guide="none") +
    scale_y_continuous(labels=scales::percent_format(accuracy=0.1)) +
    labs(
      title   = "Descontinuidade no cutoff de 16 anos — pré vs pós 2019",
      x       = "Idade (anos decimais)", y = "Prevalência de uniões (%)",
      caption = sprintf(
        "Bins de ~2 meses. Regressão local linear em cada lado. BW = %.1f.\n%s",
        BW_rob,
        if (!is.na(didc_rd))
          sprintf("β_DiDC = %+.3f pp (SE=%.3f, p=%.3f)", didc_rd*100, se_didc_rd*100, pval_didc_rd)
        else ""
      )
    ) +
    theme_minimal(base_size=11) + theme(legend.position="bottom")

  ggsave(file.path(path_figs, "fig_didc_rd_visual.png"),
         fig_didc_rd_vis, width=22, height=13, units="cm", dpi=300, bg="white")
  cat("  fig_didc_rd_visual.png salvo.\n\n")

}  # fim if(tem_cont)

# =============================================================================
# BLOCO 7 — DR-DiD DE CALLAWAY & SANT'ANNA COM IDADE CONTÍNUA
# =============================================================================
# Mesmo estimador dos Blocos 1b–4, mas:
#   (1) Tratamento definido por idade_cont < 16 (precisão mensal, não inteira)
#   (2) idade_cont entra como covariável contínua no xformla
#
# Vantagem: o propensity score e a regressão do outcome condicionam na idade
# exata em meses, não apenas no grupo etário anual. Uma menina de 15,9 anos
# é comparada com controles de 16,0 anos — não com o grupo 16-17 inteiro.
#
# Dois designs testados:
#   A) Tratadas: idade_cont < 16 | Controle: 16 ≤ idade_cont < 17 (análogo 1617)
#   B) Tratadas: idade_cont < 16 | Controle: 17 ≤ idade_cont < 18 (análogo 1718)
bloco("7", "DR-DiD CALLAWAY & SANT'ANNA COM IDADE CONTÍNUA")

# Fórmula com idade contínua como covariável
COVAR_FORMULA_CONT <- ~ idade_cont + parda_preta + rural + uf_fct

# ── Design A: tratadas <16, controle 16–17 ────────────────────────────────────
dados_cs_cont_A <- didc_pnadc |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  filter(
    idade %in% c(IDADES_TRAT, IDADES_CTRL1),
    Ano   %in% c(ANO_REF, ANOS_EVT),
    !is.na(idade_cont)
  ) |>
  mutate(
    D_cont = as.integer(idade_cont < 16),
    G      = if_else(D_cont == 1L, 2019, 0),
    id_obs = row_number(),
    ano_fct = factor(Ano),
    uf_fct  = factor(UF)
  )

cat(sprintf("  Design A | N = %d | Tratadas (<16): %d | Controle (16-17): %d\n\n",
            nrow(dados_cs_cont_A),
            sum(dados_cs_cont_A$D_cont == 1),
            sum(dados_cs_cont_A$D_cont == 0)))

cs_cont_A <- estimar_cs(dados_cs_cont_A, "cont <16 vs 16-17", "cont_A",
                        xformla = COVAR_FORMULA_CONT)

if (!is.null(cs_cont_A)) {
  att_es_cont_A  <- aggte(cs_cont_A, type = "dynamic", na.rm = TRUE)
  att_ov_cont_A  <- aggte(cs_cont_A, type = "simple",  na.rm = TRUE)
  ATT_CS_CONT_A  <- att_ov_cont_A$overall.att
  SE_CS_CONT_A   <- att_ov_cont_A$overall.se
  PVAL_CS_CONT_A <- 2 * pnorm(-abs(ATT_CS_CONT_A / SE_CS_CONT_A))
  fmt_linha("CS cont — <16 vs 16-17", ATT_CS_CONT_A, SE_CS_CONT_A, PVAL_CS_CONT_A)
} else {
  ATT_CS_CONT_A <- SE_CS_CONT_A <- PVAL_CS_CONT_A <- NA_real_
  att_es_cont_A <- att_ov_cont_A <- NULL
}

# ── Design B: tratadas <16, controle 17–18 ────────────────────────────────────
dados_cs_cont_B <- didc_pnadc |>
  mutate(Ano = as.integer(as.character(Ano))) |>
  filter(
    idade %in% c(IDADES_TRAT, IDADES_CTRL2),
    Ano   %in% c(ANO_REF, ANOS_EVT),
    !is.na(idade_cont)
  ) |>
  mutate(
    D_cont = as.integer(idade_cont < 16),
    G      = if_else(D_cont == 1L, 2019, 0),
    id_obs = row_number(),
    ano_fct = factor(Ano),
    uf_fct  = factor(UF)
  )

cat(sprintf("  Design B | N = %d | Tratadas (<16): %d | Controle (17-18): %d\n\n",
            nrow(dados_cs_cont_B),
            sum(dados_cs_cont_B$D_cont == 1),
            sum(dados_cs_cont_B$D_cont == 0)))

cs_cont_B <- estimar_cs(dados_cs_cont_B, "cont <16 vs 17-18", "cont_B",
                        xformla = COVAR_FORMULA_CONT)

if (!is.null(cs_cont_B)) {
  att_es_cont_B  <- aggte(cs_cont_B, type = "dynamic", na.rm = TRUE)
  att_ov_cont_B  <- aggte(cs_cont_B, type = "simple",  na.rm = TRUE)
  ATT_CS_CONT_B  <- att_ov_cont_B$overall.att
  SE_CS_CONT_B   <- att_ov_cont_B$overall.se
  PVAL_CS_CONT_B <- 2 * pnorm(-abs(ATT_CS_CONT_B / SE_CS_CONT_B))
  fmt_linha("CS cont — <16 vs 17-18", ATT_CS_CONT_B, SE_CS_CONT_B, PVAL_CS_CONT_B)
} else {
  ATT_CS_CONT_B <- SE_CS_CONT_B <- PVAL_CS_CONT_B <- NA_real_
  att_es_cont_B <- att_ov_cont_B <- NULL
}

# =============================================================================
# BLOCO 8 — DiD LOCAL COM IDADE CONTÍNUA (bandwidths estreitos)
# =============================================================================
# Comparação quasi-experimental mais direta: meninas quasi-idênticas em idade,
# separadas apenas pelo limiar legal de 16 anos.
# Tratadas: abaixo de 16 (perderam exceções com a lei)
# Controle: acima de 16 (inalteradas — podem casar com consentimento parental)
# Bandwidths: ±0.10, ±0.25, ±0.50 anos do cutoff
bloco("8", "DiD LOCAL COM IDADE CONTÍNUA [bandwidths estreitos]")

did_local_resultados <- NULL

if (exists("dados_cont") && !is.null(dados_cont) && nrow(dados_cont) > 0) {

  BWS_LOCAL <- c(1.00, 0.75, 0.50)  # ±1 ano, ±9 meses, ±6 meses

  # Para cada bandwidth: filtra amostra e estima DR-DiD via att_gt
  cs_bw_resultados <- purrr::map(BWS_LOCAL, function(bw) {
    df <- dados_cont |>
      mutate(Ano = as.integer(as.character(Ano))) |>
      filter(abs(idade_c_cont) <= bw, !is.na(idade_cont)) |>
      mutate(
        D_cont  = as.integer(idade_c_cont < 0),   # tratada: abaixo de 16
        G       = if_else(D_cont == 1L, 2019, 0),
        id_obs  = row_number(),
        ano_fct = factor(Ano),
        uf_fct  = factor(UF)
      )

    cat(sprintf("  BW = ±%.2f anos | N = %d (abaixo <16: %d, acima ≥16: %d)\n",
                bw, nrow(df), sum(df$D_cont == 1), sum(df$D_cont == 0)))

    tag   <- paste0("bw_local_", stringr::str_replace(as.character(bw), "\\.", ""))
    label <- sprintf("DR-DiD BW=±%.2f", bw)

    cs <- estimar_cs(df, label, tag, xformla = COVAR_FORMULA_CONT)

    att_es  <- if (!is.null(cs)) aggte(cs, type = "dynamic", na.rm = TRUE) else NULL
    att_ov  <- if (!is.null(cs)) aggte(cs, type = "simple",  na.rm = TRUE) else NULL
    att_val <- if (!is.null(att_ov)) att_ov$overall.att else NA_real_
    se_val  <- if (!is.null(att_ov)) att_ov$overall.se  else NA_real_
    pv_val  <- if (!is.na(att_val))  2 * pnorm(-abs(att_val / se_val)) else NA_real_

    list(bw = bw, df = df, cs = cs, att_es = att_es,
         att = att_val, se = se_val, pval = pv_val)
  }) |> purrr::set_names(paste0("bw", BWS_LOCAL))

  # Tabela comparativa
  cat("\n  ── DR-DiD por bandwidth (idade contínua) ────────────────────────────\n")
  cat(sprintf("  %-28s  %8s  %8s  %8s\n", "Bandwidth", "ATT (pp)", "SE", "p-valor"))
  cat("  ", strrep("-", 60), "\n", sep="")
  purrr::walk(cs_bw_resultados, function(res) {
    fmt_linha(sprintf("±%.2f anos (~±%d meses)", res$bw, round(res$bw * 12)),
              res$att, res$se, res$pval, w = 28)
  })
  cat("  ", strrep("-", 60), "\n\n", sep="")

} else {
  cat("  dados_cont não disponível — rode o Bloco 6 primeiro.\n")
  cs_bw_resultados <- NULL
}

# =============================================================================
# SUMÁRIO FINAL
# =============================================================================
cat(strrep("=", 70), "\n", sep="")
cat("SUMÁRIO DOS RESULTADOS\n")
cat(strrep("=", 70), "\n\n")

cat("  Design                              ATT (pp)  SE       p-valor\n")
cat("  ", strrep("-", 60), "\n", sep="")
fmt_linha("CS (2021) — 15 vs 16 (diagnóstico)", ATT_CS_1516,   SE_CS_1516,   PVAL_CS_1516,   w=35)
fmt_linha("TWFE — 14-15 vs 16-17",              att_twfe,      se_twfe,      pval_twfe,      w=35)
fmt_linha("CS (2021) — 14-15 vs 16-17",         ATT_CS_1617,   SE_CS_1617,   PVAL_CS_1617,   w=35)
fmt_linha("CS (2021) — 14-15 vs 17-18",         ATT_CS_1718,   SE_CS_1718,   PVAL_CS_1718,   w=35)
if (exists("didc_rd") && !is.na(didc_rd))
  fmt_linha("DiDC rdrobust (PRINCIPAL)",         didc_rd,       se_didc_rd,   pval_didc_rd,   w=35)
cat("  ", strrep("-", 60), "\n", sep="")
cat("  *** p<0.01  ** p<0.05  * p<0.10\n\n")

cat("  HonestDiD:\n")
if (!is.null(hd_1516)) cat("  · 15 vs 16 (diagnóstico): ver fig_drDiD_1516_roth_magnitude.png\n")
if (!is.null(hd_1617)) cat("  · 14-15 vs 16-17: ver fig_drDiD_roth_magnitude_novo.png\n")
if (!is.null(hd_1718)) cat("  · 14-15 vs 17-18: ver fig_drDiD_roth_magnitude_1718.png\n")
cat("\n")

cat(strrep("=", 70), "\n", sep="")
cat("09_did_robustez.R — concluído.\n")
cat(strrep("=", 70), "\n\n")