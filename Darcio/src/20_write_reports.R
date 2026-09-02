#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
})
Sys.setenv(TZ = "America/Sao_Paulo")

started <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
root <- file.path(project_root, "Darcio")
analysis_dir <- file.path(root, "outputs", "analysis")
audit_dir <- file.path(root, "outputs", "audit")
data_dir <- file.path(root, "outputs", "data")
table_dir <- file.path(root, "outputs", "tables")
figure_dir <- file.path(root, "outputs", "figures")
log_dir <- file.path(root, "outputs", "logs")
dir.create(analysis_dir, recursive = TRUE, showWarnings = FALSE)

read_table <- function(stem) fread(file.path(table_dir, paste0(stem, ".csv")))
fmt <- function(x, digits = 2L) formatC(x, format = "f", digits = digits,
                                       big.mark = ".", decimal.mark = ",")
fmt_int <- function(x) formatC(round(x), format = "f", digits = 0L,
                               big.mark = ".", decimal.mark = ",")
fmt_p <- function(x) {
  ifelse(x < 0.001, "<0,001", paste0("=", fmt(x, 3L)))
}
ci_pct <- function(lo, hi, digits = 1L) {
  paste0("[", fmt(lo, digits), "%; ", fmt(hi, digits), "%]")
}
ci_pp <- function(lo, hi, digits = 3L) {
  paste0("[", fmt(lo, digits), "; ", fmt(hi, digits), "] p.p.")
}
rel <- function(path) sub(paste0("^", root, "/"), "", path)

primary <- read_table("REGISTRY_PRIMARY_EFFECT")[1]
inf_registry <- read_table("REGISTRY_INFERENCE_TRIANGULATION")
trend_div <- read_table("REGISTRY_TREND_SPECIFICATION_DIVERGENCE")
pretrend <- read_table("PRETREND_DIAGNOSTICS")
power <- read_table("POWER_AND_MDE")
ages <- read_table("REGISTRY_AGE_SPECIFIC_EFFECTS")
sex_registry <- read_table("REGISTRY_PRIMARY_BY_SEX")
recapture <- read_table("REGISTRY_AGGREGATE_RECAPTURE")[1]
ddd <- read_table("REGISTRY_EXPOSURE_DDD")
ddd_diag <- read_table("REGISTRY_EXPOSURE_DIAGNOSTICS")[1]
placebo_dates <- read_table("REGISTRY_PLACEBO_DATES")
synthetic <- read_table("REGISTRY_SYNTHETIC_AGE_SUMMARY")[1]
denom_uncertainty <- read_table("REGISTRY_DENOMINATOR_UNCERTAINTY")[1]
registry_prewindow <- read_table("REGISTRY_PREWINDOW_SENSITIVITY")
monthly <- read_table("REGISTRY_MONTHLY_REGISTRATION_ROBUSTNESS")
secondary <- read_table("REGISTRY_SECONDARY_OUTCOMES_BRAZIL")
union <- read_table("PNADC_UNION_PRIMARY_EFFECT")[1]
union_inf <- read_table("PNADC_UNION_INFERENCE_TRIANGULATION")
union_micro <- read_table("PNADC_UNION_MICRODATA_ROBUSTNESS")
union_prewindow <- read_table("PNADC_UNION_PREWINDOW_SENSITIVITY")
rotation <- fread(file.path(audit_dir, "PNADC_ROTATION_MICRODATA_DIAGNOSTICS.csv"))[1]
resources <- fread(file.path(audit_dir, "GATE_B_RESOURCE_SNAPSHOT.csv"))[1]
inventory <- fread(file.path(audit_dir, "DATA_INVENTORY.csv"))
coverage <- fread(file.path(audit_dir, "COVERAGE_BY_YEAR.csv"))

age_row <- function(a) ages[focal_age == a][1]
sex_row <- function(s) sex_registry[sex == s][1]
ddd_row <- function(pattern) ddd[grepl(pattern, exposure)][1]
micro_row <- function(pattern) union_micro[grepl(pattern, estimator)][1]
secondary_row <- function(y) secondary[year == y][1]

reg_hac <- inf_registry[grepl("Newey", method)][1]
reg_forecast <- inf_registry[grepl("forecast", method)][1]
union_hac <- union_inf[grepl("Newey", method)][1]
union_forecast <- union_inf[grepl("forecast", method)][1]
reg_pre <- pretrend[outcome == "Registry log-rate gap"][1]
union_pre <- pretrend[outcome == "PNADC union prevalence gap"][1]
reg_mde <- power[outcome == "formal marriage age 15"][1]
union_mde <- power[outcome == "union_conservative age 15"][1]
monthly_primary <- monthly[
  sex == "combined" & controls == "17-18-19" & age_specific_trends == TRUE
][1]
registry_female <- sex_row("female")
registry_male <- sex_row("male")
survey_micro <- micro_row("Taylor")
cluster_micro <- micro_row("two-way dwelling")
expanded_micro <- union_micro[outcome == "union_expanded" & model_family == "linear"][1]
ddd_eb <- ddd_row("empirical-Bayes")

affected_2013 <- secondary_row(2013L)
affected_2018 <- secondary_row(2018L)
affected_2019 <- secondary_row(2019L)
affected_2024 <- secondary_row(2024L)

technical <- c(
  "# Relatório técnico — avaliação causal da Lei nº 13.811/2019",
  "",
  paste0("**Versão reproduzível gerada em:** ",
         format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), "  "),
  "**Estimando principal:** pessoas de 15 anos em casamentos civis registrados por 100 mil residentes de 15 anos  ",
  "**Desenho:** diferenças-em-diferenças por elegibilidade etária, não RD convencional  ",
  "**Especificação congelada antes dos efeitos:** `config/specification_lock.yml`",
  "",
  "## 1. Resposta curta e limites da conclusão",
  "",
  paste0(
    "Na especificação primária congelada — idade 15 versus 17–19, regiões, trimestres, ",
    "PPML com offset populacional, efeitos fixos, sazonalidade e tendências lineares específicas ",
    "por idade — a estimativa para 2019T2–T4 foi **", fmt(primary$percent_change, 1),
    "%**, IC95% ", ci_pct(primary$percent_change_ci_lower, primary$percent_change_ci_upper),
    ", p", fmt_p(primary$p_value_period_cluster), ". Em níveis, isso corresponde a ",
    fmt(primary$effect_points_per_100k, 3), " pessoa por 100 mil e a ",
    fmt(primary$estimated_events_avoided, 1), " registros previstos evitados, IC95% [",
    fmt(primary$events_avoided_ci_lower, 1), "; ", fmt(primary$events_avoided_ci_upper, 1), "]."
  ),
  "",
  paste0(
    "Esse resultado **não demonstra uma redução causal adicional** nos registros aos 15 anos no curto prazo: ",
    "o intervalo admite queda relevante e aumento relevante. Tampouco demonstra ausência de efeito. ",
    "A série já caía antes da lei, e a versão obrigatória sem tendências estima ",
    fmt(trend_div[age_specific_trends == FALSE]$percent_change, 1),
    "%, mostrando dependência material da especificação."
  ),
  "",
  paste0(
    "A PNADC produz um ponto de **+", fmt(union$effect_percentage_points, 3),
    " ponto percentual** na prevalência conservadora de união corresidente aos 15 anos, IC95% ",
    ci_pp(union$ci_lower_percentage_points, union$ci_upper_percentage_points),
    ", p", fmt_p(union$p_value), ". O intervalo quase toca zero, o teste de equivalência a ±0,50 p.p. falha ",
    "(p TOST", fmt_p(union$tost_p_value), ") e o MDE é ",
    fmt(union$mde_80_power_percentage_points, 3), " p.p. Logo, há evidência apenas **sugestiva**, não ",
    "conclusiva, de maior união corresidente relativa; não se prova informalização nem redução da formação de uniões."
  ),
  "",
  "As quatro afirmações substantivas permanecem separadas:",
  "",
  "1. **Registros civis abaixo de 16 caíram em termos descritivos.** Isso já ocorria antes de 2019; o contraste causal aos 15 anos não identifica queda adicional robusta.",
  "2. **Adiamento para 16–17 não foi estabelecido.** Os pontos são positivos, mas imprecisos; a razão de recaptura é numericamente instável.",
  "3. **Redução da formação de uniões não foi estabelecida.** A PNADC mede estoque corresidente limitado, não fluxo de formação.",
  "4. **Deslocamento para informalidade não foi estabelecido.** O ponto positivo da PNADC é compatível com essa hipótese, mas a incerteza e a diferença de objetos impedem uma afirmação causal forte.",
  "",
  "O Registro Civil mede fluxo de eventos formais; a PNADC mede estoque de pessoas em união corresidente. Os dois outcomes e seus coeficientes não são subtraídos nem tratados como a mesma variável.",
  "",
  "## 2. Marco jurídico verificado",
  "",
  "A [Lei nº 13.811, de 12 de março de 2019](https://www.planalto.gov.br/ccivil_03/_ato2019-2022/2019/lei/l13811.htm), publicada e vigente em 13 de março de 2019, alterou o art. 1.520 do Código Civil para suprimir as exceções ao casamento abaixo da idade núbil. A leitura conjunta dos arts. 1.517–1.520 do [Código Civil compilado](https://www.planalto.gov.br/ccivil_03/leis/2002/l10406compilada.htm) confirma que a lei não proibiu todo casamento abaixo de 18 anos: pessoas de 16 e 17 anos continuaram sujeitas à autorização dos pais ou representantes legais prevista no art. 1.517.",
  "",
  "Consequentemente, o tratamento direto é idade inferior a 16 anos. Com idade observada apenas em anos completos/categorias, o estudo usa DiD por elegibilidade etária. Não se apresenta uma RD convencional.",
  "",
  "## 3. Dados, auditoria e construção",
  "",
  paste0(
    "O inventário contém **", fmt_int(nrow(inventory)), " arquivos** de entrada/referência. ",
    "A reconstrução oficial do Registro Civil usa a tabela 4406 do SIDRA para 2013–2024. ",
    "A PNADC trimestral contém 48 trimestres, 24.704.364 pessoas-fonte e 2.432.627 adolescentes de 14–19 anos. ",
    "Os ZIPs trimestrais somam ", fmt(resources$raw_quarterly_compressed_gb, 2),
    " GB e poderiam expandir para ", fmt(resources$raw_quarterly_uncompressed_potential_gb, 2),
    " GB; foram lidos em streaming, sem expansão física dos TXT."
  ),
  "",
  "### 3.1 Registro Civil",
  "",
  "A fonte é uma tabela agregada de frequências, não microdados individualizados. Foram preservadas células de casamento e células de pessoas-cônjuges sem replicar linhas. Cada cônjuge entra uma vez em sua célula idade × sexo; `affected_marriage` conta casamentos em que a menor idade é inferior a 16.",
  "",
  "As 3.780 células locais idade-sexo e todos os totais locais verificáveis coincidiram exatamente com a reconstrução oficial. A documentação do [Registro Civil do IBGE](https://www.ibge.gov.br/estatisticas/sociais/populacao/9110-estatisticas-do-registro-civil.html?lang=pt-BR) e os [metadados da tabela 4406](https://sidra.ibge.gov.br/tabela/4406) estabelecem que idade e mês se referem ao **registro**, e a geografia ao cartório/lugar do registro. Não se dispõe do mês da ocorrência/celebração nem de residência comprovada.",
  "",
  "### 3.2 PNADC e denominadores",
  "",
  "O dicionário oficial específico do layout identificou V1028 como peso trimestral calibrado, Estrato e UPA como elementos do desenho, e as variáveis de idade, sexo e condição no domicílio. V1028 não foi dividido por quatro. A PNADC é tratada como repetição de cortes transversais; nenhum identificador de ordem da pessoa é usado como chave longitudinal.",
  "",
  "A regra ex ante exigiu n não ponderado ≥30 e CV populacional ≤20% por célula, com pelo menos 95% das células aprovadas e CV máximo ≤35% para escolher a geografia. UF falhou pelo CV máximo de 71,2%; região passou em 100% das células, com máximo de 9,1%, e foi escolhida para a incidência. Brasil é sensibilidade. Para união rara, Brasil combinado é primário.",
  "",
  "A definição conservadora de união vale um quando o adolescente é cônjuge/companheiro da pessoa responsável ou é responsável e há cônjuge/companheiro no domicílio. Ela não capta todas as uniões. A definição ampliada acrescenta pareamentos aninhados plausíveis e permanece uma robustez ambígua.",
  "",
  "### 3.3 Compatibilidade e timing",
  "",
  "O numerador é classificado pelo local de registro; o denominador, por residência. A agregação regional reduz, mas não elimina, a incompatibilidade. Resultados municipais foram bloqueados. A maior frequência comum válida é trimestral. 2019T1 foi omitido; pós integral começa em 2019T2. A análise mensal omite março e começa em abril, mas continua sendo mês de registro.",
  "",
  "## 4. Estratégia de identificação e specification lock",
  "",
  "O modelo primário estima contagens por PPML com log da população como offset. Inclui efeitos fixos região × idade, região × período e idade × trimestre sazonal, além de tendências lineares específicas por idade. O grupo tratado é idade 15 e os controles primários são 17–19. Os controles 18–19 e 16–17 foram congelados como robustez; o segundo conjunto pode estar contaminado por adiamento.",
  "",
  "A reforma é nacional e única. As muitas células regionais não geram tratamentos independentes. A inferência principal agrupa por trimestre-período (27 clusters, apenas três períodos pós no curto prazo) e é triangulada com série agregada HAC, bootstrap temporal, placebos e agregações alternativas. O cluster bidimensional com somente cinco regiões exigiu ajuste para matriz semidefinida positiva e produziu erro-padrão implausivelmente pequeno; ele é diagnóstico e não sustenta a conclusão.",
  "",
  "O lock foi criado em 2026-09-02T00:56:08-03:00, antes de qualquer coeficiente pós-reforma, e tem hashes SHA-256 registrados. Quatro emendas documentam apenas não identificação de bases saturadas e impossibilidade computacional do `svyglm` direto; nenhum sinal, magnitude ou significância motivou mudança.",
  "",
  "## 5. Resultados do Registro Civil",
  "",
  "### 5.1 Descrição e estimando principal",
  "",
  paste0(
    "Casamentos com ao menos um cônjuge abaixo de 16 caíram de ",
    fmt_int(affected_2013$affected_marriages_below_16), " em 2013 para ",
    fmt_int(affected_2018$affected_marriages_below_16), " em 2018, ",
    fmt_int(affected_2019$affected_marriages_below_16), " em 2019 e ",
    fmt_int(affected_2024$affected_marriages_below_16), " em 2024. ",
    "A queda prévia impede interpretar a simples diferença 2018–2019 como efeito causal."
  ),
  "",
  paste0(
    "Na categoria agregada abaixo de 15, os números foram ",
    fmt_int(affected_2018$marriages_at_least_one_below_15), " em 2018, ",
    fmt_int(affected_2019$marriages_at_least_one_below_15), " em 2019 e ",
    fmt_int(affected_2024$marriages_at_least_one_below_15), " em 2024. ",
    "Reportam-se contagem e participação, nunca uma taxa com denominador 0–14 fabricado. ",
    "No agregado, houve ", fmt_int(affected_2018$total_marriages),
    " casamentos em 2018 (", fmt(affected_2018$total_marriage_rate_100k, 1),
    " por 100 mil), ", fmt_int(affected_2019$total_marriages), " em 2019 (",
    fmt(affected_2019$total_marriage_rate_100k, 1), " por 100 mil) e ",
    fmt_int(affected_2024$total_marriages), " em 2024 (",
    fmt(affected_2024$total_marriage_rate_100k, 1),
    " por 100 mil). Essa taxa total é descritiva e mecanicamente muito diluída."
  ),
  "",
  paste0(
    "O estimando primário usa 540 células, cinco regiões e 27 trimestres. Houve ",
    fmt_int(primary$observed_events_treated_cells), " pessoas de 15 anos registradas nas células tratadas de 2019T2–T4. ",
    "A razão de taxas foi ", fmt(primary$rate_ratio, 3), " (IC95% ",
    fmt(primary$rate_ratio_ci_lower, 3), "–", fmt(primary$rate_ratio_ci_upper, 3), ")."
  ),
  "",
  "![Taxas brutas por idade](../figures/FIGURE_01_REGISTRY_RAW_RATES_BY_AGE.png)",
  "",
  "![Event study principal](../figures/FIGURE_03_REGISTRY_EVENT_STUDY.png)",
  "",
  "### 5.2 Inferência, pré-tendências e potência",
  "",
  paste0(
    "A série agregada HAC estima ", fmt(reg_hac$percent_change, 1), "% (p",
    fmt_p(reg_hac$p_value), ") e o forecast com bootstrap temporal, ",
    fmt(reg_forecast$percent_change, 1), "% (p", fmt_p(reg_forecast$p_value), "). ",
    "Esses métodos não reproduzem exatamente o PPML regional, mas confirmam que a inferência temporal é ampla."
  ),
  "",
  paste0(
    "O teste conjunto de 24 leads tem p", fmt_p(reg_pre$joint_lead_p_value),
    ", porém nenhuma banda simultânea ficou inteiramente dentro do limite econômico de ±10%. ",
    "Não rejeitar o teste não comprova tendências paralelas. Entre as datas placebo, 2015T2 apresentou ",
    "efeito negativo (p", fmt_p(placebo_dates[pseudo_reform == "2015Q2"]$p_value),
    "), e a randomization inference com só quatro datas tem p=1,00 e resolução muito baixa."
  ),
  "",
  paste0(
    "O MDE de 80% é uma queda de ", fmt(reg_mde$mde_decline_percent, 1),
    "%. A potência aproximada é ", fmt(100 * power[outcome == "formal marriage age 15" & target_decline_percent == 10]$approximate_power, 0),
    "% para queda de 10% e ", fmt(100 * power[outcome == "formal marriage age 15" & target_decline_percent == 20]$approximate_power, 0),
    "% para queda de 20%. Portanto, efeitos modestos permanecem difíceis de detectar."
  ),
  "",
  "### 5.3 Robustez e heterogeneidade",
  "",
  paste0(
    "A versão sem tendência encontra ", fmt(trend_div[age_specific_trends == FALSE]$percent_change, 1),
    "% (p", fmt_p(trend_div[age_specific_trends == FALSE]$p_value), "), contra ",
    fmt(trend_div[age_specific_trends == TRUE]$percent_change, 1), "% no modelo congelado. ",
    "A análise mensal com tendência encontra ", fmt(monthly_primary$percent_change, 1),
    "% (p", fmt_p(monthly_primary$p_value), "). As janelas pré iniciadas em 2013, 2014 e 2015 produzem, respectivamente, ",
    paste0(fmt(registry_prewindow$percent_change, 1), "%", collapse = ", "), "."
  ),
  "",
  paste0(
    "A incerteza marginal do denominador em 499 sorteios tem DP ",
    fmt(denom_uncertainty$draw_sd_beta, 3), " na escala log, menor que o erro-padrão temporal primário, ",
    "mas a covariância completa entre células não estava disponível. O controle sintético pré-2019 colocou peso ",
    fmt(100 * synthetic$weight_age17, 1), "% na idade 17 e estimou lacuna curta de ",
    fmt(synthetic$short_run_effect_points_per_100k, 3), " por 100 mil; isso é robustez descritiva, não nova identificação."
  ),
  "",
  paste0(
    "Por sexo, o ponto feminino é ", fmt(registry_female$percent_change, 1),
    "% (p ajustado Holm", fmt_p(registry_female$p_value_holm), ") e o masculino é +",
    fmt(registry_male$percent_change, 1), "% (p ajustado Holm",
    fmt_p(registry_male$p_value_holm), "). O segundo é instável: há 36 células masculinas com zero e o nível basal é raro. ",
    "A heterogeneidade não deve substituir o estimando combinado."
  ),
  "",
  "## 6. Adiamento, bunching e recaptura",
  "",
  paste0(
    "Os efeitos curtos estimados foram +", fmt(age_row(16)$percent_change, 1),
    "% aos 16 (p Holm", fmt_p(age_row(16)$p_value_holm_ages_16_19), "), +",
    fmt(age_row(17)$percent_change, 1), "% aos 17 (p Holm",
    fmt_p(age_row(17)$p_value_holm_ages_16_19), "), +",
    fmt(age_row(18)$percent_change, 1), "% aos 18 e ",
    fmt(age_row(19)$percent_change, 1), "% aos 19. Nenhum contraste 16–19 sobrevive à correção familiar."
  ),
  "",
  paste0(
    "O déficit pontual aos 15 foi apenas ", fmt(recapture$age15_estimated_deficit, 1),
    " eventos, enquanto o excesso estimado aos 16–17 foi ",
    fmt(recapture$age16_17_estimated_excess, 1), ". A recaptura agregada pontual de ",
    fmt(recapture$aggregate_recapture, 1), " tem IC95% [",
    fmt(recapture$recapture_ci_lower, 1), "; ", fmt(recapture$recapture_ci_upper, 1),
    "] e só ", fmt(100 * recapture$valid_draw_share, 1),
    "% dos sorteios definem o denominador. Ela é não informativa e não acompanha pessoas."
  ),
  "",
  "![Distribuição etária e bunching](../figures/FIGURE_05_REGISTRY_AGE_DISTRIBUTION_BUNCHING.png)",
  "",
  "## 7. Exposição prévia e DDD complementar",
  "",
  paste0(
    "A exposição é a participação de casamentos com alguém abaixo de 16 entre todos os casamentos de 2013–2017, ",
    "não uma taxa populacional. O gradiente EB por um desvio-padrão prévio é +",
    fmt(ddd_eb$percent_gradient, 1), "% (IC95% na escala log [",
    fmt(ddd_eb$ci_lower_cluster_year, 3), "; ", fmt(ddd_eb$ci_upper_cluster_year, 3),
    "], p", fmt_p(ddd_eb$p_value_cluster_year), ")."
  ),
  "",
  paste0(
    "A correlação entre exposição e mudança no holdout de 2018 é ",
    fmt(ddd_diag$exposure_holdout_change_correlation, 3),
    ", sinalizando regressão à média/tendências diferenciais. A DDD não identifica o efeito nacional médio."
  ),
  "",
  "![DDD por exposição prévia](../figures/FIGURE_06_REGISTRY_EXPOSURE_DDD.png)",
  "",
  "## 8. PNADC: união corresidente",
  "",
  paste0(
    "A análise primária de células combina ", fmt_int(union$unweighted_people),
    " observações não ponderadas nas idades 15 e 17–19. Destas, ",
    fmt_int(union$age15_unweighted_people), " têm 15 anos, com ",
    fmt_int(union$age15_unweighted_union_cases), " casos conservadores; em 2019T2–T4 são ",
    fmt_int(union$post_age15_unweighted_people), " pessoas e ",
    fmt_int(union$post_age15_unweighted_union_cases), " casos."
  ),
  "",
  paste0(
    "O modelo de células estima +", fmt(union$effect_percentage_points, 3),
    " p.p. A série agregada HAC estima +", fmt(union_hac$effect_percentage_points, 3),
    " p.p., IC95% ", ci_pp(union_hac$ci_lower_percentage_points, union_hac$ci_upper_percentage_points),
    "; o forecast temporal/desenho estima +", fmt(union_forecast$effect_percentage_points, 3),
    " p.p., IC95% ", ci_pp(union_forecast$ci_lower_percentage_points, union_forecast$ci_upper_percentage_points), "."
  ),
  "",
  paste0(
    "No microdado, a LPM com clusters domicílio-período estima +",
    fmt(100 * cluster_micro$estimate, 3), " p.p., IC95% ",
    ci_pp(100 * cluster_micro$ci_lower, 100 * cluster_micro$ci_upper),
    "; a variância Taylor Estrato/UPA estima o mesmo ponto e IC95% ",
    ci_pp(100 * survey_micro$ci_lower, 100 * survey_micro$ci_upper), ". A união ampliada estima +",
    fmt(100 * expanded_micro$estimate, 3), " p.p., p", fmt_p(expanded_micro$p_value), "."
  ),
  "",
  paste0(
    "A PNADC acompanha domicílios, não necessariamente pessoas que saem para formar união. ",
    fmt(100 * rotation$share_dwellings_multiple_periods, 1), "% dos domicílios aparecem em mais de um período e ",
    fmt(100 * rotation$share_rows_in_repeated_dwellings, 1), "% das linhas pertencem a domicílios repetidos; ",
    "isso foi incorporado à robustez de variância, não transformado em painel de transições."
  ),
  "",
  paste0(
    "O teste conjunto de leads da união tem p", fmt_p(union_pre$joint_lead_p_value),
    ", mas as bandas não estabelecem equivalência prévia. Janelas iniciadas em 2013, 2014 e 2015 estimam ",
    paste0(fmt(union_prewindow$effect_percentage_points, 3), " p.p.", collapse = ", "),
    ". O resultado comportamental é, portanto, sugestivo e sensível à janela."
  ),
  "",
  "![Prevalência bruta de união](../figures/FIGURE_07_PNADC_UNION_RAW_PREVALENCE.png)",
  "",
  "![Dinâmica da união](../figures/FIGURE_08_PNADC_UNION_EVENT_STUDY.png)",
  "",
  "## 9. Pandemia, ameaças e limitações",
  "",
  "A janela principal termina em dezembro de 2019 para reduzir contaminação pandêmica. 2020–2021 é marcado e excluído em uma robustez; 2022–2024 é descrito, não automaticamente atribuído à lei. Efeitos fixos absorvem choques gerais, mas não choques nacionais específicos por idade.",
  "",
  "As principais ameaças remanescentes são: antecipação; defasagem entre habilitação, celebração e registro; idade em anos completos no registro; mudança/cobertura administrativa; geografia de cartório versus residência; adiamento; união não registrada; composição e rotação da PNADC; denominadores estimados; outcomes raros; baixa potência; e possível evolução diferencial prévia por idade. Não há datas exatas para RD, município compatível, trajetória individual, primeiro casamento verificável ou taxa defensável para a categoria agregada abaixo de 15.",
  "",
  "## 10. Síntese inferencial",
  "",
  "O objeto efetivamente identificado é um contraste curto, por elegibilidade etária, da incidência de registros civis aos 15 anos relativa às idades 17–19, sob a hipótese de que tendências específicas lineares por idade e efeitos fixos capturam a evolução contrafactual. Os diagnósticos mostram que essa hipótese é substantivamente decisiva e não plenamente verificável.",
  "",
  "A evidência descritiva é inequívoca quanto à redução secular dos registros abaixo de 16. A evidência causal incremental para 2019 é inconclusiva na especificação congelada. Não há recaptura confiável aos 16–17. A PNADC não sustenta uma redução da união corresidente; seu ponto positivo é compatível com informalização, mas não a comprova.",
  "",
  "## 11. Replicação",
  "",
  "A partir da raiz do repositório:",
  "",
  "```bash",
  "./Darcio/run_all.sh",
  "```",
  "",
  "O comando verifica dependências, inventaria e valida fontes, reconstrói derivados, revalida o lock, estima todos os modelos, exporta CSV/LaTeX/PDF/PNG, gera os relatórios e executa os testes finais. Aquisições oficiais são reutilizadas quando hashes e schemas coincidem. O processamento limita paralelismo a quatro e lê os ZIPs trimestrais em streaming.",
  "",
  "## 12. Fontes oficiais abertas e conferidas",
  "",
  "- Presidência da República. [Lei nº 13.811/2019](https://www.planalto.gov.br/ccivil_03/_ato2019-2022/2019/lei/l13811.htm). Acesso em 2026-09-01.",
  "- Presidência da República. [Código Civil compilado, arts. 1.517–1.520](https://www.planalto.gov.br/ccivil_03/leis/2002/l10406compilada.htm). Acesso em 2026-09-01.",
  "- IBGE. [Estatísticas do Registro Civil](https://www.ibge.gov.br/estatisticas/sociais/populacao/9110-estatisticas-do-registro-civil.html?lang=pt-BR). Acesso em 2026-09-01.",
  "- IBGE. [SIDRA, tabela 4406](https://sidra.ibge.gov.br/tabela/4406). Acesso em 2026-09-01.",
  "- IBGE. [PNAD Contínua](https://www.ibge.gov.br/estatisticas/economicas/contas-nacionais/17270-pnad-continua.html). Acesso em 2026-09-01.",
  "- IBGE. [Documentação trimestral da PNADC](https://ftp.ibge.gov.br/Trabalho_e_Rendimento/Pesquisa_Nacional_por_Amostra_de_Domicilios_continua/Trimestral/Microdados/Documentacao/). Acesso em 2026-09-01.",
  "",
  "Títulos, URLs, cópias locais, hashes e notas de conferência estão em `references/SOURCES.csv`."
)
technical <- gsub("p\\.p\\.\\.", "p.p.", technical)
writeLines(technical, file.path(analysis_dir, "TECHNICAL_REPORT.md"), useBytes = TRUE)

executive <- c(
  "# Sumário executivo — Lei nº 13.811/2019",
  "",
  "## Pergunta e desenho",
  "",
  "A Lei nº 13.811/2019 entrou em vigor em 13 de março de 2019 e eliminou as exceções que permitiam casamento civil abaixo da idade núbil. Ela não proibiu todos os casamentos abaixo de 18: os de 16 e 17 anos continuaram regidos pelo art. 1.517 do Código Civil.",
  "",
  "A avaliação combina a tabela oficial 4406 do Registro Civil/SIDRA (2013–2024) com microdados trimestrais da PNADC. Como a idade existe apenas em anos completos, o desenho é diferenças-em-diferenças por elegibilidade etária, não RD. A especificação foi congelada antes dos resultados: idade 15 é tratada, idades 17–19 são controles, 2019T1 é omitido e o pós curto é 2019T2–T4. O modelo principal é PPML regional com população como offset, efeitos fixos, sazonalidade e tendências específicas por idade; a inferência principal agrupa por período porque houve uma única reforma nacional.",
  "",
  "## Resultado principal",
  "",
  paste0(
    "A estimativa congelada é **", fmt(primary$percent_change, 1), "%** nos registros aos 15 anos ",
    "(razão de taxas ", fmt(primary$rate_ratio, 3), "; IC95% ",
    ci_pct(primary$percent_change_ci_lower, primary$percent_change_ci_upper),
    "; p", fmt_p(primary$p_value_period_cluster), "). Em níveis: ",
    fmt(primary$effect_points_per_100k, 3), " por 100 mil e ",
    fmt(primary$estimated_events_avoided, 1), " eventos previstos evitados, com IC95% de ",
    fmt(primary$events_avoided_ci_lower, 1), " a ", fmt(primary$events_avoided_ci_upper, 1), "."
  ),
  "",
  paste0(
    "O intervalo não exclui uma queda de ", fmt(abs(primary$percent_change_ci_lower), 1),
    "% nem um aumento de ", fmt(primary$percent_change_ci_upper, 1),
    "%. A versão sem tendências encontra queda de ",
    fmt(abs(trend_div[age_specific_trends == FALSE]$percent_change), 1),
    "%. Essa divergência, somada a placebo significativo em 2015T2 e sensibilidade à janela pré, mostra que a trajetória descendente anterior à lei é decisiva. O estudo não sustenta uma simples leitura antes/depois."
  ),
  "",
  "## Adiamento e comportamento",
  "",
  paste0(
    "Os pontos aos 16 e 17 anos são +", fmt(age_row(16)$percent_change, 1),
    "% e +", fmt(age_row(17)$percent_change, 1),
    "%, respectivamente, mas não são precisos após correção por múltiplos testes. A recaptura agregada tem intervalo extremamente amplo e só é definida em cerca de metade dos sorteios. Não há evidência confiável de adiamento."
  ),
  "",
  paste0(
    "Na PNADC, a união conservadora aos 15 anos aumenta relativamente em **",
    fmt(union$effect_percentage_points, 3), " p.p.**, IC95% ",
    ci_pp(union$ci_lower_percentage_points, union$ci_upper_percentage_points),
    ". O MDE é ", fmt(union$mde_80_power_percentage_points, 3),
    " p.p. e a equivalência a ±0,50 p.p. não é demonstrada. Robustezes de microdados têm pontos semelhantes. ",
    "Isso é sugestivo de maior coabitação relativa, mas não prova substituição para informalidade: o Registro mede fluxo formal, a PNADC mede estoque corresidente incompleto, e seus coeficientes não podem ser subtraídos."
  ),
  "",
  "## Conclusões que os dados permitem",
  "",
  "- O número observado de casamentos com alguém abaixo de 16 caiu fortemente entre 2013 e 2024, mas grande parte da queda precede a lei.",
  "- A especificação causal congelada não identifica uma queda adicional robusta nos registros aos 15 anos em 2019T2–T4; também não prova efeito zero.",
  "- Não há evidência precisa de adiamento para 16–17 anos.",
  "- Não há evidência de redução da união corresidente; o sinal positivo é compatível, mas insuficiente, para informalização.",
  "",
  "## Limitações decisivas",
  "",
  "A fonte registra mês e idade no registro, não na celebração; cartório e residência não são a mesma geografia; não há idade exata para RD; 2019 oferece só três trimestres integralmente tratados; a PNADC não acompanha confiavelmente quem deixa o domicílio; a união conservadora capta principalmente relações com a pessoa responsável; e o estimando principal tem MDE de queda de 19,3%.",
  "",
  "## Replicação",
  "",
  "```bash",
  "./Darcio/run_all.sh",
  "```",
  "",
  "Todos os arquivos, testes, resultados e limitações estão em `Darcio/outputs/`; o lock e suas emendas estão em `Darcio/config/` e `Darcio/outputs/analysis/`."
)
executive <- gsub("p\\.p\\.\\.", "p.p.", executive)
writeLines(executive, file.path(analysis_dir, "EXECUTIVE_SUMMARY.md"), useBytes = TRUE)

# A row for every produced analysis CSV/PDF/PNG, plus explicit key-number rows.
table_files <- sort(list.files(table_dir, pattern = "\\.csv$", full.names = TRUE))
figure_files <- sort(list.files(figure_dir, pattern = "\\.(png|pdf)$", full.names = TRUE))
classify_source <- function(name) {
  if (grepl("PNADC|UNION", name)) {
    "PNADC quarterly microdata; design-based analytic cells"
  } else if (grepl("EXPOSURE|DDD", name)) {
    "IBGE SIDRA table 4406; PNADC denominator panel"
  } else if (grepl("REGISTRY|MARRIAGE|DELAY|RECAPTURE", name)) {
    "IBGE SIDRA table 4406; PNADC quarterly denominators"
  } else {
    "audited Registry and PNADC derived results"
  }
}
classify_script <- function(name) {
  if (grepl("MONTHLY", name)) return("src/17_analyze_registry_monthly.R")
  if (grepl("POWER|PRETREND", name)) return("src/18_diagnostics_power.R")
  if (grepl("PNADC", name) && grepl("MICRODATA", name)) return("src/16_analyze_pnadc_microdata.R")
  if (grepl("PNADC|UNION", name)) return("src/15_analyze_pnadc_cells.R")
  if (grepl("DDD|EXPOSURE|DELAY|RECAPTURE|AGE_SPECIFIC|DISTRIBUTION", name)) return("src/14_analyze_delay_exposure.R")
  if (grepl("REGISTRY", name)) return("src/13_analyze_registry.R")
  "src/19_export_results.R"
}
classify_spec <- function(name) {
  if (grepl("PRIMARY_EFFECT|TABLE_03", name)) return("locked primary")
  if (grepl("PLACEBO|POWER|PRETREND|ROBUSTNESS|SENSITIVITY|HAC|FORECAST", name)) return("locked diagnostic/robustness")
  if (grepl("UNION", name)) return("locked behavioral estimand/robustness")
  if (grepl("DDD|EXPOSURE", name)) return("locked complementary DDD")
  if (grepl("DELAY|RECAPTURE|AGE_SPECIFIC|BUNCHING", name)) return("locked mechanism estimand")
  "locked descriptive/export specification"
}

artifact_manifest <- rbindlist(list(
  data.table(
    result_id = paste0("TABLE_", sprintf("%03d", seq_along(table_files))),
    type = "table_csv",
    description = tools::file_path_sans_ext(basename(table_files)),
    value = NA_character_, unit = NA_character_,
    artifact = rel(table_files),
    script = vapply(basename(table_files), classify_script, character(1L)),
    source_data = vapply(basename(table_files), classify_source, character(1L)),
    specification = vapply(basename(table_files), classify_spec, character(1L)),
    causal_status = ifelse(grepl("PRIMARY", basename(table_files)),
                           "primary/confirmatory as labeled", "diagnostic, mechanism, or robustness as labeled")
  ),
  data.table(
    result_id = paste0("FIGURE_", sprintf("%03d", seq_along(figure_files))),
    type = tools::file_ext(figure_files),
    description = tools::file_path_sans_ext(basename(figure_files)),
    value = NA_character_, unit = NA_character_,
    artifact = rel(figure_files),
    script = "src/19_export_results.R",
    source_data = vapply(basename(figure_files), classify_source, character(1L)),
    specification = vapply(basename(figure_files), classify_spec, character(1L)),
    causal_status = "figure; interpretation follows underlying specification"
  )
), use.names = TRUE)

key_numbers <- data.table(
  result_id = c(
    "KEY_REGISTRY_PRIMARY_PERCENT", "KEY_REGISTRY_PRIMARY_RR",
    "KEY_REGISTRY_PRIMARY_POINTS", "KEY_REGISTRY_AVOIDED_EVENTS",
    "KEY_REGISTRY_NO_TREND", "KEY_REGISTRY_MDE",
    "KEY_DELAY_AGE16", "KEY_DELAY_AGE17", "KEY_RECAPTURE",
    "KEY_DDD_EB", "KEY_UNION_PRIMARY_PP", "KEY_UNION_MDE_PP",
    "KEY_UNION_MICRO_TAYLOR_PP", "KEY_AFFECTED_2013", "KEY_AFFECTED_2024"
  ),
  type = "key_number",
  description = c(
    "Primary short-run Registry effect", "Primary short-run Registry rate ratio",
    "Primary Registry effect in levels", "Predicted events avoided",
    "Mandatory no-trend Registry estimate", "Registry MDE at 80% power",
    "Age-16 mechanism contrast", "Age-17 mechanism contrast", "Aggregate recapture",
    "DDD gradient per pre-period SD", "Primary conservative-union effect",
    "Conservative-union MDE at 80% power", "Union microdata Taylor estimate",
    "Affected marriages below 16 in 2013", "Affected marriages below 16 in 2024"
  ),
  value = as.character(c(
    primary$percent_change, primary$rate_ratio, primary$effect_points_per_100k,
    primary$estimated_events_avoided, trend_div[age_specific_trends == FALSE]$percent_change,
    reg_mde$mde_decline_percent, age_row(16)$percent_change, age_row(17)$percent_change,
    recapture$aggregate_recapture, ddd_eb$percent_gradient, union$effect_percentage_points,
    union$mde_80_power_percentage_points, 100 * survey_micro$estimate,
    affected_2013$affected_marriages_below_16, affected_2024$affected_marriages_below_16
  )),
  unit = c(
    "percent", "rate ratio", "persons per 100,000", "persons", "percent",
    "decline percent", "percent", "percent", "ratio", "percent gradient",
    "percentage points", "percentage points", "percentage points", "marriages", "marriages"
  ),
  artifact = c(
    rep("outputs/tables/REGISTRY_PRIMARY_EFFECT.csv", 4),
    "outputs/tables/REGISTRY_TREND_SPECIFICATION_DIVERGENCE.csv",
    "outputs/tables/POWER_AND_MDE.csv",
    rep("outputs/tables/REGISTRY_AGE_SPECIFIC_EFFECTS.csv", 2),
    "outputs/tables/REGISTRY_AGGREGATE_RECAPTURE.csv",
    "outputs/tables/REGISTRY_EXPOSURE_DDD.csv",
    "outputs/tables/PNADC_UNION_PRIMARY_EFFECT.csv",
    "outputs/tables/POWER_AND_MDE.csv",
    "outputs/tables/PNADC_UNION_MICRODATA_ROBUSTNESS.csv",
    rep("outputs/tables/REGISTRY_SECONDARY_OUTCOMES_BRAZIL.csv", 2)
  ),
  script = c(
    rep("src/13_analyze_registry.R", 6),
    rep("src/14_analyze_delay_exposure.R", 4),
    "src/15_analyze_pnadc_cells.R", "src/18_diagnostics_power.R",
    "src/16_analyze_pnadc_microdata.R", rep("src/19_export_results.R", 2)
  ),
  source_data = c(
    rep("IBGE SIDRA table 4406; PNADC quarterly denominators", 10),
    rep("PNADC quarterly microdata", 3), rep("IBGE SIDRA table 4406", 2)
  ),
  specification = c(
    rep("locked primary", 4), "mandatory no-trend robustness", "locked power diagnostic",
    rep("locked mechanism estimand", 3), "locked complementary DDD",
    "locked behavioral primary", "locked power diagnostic", "locked microdata robustness",
    rep("descriptive corroboration", 2)
  ),
  causal_status = c(
    rep("primary causal contrast; assumption-sensitive", 4),
    "robustness; not selected as primary", "precision diagnostic",
    rep("mechanism contrast; not independent treatment", 2),
    "unstable aggregate accounting object", "gradient, not national average effect",
    "behavioral contrast; suggestive/inconclusive", "precision diagnostic",
    "behavioral robustness", rep("descriptive, not causal", 2)
  )
)

manifest <- rbindlist(list(key_numbers, artifact_manifest), use.names = TRUE, fill = TRUE)
setorder(manifest, type, result_id)
fwrite(manifest, file.path(analysis_dir, "RESULTS_MANIFEST.csv"), na = "")

session_lines <- c(
  paste0("generated_at=", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  paste0("project_root=", project_root),
  paste0("R=", R.version.string),
  paste0("platform=", R.version$platform),
  paste0("os=", paste(Sys.info(), collapse = ";")),
  paste0("cpu_detected=", parallel::detectCores()),
  "max_pipeline_workers=4",
  paste0("specification_lock_sha256=17f690311168b0953779e533f8a3a5b7ebf79e502237e0a4bbde3b8d07c465c2"),
  paste0("estimands_md_sha256=537fe0474cc1cd69a99251ddbc08c222b14f9685e9edf198ebce88e623b07449"),
  "",
  "--- sessionInfo() ---",
  capture.output(sessionInfo()),
  "",
  "--- git status --short ---",
  tryCatch(system2("git", c("status", "--short"), stdout = TRUE, stderr = TRUE),
           error = function(e) paste("unavailable:", conditionMessage(e)))
)
writeLines(session_lines, file.path(analysis_dir, "session_info.txt"), useBytes = TRUE)

gate_d <- c(
  "# Gate D — construção e estimação",
  "",
  paste0("Concluído em ", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), "."),
  "",
  "- Painéis regional, Brasil, UF diagnóstico, anual, mensal e células de união foram construídos com schemas e proveniência.",
  "- Foram estimadas 144 especificações de robustez do Registro, event studies, 499 sorteios de denominador e 999 reamostragens temporais.",
  "- Foram estimados adiamento, recaptura e DDD por exposição bruta/empirical Bayes.",
  "- Foram estimadas 144 especificações de células PNADC, 999 sorteios de desenho/dinâmica e quatro robustezes de microdados.",
  "- Março/2019 e 2019T1 nunca foram classificados como pós integral.",
  "- Nenhum dado bruto foi alterado e nenhuma linha agregada foi expandida por frequência.",
  "",
  "Resultados e diagnósticos estão em `outputs/tables/`, `outputs/data/` e `outputs/audit/`."
)
writeLines(gate_d, file.path(analysis_dir, "GATE_D_CONSTRUCTION_AND_ESTIMATION.md"))

gate_e <- c(
  "# Gate E — validação e relatório",
  "",
  paste0("Concluído em ", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), "."),
  "",
  "- Pré-tendências, limites econômicos, placebos de data/idade, potência e MDE foram produzidos.",
  "- Incerteza foi triangulada por período, HAC, bootstrap temporal, sorteios de desenho e microdados.",
  "- Dez figuras foram exportadas em PNG e PDF; tabelas principais em CSV e LaTeX.",
  "- O relatório técnico, sumário executivo, manifesto de resultados e informações da sessão foram gerados programaticamente.",
  "- A reprodução final é verificada por `tests/run_tests.R`; seu resultado fica em `outputs/analysis/FINAL_ACCEPTANCE.md`.",
  "",
  "A conclusão principal é inconclusiva quanto a uma queda causal incremental dos registros aos 15 anos na especificação congelada, e sugestiva porém inconclusiva quanto a aumento de união corresidente."
)
writeLines(gate_e, file.path(analysis_dir, "GATE_E_VALIDATION_AND_REPORTING.md"))

elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
writeLines(c(
  sprintf("started=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("finished=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("technical_report_lines=%d", length(technical)),
  sprintf("executive_summary_words=%d", length(strsplit(paste(executive, collapse = " "), "[[:space:]]+")[[1L]])),
  sprintf("manifest_rows=%d", nrow(manifest)),
  "gate=E_reporting"
), file.path(log_dir, "20_write_reports.log"))

cat(sprintf("reports_complete technical_lines=%d executive_words=%d manifest_rows=%d elapsed_seconds=%.1f\n",
            length(technical),
            length(strsplit(paste(executive, collapse = " "), "[[:space:]]+")[[1L]]),
            nrow(manifest), elapsed))
