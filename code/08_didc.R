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
# NOTA: V20081 (mês) e V20082 (ano) de nascimento são usados para
# calcular idade_cont (precisão mensal — dia 15 como proxy do meio do mês).
# V2008 (dia) será adicionado futuramente para precisão diária.
# Se o cache existir sem essas variáveis, delete didc_YYYY.rds e
# didc_pnadc_cache.rds e re-execute.
DIDC_VARS <- c(
  "Ano", "UF",
  "Trimestre", # trimestre da entrevista → usado para calcular entrev_doy
  "V1032",   # peso calibrado   → pes_comcalib
  "V2005",   # condição domic.  → condno_domic
  "V2007",   # sexo
  "V2009",   # idade (inteira)  → idade
  "V2010",   # cor/raça         → cor_raca
  "V1022",   # urbano/rural     → sit_domic
  "V20081",  # mês de nascimento→ nasc_mes
  "V20082"   # ano de nascimento→ nasc_ano
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
        select(any_of(c("Ano", "UF", "Trimestre", "V1032", "V2005", "V2007",
                        "V2009", "V2010", "V1022",
                        "V20081", "V20082"))) |>
        rename(any_of(c(
          pes_comcalib = "V1032",
          condno_domic = "V2005",
          sexo         = "V2007",
          idade        = "V2009",
          cor_raca     = "V2010",
          sit_domic    = "V1022",
          nasc_mes     = "V20081",
          nasc_ano     = "V20082"
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
    ano_ref   = relevel(factor(Ano), ref = "2018"),
    # idade_cont: idade decimal em anos, calculada a partir de mês/ano de
    # nascimento. Assume entrevista em 1º de julho (dia 182 do ano) e usa
    # dia 15 como proxy do meio do mês de nascimento (precisão mensal).
    # Códigos IBGE de ignorado: mês=99, ano=9999 (ou 999).
    # V2008 (dia exato) será adicionado futuramente para precisão diária.
    idade_cont = {
      nasc_m <- suppressWarnings(as.integer(as.character(nasc_mes)))
      nasc_a <- suppressWarnings(as.integer(as.character(nasc_ano)))
      # Invalidar códigos de ignorado e valores implausíveis
      nasc_m[nasc_m >= 13L | nasc_m < 1L]  <- NA_integer_
      nasc_a[nasc_a >= 2020L]               <- NA_integer_
      nasc_a[nasc_a < 1990L]               <- NA_integer_
      # Dia do ano de nascimento: dia 15 como proxy do meio do mês
      nasc_doy <- ifelse(!is.na(nasc_m),
                         (nasc_m - 1L) * 30L + 15L,
                         NA_real_)
      # Dia do ano da entrevista: meado de cada trimestre (se disponível)
      # Q1 (jan–mar) ≈ dia 45 | Q2 (abr–jun) ≈ dia 136
      # Q3 (jul–set) ≈ dia 228 | Q4 (out–dez) ≈ dia 319
      # Fallback: 1º de julho (dia 182) se Trimestre não estiver no cache
      entrev_doy <- if ("Trimestre" %in% names(.data)) {
        trim <- suppressWarnings(as.integer(as.character(Trimestre)))
        dplyr::case_when(
          trim == 1L ~ 45L,
          trim == 2L ~ 136L,
          trim == 3L ~ 228L,
          trim == 4L ~ 319L,
          TRUE       ~ 182L
        )
      } else {
        182L
      }
      age_dias <- (as.integer(Ano) - nasc_a) * 365L +
                  (entrev_doy - nasc_doy)
      age_dias / 365.25
    },
    acima_cont   = as.integer(!is.na(idade_cont) & idade_cont >= 16),
    idade_c_cont = idade_cont - 16
  )

message(sprintf(
  "didc_pnadc: %d obs | em_uniao: %.2f%% | acima: %.2f%%",
  nrow(didc_pnadc),
  mean(didc_pnadc$em_uniao, na.rm = TRUE) * 100,
  mean(didc_pnadc$acima) * 100
))

