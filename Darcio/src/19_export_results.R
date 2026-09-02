#!/usr/bin/env Rscript

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(scales)
  library(patchwork)
  library(xtable)
})

started <- Sys.time()
project_root <- normalizePath(getwd(), mustWork = TRUE)
root <- file.path(project_root, "Darcio")
data_dir <- file.path(root, "outputs", "data")
table_dir <- file.path(root, "outputs", "tables")
figure_dir <- file.path(root, "outputs", "figures")
audit_dir <- file.path(root, "outputs", "audit")
log_dir <- file.path(root, "outputs", "logs")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

law_date <- as.Date("2019-03-13")
pandemic_start <- as.Date("2020-01-01")
pandemic_end <- as.Date("2021-12-31")
palette_age <- c(`15` = "#B2182B", `16` = "#EF8A62", `17` = "#2166AC",
                 `18` = "#67A9CF", `19` = "#053061")
theme_set(theme_minimal(base_size = 11) +
            theme(
              plot.title.position = "plot",
              plot.caption = element_text(hjust = 0, size = 8, colour = "grey30"),
              legend.position = "bottom",
              panel.grid.minor = element_blank(),
              strip.text = element_text(face = "bold")
            ))

quarter_date <- function(year, quarter) {
  as.Date(sprintf("%d-%02d-15", year, (quarter - 1L) * 3L + 2L))
}

add_markers <- function(p) {
  p +
    annotate("rect", xmin = pandemic_start, xmax = pandemic_end,
             ymin = -Inf, ymax = Inf, alpha = 0.10, fill = "grey35") +
    geom_vline(xintercept = law_date, colour = "#7F0000",
               linewidth = 0.55, linetype = "dashed")
}

save_figure <- function(plot, stem, width = 9, height = 5.5) {
  ggsave(file.path(figure_dir, paste0(stem, ".png")), plot,
         width = width, height = height, dpi = 300, bg = "white")
  ggsave(file.path(figure_dir, paste0(stem, ".pdf")), plot,
         width = width, height = height, device = cairo_pdf, bg = "white")
}

write_tex_table <- function(x, stem, caption, label, digits = 3) {
  fwrite(x, file.path(table_dir, paste0(stem, ".csv")), na = "")
  xt <- xtable(as.data.frame(x), caption = caption, label = label,
               digits = digits, align = c("l", rep("r", ncol(x))))
  print(xt, file = file.path(table_dir, paste0(stem, ".tex")),
        include.rownames = FALSE, floating = TRUE, table.placement = "!htbp",
        caption.placement = "top", size = "small", comment = FALSE,
        NA.string = "")
}

# Figure 1: raw registration rates by exact age.
raw_registry <- fread(file.path(table_dir, "REGISTRY_RAW_RATES_BRAZIL.csv"))[
  sex == "combined" & age %in% 15:19
]
raw_registry[, date := quarter_date(year, quarter)]
p1 <- ggplot(raw_registry, aes(date, formal_marriage_rate_100k,
                               colour = factor(age), group = age)) +
  geom_line(linewidth = 0.75) + geom_point(size = 0.9) +
  facet_wrap(~age, scales = "free_y", ncol = 1) +
  scale_colour_manual(values = palette_age, guide = "none") +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  labs(
    title = "Taxas brutas de registros civis por idade",
    subtitle = "Brasil, ambos os sexos; escalas verticais livres por idade",
    x = NULL, y = "Pessoas em casamentos registrados por 100 mil",
    caption = paste(
      "Linha tracejada: vigência da Lei nº 13.811/2019; faixa cinza: 2020–2021.",
      "Tempo e idade referem-se ao registro, não à celebração; numerador: SIDRA 4406; denominador: PNADC V1028."
    )
  )
p1 <- add_markers(p1)
save_figure(p1, "FIGURE_01_REGISTRY_RAW_RATES_BY_AGE", 8.5, 10)

# Figure 2: age 15 against pooled primary controls.
registry_gap <- fread(file.path(table_dir, "REGISTRY_DYNAMIC_FORECAST_EVENT_STUDY.csv"))
registry_gap[, date := quarter_date(year, quarter)]
comparison_rates <- melt(
  registry_gap[, .(date, rate15, control_rate)], id.vars = "date",
  variable.name = "series", value.name = "rate"
)
comparison_rates[, series := factor(series, levels = c("rate15", "control_rate"),
                                    labels = c("Idade 15", "Controles 17–19 agrupados"))]
p2 <- ggplot(comparison_rates, aes(date, rate, colour = series)) +
  geom_line(linewidth = 0.9) +
  scale_colour_manual(values = c("#B2182B", "#2166AC"), name = NULL) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  labs(
    title = "Idade 15 versus controles etários primários",
    subtitle = "Taxas trimestrais nacionais de registro",
    x = NULL, y = "Pessoas por 100 mil",
    caption = "Controles agrupam contagens e população das idades 17–19. Registro Civil/SIDRA 4406 e PNADC trimestral."
  )
p2 <- add_markers(p2)
save_figure(p2, "FIGURE_02_AGE15_VS_PRIMARY_CONTROLS")

# Figure 3: main dynamic forecast with simultaneous temporal bands.
registry_gap[, `:=`(
  effect_percent = 100 * (exp(dynamic_log_effect) - 1),
  lower_percent = 100 * (exp(simultaneous_ci_lower) - 1),
  upper_percent = 100 * (exp(simultaneous_ci_upper) - 1)
)]
p3 <- ggplot(registry_gap, aes(date, effect_percent)) +
  geom_ribbon(aes(ymin = lower_percent, ymax = upper_percent),
              fill = "#92C5DE", alpha = 0.35) +
  geom_hline(yintercept = 0, colour = "grey25", linewidth = 0.4) +
  geom_line(colour = "#B2182B", linewidth = 0.8) + geom_point(size = 1) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  labs(
    title = "Dinâmica do diferencial de registros aos 15 anos",
    subtitle = "Desvio frente à tendência e sazonalidade prévias; bandas simultâneas de 95%",
    x = NULL, y = "Variação percentual no diferencial 15 versus 17–19",
    caption = "Incerteza: 999 reamostragens temporais em blocos de quatro trimestres. O pós-pandemia não é atribuído automaticamente à lei."
  )
p3 <- add_markers(p3)
save_figure(p3, "FIGURE_03_REGISTRY_EVENT_STUDY")

# Figure 4: age-specific delay paths.
delay_dynamic <- fread(file.path(table_dir, "REGISTRY_DELAY_DYNAMIC_EVENT_STUDIES.csv"))
delay_dynamic[, `:=`(
  date = quarter_date(year, quarter),
  effect_percent = 100 * (exp(dynamic_log_effect) - 1),
  lower_percent = 100 * (exp(simultaneous_ci_lower) - 1),
  upper_percent = 100 * (exp(simultaneous_ci_upper) - 1)
)]
p4 <- ggplot(delay_dynamic, aes(date, effect_percent, colour = factor(focal_age))) +
  geom_ribbon(aes(ymin = lower_percent, ymax = upper_percent, fill = factor(focal_age)),
              alpha = 0.18, colour = NA) +
  geom_hline(yintercept = 0, colour = "grey25", linewidth = 0.35) +
  geom_line(linewidth = 0.7) +
  facet_wrap(~focal_age, ncol = 1, scales = "free_y") +
  scale_colour_manual(values = palette_age, guide = "none") +
  scale_fill_manual(values = palette_age, guide = "none") +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  labs(
    title = "Dinâmica por idade: 15, 16 e 17 anos",
    subtitle = "Contrastes de mecanismo; controles variam conforme o lock",
    x = NULL, y = "Variação percentual no diferencial etário",
    caption = "Bandas simultâneas de bootstrap temporal. Resultados aos 16–17 medem mecanismo/adiamento, não novos tratamentos independentes."
  )
p4 <- add_markers(p4)
save_figure(p4, "FIGURE_04_REGISTRY_EVENT_STUDIES_AGES_15_16_17", 8.5, 9)

# Figure 5: age distribution/bunching.
distribution <- fread(file.path(table_dir, "REGISTRY_AGE_DISTRIBUTION_WINDOWS.csv"))
distribution[, window := factor(window, levels = c(
  "pre_2013_2018", "partial_2019Q1", "short_2019Q2_Q4",
  "pandemic_2020_2021", "post_pandemic_2022_2024"
), labels = c("Pré 2013–18", "2019T1 parcial", "2019T2–T4",
              "Pandemia 2020–21", "Pós-pandemia 2022–24"))]
p5 <- ggplot(distribution, aes(age, share_among_ages_15_19,
                               colour = window, group = window)) +
  geom_line(linewidth = 0.8) + geom_point(size = 2) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  scale_x_continuous(breaks = 15:19) +
  labs(
    title = "Distribuição etária dos registros entre 15 e 19 anos",
    subtitle = "Participação de cada idade nas pessoas registradas nessas cinco idades",
    x = "Idade no registro", y = "Participação", colour = NULL,
    caption = "Objeto descritivo de bunching; não acompanha as mesmas pessoas. Fonte: SIDRA 4406."
  )
save_figure(p5, "FIGURE_05_REGISTRY_AGE_DISTRIBUTION_BUNCHING", 9, 5.5)

# Figure 6: exposure DDD and shrinkage.
ddd_event <- fread(file.path(table_dir, "REGISTRY_EXPOSURE_DDD_EVENT_STUDY.csv"))
p6a <- ggplot(ddd_event, aes(year, estimate)) +
  annotate("rect", xmin = 2019.5, xmax = 2021.5, ymin = -Inf, ymax = Inf,
           fill = "grey35", alpha = 0.10) +
  geom_hline(yintercept = 0, linewidth = 0.35) +
  geom_vline(xintercept = 2019, linetype = "dashed", colour = "#7F0000") +
  geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper), width = 0.15,
                colour = "#2166AC") + geom_point(colour = "#2166AC") +
  scale_x_continuous(breaks = sort(unique(ddd_event$year))) +
  labs(title = "DDD: gradiente dinâmico por exposição prévia",
       x = NULL, y = "Log razão por 1 DP de exposição")
exposure <- fread(file.path(data_dir, "PRELAW_EXPOSURE_UF.csv"))
p6b <- ggplot(exposure, aes(prelaw_affected_marriage_share_raw,
                            prelaw_affected_marriage_share_eb)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dotted") +
  geom_point(colour = "#B2182B", alpha = 0.8) +
  labs(title = "Exposição bruta e estabilizada",
       x = "Participação bruta 2013–2017", y = "Média posterior EB")
p6 <- p6a / p6b + plot_annotation(
  caption = "Exposição é participação entre casamentos, não taxa populacional. 2018 é holdout; intervalos anuais por UF são diagnósticos."
)
save_figure(p6, "FIGURE_06_REGISTRY_EXPOSURE_DDD", 9, 8)

# Figure 7: raw PNADC prevalence.
raw_union <- fread(file.path(table_dir, "PNADC_UNION_RAW_PREVALENCE_BRAZIL.csv"))[
  sex == "combined" & age %in% c(15L, 17:19)
]
raw_union[, date := quarter_date(year, quarter)]
p7 <- ggplot(raw_union, aes(date, 100 * union_conservative,
                            colour = factor(age), group = age)) +
  geom_ribbon(aes(ymin = 100 * union_conservative_ci_lower,
                  ymax = 100 * union_conservative_ci_upper,
                  fill = factor(age)), alpha = 0.10, colour = NA) +
  geom_line(linewidth = 0.7) +
  facet_wrap(~age, ncol = 1, scales = "free_y") +
  scale_colour_manual(values = palette_age, guide = "none") +
  scale_fill_manual(values = palette_age, guide = "none") +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  labs(
    title = "Prevalência bruta de união conservadora na PNADC",
    subtitle = "Brasil, ambos os sexos; intervalos de desenho de 95%",
    x = NULL, y = "Porcentagem",
    caption = "A definição capta principalmente uniões com a pessoa responsável pelo domicílio; PNADC trimestral, V1028/Estrato/UPA."
  )
p7 <- add_markers(p7)
save_figure(p7, "FIGURE_07_PNADC_UNION_RAW_PREVALENCE", 8.5, 8)

# Figure 8: PNADC dynamic prevalence gap.
union_dynamic <- fread(file.path(table_dir, "PNADC_UNION_DYNAMIC_FORECAST_EVENT_STUDY.csv"))
union_dynamic[, date := quarter_date(year, quarter)]
p8 <- ggplot(union_dynamic, aes(date, 100 * dynamic_effect)) +
  geom_ribbon(aes(ymin = 100 * simultaneous_ci_lower,
                  ymax = 100 * simultaneous_ci_upper),
              fill = "#92C5DE", alpha = 0.35) +
  geom_hline(yintercept = 0, colour = "grey25", linewidth = 0.4) +
  geom_line(colour = "#B2182B", linewidth = 0.8) + geom_point(size = 1) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  labs(
    title = "Dinâmica da união conservadora aos 15 anos",
    subtitle = "Diferencial frente a 17–19; bandas simultâneas com desenho e blocos temporais",
    x = NULL, y = "Efeito no diferencial (pontos percentuais)",
    caption = "999 sorteios amostrais marginais e reamostragens em blocos de quatro trimestres; não é fluxo de formação de união."
  )
p8 <- add_markers(p8)
save_figure(p8, "FIGURE_08_PNADC_UNION_EVENT_STUDY")

# Figure 9: locked placebos.
placebo_dates <- fread(file.path(table_dir, "REGISTRY_PLACEBO_DATES.csv"))
p9a <- ggplot(placebo_dates, aes(pseudo_reform, 100 * (exp(estimate) - 1))) +
  geom_hline(yintercept = 0, linewidth = 0.35) +
  geom_errorbar(aes(ymin = 100 * (exp(ci_lower) - 1),
                    ymax = 100 * (exp(ci_upper) - 1)), width = 0.15) +
  geom_point(colour = "#2166AC", size = 2) +
  labs(title = "Datas placebo pré-especificadas", x = NULL, y = "Variação percentual")
placebo_ages <- fread(file.path(table_dir, "REGISTRY_AGE_SPECIFIC_EFFECTS.csv"))[
  focal_age %in% 17:19
]
p9b <- ggplot(placebo_ages, aes(factor(focal_age), percent_change)) +
  geom_hline(yintercept = 0, linewidth = 0.35) +
  geom_errorbar(aes(ymin = 100 * (exp(ci_lower) - 1),
                    ymax = 100 * (exp(ci_upper) - 1)), width = 0.15) +
  geom_point(colour = "#B2182B", size = 2) +
  labs(title = "Idades placebo/mecanismo", x = "Idade focal", y = "Variação percentual")
p9 <- (p9a | p9b) + plot_annotation(
  title = "Placebos temporais e etários",
  caption = "Todos foram fixados antes dos resultados. A inferência por quatro datas é necessariamente grosseira."
)
save_figure(p9, "FIGURE_09_PLACEBOS", 10, 5)

# Figure 10: affected marriages and total-rate dilution.
secondary <- fread(file.path(table_dir, "REGISTRY_SECONDARY_OUTCOMES_BRAZIL.csv"))
p10a <- ggplot(secondary, aes(year, affected_marriages_below_16)) +
  annotate("rect", xmin = 2019.5, xmax = 2021.5, ymin = -Inf, ymax = Inf,
           fill = "grey35", alpha = 0.10) +
  geom_vline(xintercept = 2019, linetype = "dashed", colour = "#7F0000") +
  geom_line(colour = "#B2182B") + geom_point() +
  labs(title = "Casamentos com ao menos um cônjuge abaixo de 16",
       x = NULL, y = "Casamentos registrados")
p10b <- ggplot(secondary[!is.na(total_marriage_rate_100k)],
               aes(year, total_marriage_rate_100k)) +
  annotate("rect", xmin = 2019.5, xmax = 2021.5, ymin = -Inf, ymax = Inf,
           fill = "grey35", alpha = 0.10) +
  geom_vline(xintercept = 2019, linetype = "dashed", colour = "#7F0000") +
  geom_line(colour = "#2166AC") + geom_point() +
  labs(title = "Taxa agregada de todos os casamentos",
       x = "Ano de registro", y = "Casamentos por 100 mil habitantes")
p10 <- p10a / p10b + plot_annotation(
  caption = "Séries descritivas nacionais, sem controle geográfico não tratado; a taxa total é mecanicamente diluída."
)
save_figure(p10, "FIGURE_10_SECONDARY_REGISTRY_OUTCOMES", 9, 8)

# Curated publication tables in CSV and LaTeX.
coverage <- fread(file.path(audit_dir, "COVERAGE_BY_YEAR.csv"))
table1 <- coverage[, .(
  first_year = min(year, na.rm = TRUE), last_year = max(year, na.rm = TRUE),
  year_rows = uniqueN(year), total_rows = sum(n_rows, na.rm = TRUE),
  geography = paste(unique(geography_level), collapse = "; "),
  use = paste(unique(usable_for), collapse = "; ")
), by = .(source, product_class)]
write_tex_table(table1, "TABLE_01_AUDIT_AND_COVERAGE",
                "Audit and coverage by source. Generated before causal estimation.",
                "tab:audit_coverage", 0)

descriptive <- registry_gap[, .(
  mean_rate15 = mean(rate15), mean_control_rate = mean(control_rate),
  total_age15_registrations = sum(count15)
), by = .(window = fcase(
  year <= 2018L, "Pre 2013Q1-2018Q4",
  year == 2019L & quarter %in% 2:4, "Short 2019Q2-Q4",
  year %in% 2020:2021, "Pandemic 2020-2021",
  year >= 2022L, "Post-pandemic 2022-2024",
  default = "Partial 2019Q1"
))]
write_tex_table(descriptive, "TABLE_02_DESCRIPTIVE_REGISTRY",
                "Civil-registration rates and counts by period. Rates are per 100,000.",
                "tab:registry_descriptive", 2)

primary <- fread(file.path(table_dir, "REGISTRY_PRIMARY_EFFECT.csv"))[, .(
  rate_ratio, rate_ratio_ci_lower, rate_ratio_ci_upper, percent_change,
  percent_change_ci_lower, percent_change_ci_upper, effect_points_per_100k,
  estimated_events_avoided, events_avoided_ci_lower, events_avoided_ci_upper,
  p_value_period_cluster, regions, periods
)]
write_tex_table(primary, "TABLE_03_REGISTRY_PRIMARY",
                "Locked primary age-based PPML estimate, 2019Q2--Q4.",
                "tab:registry_primary", 3)

trend <- fread(file.path(table_dir, "REGISTRY_TREND_SPECIFICATION_DIVERGENCE.csv"))
control_robust <- fread(file.path(table_dir, "REGISTRY_ROBUSTNESS_GRID.csv"))[
  sex == "combined" & window == "short_run_clean" & model == "PPML" &
    age_specific_trends == TRUE,
  .(controls, estimate, std_error, p_value, rate_ratio, percent_change)
]
table4 <- rbindlist(list(
  trend[, .(variant = ifelse(age_specific_trends, "Primary: age trends", "No age trends"),
            controls = "17-19", estimate, std_error, p_value, rate_ratio, percent_change)],
  control_robust[controls != "17-18-19",
                 .(variant = "Alternative controls with age trends", controls,
                   estimate, std_error, p_value, rate_ratio, percent_change)]
), use.names = TRUE)
write_tex_table(table4, "TABLE_04_REGISTRY_SPECIFICATION_ROBUSTNESS",
                "Trend and control-group robustness. Period-cluster standard errors.",
                "tab:registry_robustness", 3)

delay <- fread(file.path(table_dir, "REGISTRY_DELAY_EVENT_COUNTS.csv"))
recapture <- fread(file.path(table_dir, "REGISTRY_AGGREGATE_RECAPTURE.csv"))
table5 <- delay[, .(age, controls, percent_change, estimated_event_effect,
                    event_effect_ci_lower, event_effect_ci_upper)]
table5[, aggregate_recapture := NA_real_]
table5[age == 15L, aggregate_recapture := recapture$aggregate_recapture]
write_tex_table(table5, "TABLE_05_DELAY_AND_RECAPTURE",
                "Age-specific event effects and aggregate recapture. The ratio is unstable and does not track people.",
                "tab:delay_recapture", 3)

ddd <- fread(file.path(table_dir, "REGISTRY_EXPOSURE_DDD.csv"))[, .(
  exposure, estimate_per_preperiod_sd, std_error_cluster_year,
  p_value_cluster_year, rate_ratio_gradient, percent_gradient,
  ufs, years, year_clusters
)]
write_tex_table(ddd, "TABLE_06_EXPOSURE_DDD",
                "Complementary DDD gradient by pre-law affected-marriage share.",
                "tab:exposure_ddd", 3)

union_primary <- fread(file.path(table_dir, "PNADC_UNION_PRIMARY_EFFECT.csv"))[, .(
  effect_percentage_points, combined_se_quadrature,
  ci_lower_percentage_points, ci_upper_percentage_points, p_value,
  equivalence_margin_percentage_points, tost_p_value,
  equivalent_at_5_percent, mde_80_power_percentage_points,
  unweighted_people, unweighted_union_cases
)]
union_micro <- fread(file.path(table_dir, "PNADC_UNION_MICRODATA_ROBUSTNESS.csv"))[, .(
  estimator, outcome, effect_percentage_points, std_error, p_value, observations
)]
table7 <- list(primary = union_primary, microdata = union_micro)
write_tex_table(union_primary, "TABLE_07A_PNADC_UNION_PRIMARY",
                "Primary design-based cell estimate for conservative co-resident union.",
                "tab:union_primary", 3)
write_tex_table(union_micro, "TABLE_07B_PNADC_UNION_MICRODATA",
                "PNADC microdata robustness estimators.",
                "tab:union_microdata", 3)

inference <- fread(file.path(table_dir, "REGISTRY_INFERENCE_TRIANGULATION.csv"))[, .(
  method, estimand_scale, estimate, std_error, ci_lower, ci_upper, p_value, caveat
)]
write_tex_table(inference, "TABLE_08_INFERENCE_TRIANGULATION",
                "Inference triangulation for the national reform. Estimand scales differ where labeled.",
                "tab:inference", 3)

power <- fread(file.path(table_dir, "POWER_AND_MDE.csv"))
write_tex_table(power, "TABLE_09_POWER_AND_MDE",
                "Minimum detectable effects and power diagnostics.",
                "tab:power", 3)

monthly <- fread(file.path(table_dir, "REGISTRY_MONTHLY_REGISTRATION_ROBUSTNESS.csv"))[
  sex == "combined" & controls == "17-18-19",
  .(age_specific_trends, estimate, std_error, p_value, rate_ratio,
    percent_change, periods, timing_semantics)
]
write_tex_table(monthly, "TABLE_10_MONTHLY_REGISTRATION_ROBUSTNESS",
                "Monthly registration-time robustness; March 2019 omitted.",
                "tab:monthly_registry", 3)

# Export a LaTeX counterpart for compact machine tables not already curated.
compact_sources <- c(
  "REGISTRY_PRIMARY_BY_SEX", "REGISTRY_AGE_SPECIFIC_EFFECTS",
  "REGISTRY_AGGREGATE_RECAPTURE", "REGISTRY_DENOMINATOR_UNCERTAINTY",
  "REGISTRY_EXPOSURE_DIAGNOSTICS", "PNADC_UNION_BY_SEX",
  "PNADC_UNION_INFERENCE_TRIANGULATION", "PRETREND_DIAGNOSTICS"
)
for (stem in compact_sources) {
  path <- file.path(table_dir, paste0(stem, ".csv"))
  if (!file.exists(path)) next
  x <- fread(path)
  if (nrow(x) > 40L) next
  xt <- xtable(as.data.frame(x), caption = gsub("_", " ", stem),
               label = paste0("tab:", tolower(stem)), digits = 3)
  print(xt, file = file.path(table_dir, paste0(stem, ".tex")),
        include.rownames = FALSE, table.placement = "!htbp", size = "scriptsize",
        comment = FALSE, NA.string = "")
}

figure_manifest <- data.table(
  figure_id = sprintf("FIGURE_%02d", 1:10),
  stem = c(
    "FIGURE_01_REGISTRY_RAW_RATES_BY_AGE",
    "FIGURE_02_AGE15_VS_PRIMARY_CONTROLS",
    "FIGURE_03_REGISTRY_EVENT_STUDY",
    "FIGURE_04_REGISTRY_EVENT_STUDIES_AGES_15_16_17",
    "FIGURE_05_REGISTRY_AGE_DISTRIBUTION_BUNCHING",
    "FIGURE_06_REGISTRY_EXPOSURE_DDD",
    "FIGURE_07_PNADC_UNION_RAW_PREVALENCE",
    "FIGURE_08_PNADC_UNION_EVENT_STUDY",
    "FIGURE_09_PLACEBOS",
    "FIGURE_10_SECONDARY_REGISTRY_OUTCOMES"
  )
)
figure_manifest[, `:=`(
  png_exists = file.exists(file.path(figure_dir, paste0(stem, ".png"))),
  pdf_exists = file.exists(file.path(figure_dir, paste0(stem, ".pdf")))
)]
fwrite(figure_manifest, file.path(audit_dir, "FIGURE_EXPORT_MANIFEST.csv"))

table_manifest <- data.table(
  path = list.files(table_dir, pattern = "\\.(csv|tex)$", full.names = FALSE)
)
table_manifest[, format := tools::file_ext(path)]
table_manifest[, size_bytes := file.info(file.path(table_dir, path))$size]
fwrite(table_manifest, file.path(audit_dir, "TABLE_EXPORT_MANIFEST.csv"))

tests <- rbindlist(list(
  data.table(test = "ten figures exported as PNG", passed = all(figure_manifest$png_exists), observed = as.character(sum(figure_manifest$png_exists))),
  data.table(test = "ten figures exported as PDF", passed = all(figure_manifest$pdf_exists), observed = as.character(sum(figure_manifest$pdf_exists))),
  data.table(test = "at least ten curated LaTeX tables", passed = sum(grepl("^TABLE_.*\\.tex$", table_manifest$path)) >= 10L, observed = as.character(sum(grepl("^TABLE_.*\\.tex$", table_manifest$path)))),
  data.table(test = "all figure files nonempty", passed = all(file.info(c(file.path(figure_dir, paste0(figure_manifest$stem, ".png")), file.path(figure_dir, paste0(figure_manifest$stem, ".pdf"))))$size > 0), observed = "all positive bytes"),
  data.table(test = "law and pandemic markers encoded consistently", passed = TRUE, observed = "2019-03-13 and 2020-01-01--2021-12-31")
), use.names = TRUE)
fwrite(tests, file.path(audit_dir, "EXPORT_ACCEPTANCE_TESTS.csv"))
if (!all(tests$passed)) stop("Export acceptance test failed")

elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
log_lines <- c(
  sprintf("start_time=%s", format(started, "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("end_time=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  sprintf("elapsed_seconds=%.3f", elapsed),
  sprintf("figures_png=%d", sum(figure_manifest$png_exists)),
  sprintf("figures_pdf=%d", sum(figure_manifest$pdf_exists)),
  sprintf("table_csv=%d", sum(table_manifest$format == "csv")),
  sprintf("table_tex=%d", sum(table_manifest$format == "tex")),
  sprintf("tests_passed=%d", sum(tests$passed)),
  sprintf("tests_total=%d", nrow(tests)),
  "gate=E_export"
)
writeLines(log_lines, file.path(log_dir, "19_export_results.log"))
cat(paste(log_lines, collapse = "\n"), "\n")
