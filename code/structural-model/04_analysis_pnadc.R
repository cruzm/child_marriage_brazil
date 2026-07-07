# ============================================================
# 04_analysis_pnadc.R — PNADC: descriptive analysis
# ============================================================
# Author: Yasmin Martins
# Date:   June 2026
# Input:  data/child_marriage.duckdb :: dc_pnadc_dcm
# Output: outputs/fig_pnadc_*.png
#         outputs/tbl_pnadc_*.csv
#
# Unit of observation: every girl aged 10–17 in the PNADC
#   sample. Choice = "in_union" | "wait". Survey weights
#   via upa + estrato + pes_comcalib.  COVID years excluded.
# ============================================================

library(tidyverse)
library(srvyr)
library(duckdb)
library(scales)
library(here)

DB_PATH <- here("data", "child_marriage.duckdb")
OUT_DIR <- here("outputs")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# Minimum wage (January of each year) for income normalisation
SM_LOOKUP <- c(
  "2012"=622,  "2013"=678,  "2014"=724,  "2015"=788,
  "2016"=880,  "2017"=937,  "2018"=954,  "2019"=998,
  "2020"=1045, "2021"=1100, "2022"=1212, "2023"=1320,
  "2024"=1412
)

# ---- Helpers ---------------------------------------------------------------

uf_to_sigla <- function(uf) {
  uf <- as.character(uf)
  lookup <- c(
    "11"="RO","12"="AC","13"="AM","14"="RR","15"="PA","16"="AP","17"="TO",
    "21"="MA","22"="PI","23"="CE","24"="RN","25"="PB","26"="PE",
    "27"="AL","28"="SE","29"="BA",
    "31"="MG","32"="ES","33"="RJ","35"="SP",
    "41"="PR","42"="SC","43"="RS",
    "50"="MS","51"="MT","52"="GO","53"="DF",
    "Rondônia"="RO","Acre"="AC","Amazonas"="AM","Roraima"="RR",
    "Pará"="PA","Amapá"="AP","Tocantins"="TO",
    "Maranhão"="MA","Piauí"="PI","Ceará"="CE",
    "Rio Grande do Norte"="RN","Paraíba"="PB","Pernambuco"="PE",
    "Alagoas"="AL","Sergipe"="SE","Bahia"="BA",
    "Minas Gerais"="MG","Espírito Santo"="ES",
    "Rio de Janeiro"="RJ","São Paulo"="SP",
    "Paraná"="PR","Santa Catarina"="SC","Rio Grande do Sul"="RS",
    "Mato Grosso do Sul"="MS","Mato Grosso"="MT","Goiás"="GO",
    "Distrito Federal"="DF"
  )
  sigla <- lookup[uf]
  ifelse(is.na(sigla) & nchar(uf) == 2L, uf, sigla)
}

get_regiao <- function(uf) {
  sigla <- uf_to_sigla(uf)
  norte      <- c("RO","AC","AM","RR","PA","AP","TO")
  nordeste   <- c("MA","PI","CE","RN","PB","PE","AL","SE","BA")
  sudeste    <- c("MG","ES","RJ","SP")
  sul        <- c("PR","SC","RS")
  centroeste <- c("MS","MT","GO","DF")
  case_when(
    sigla %in% norte      ~ "North",
    sigla %in% nordeste   ~ "Northeast",
    sigla %in% sudeste    ~ "Southeast",
    sigla %in% sul        ~ "South",
    sigla %in% centroeste ~ "Central-West",
    TRUE                  ~ NA_character_
  )
}

theme_paper <- theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold", hjust = 0.5, size = 13),
    plot.subtitle    = element_text(hjust = 0.5, size = 11, color = "gray40"),
    legend.position  = "bottom",
    panel.grid.minor = element_blank(),
    axis.text        = element_text(size = 10)
  )

# ---- DuckDB helper ---------------------------------------------------------

read_duckdb_table <- function(table, db_path) {
  con <- dbConnect(duckdb(), db_path, read_only = TRUE)
  on.exit(dbDisconnect(con, shutdown = TRUE))
  dbReadTable(con, table)
}

# ---- Load and prepare ------------------------------------------------------

dc_pnadc_dcm <- read_duckdb_table("dc_pnadc_dcm", DB_PATH) |>
  mutate(
    pes_comcalib = as.numeric(pes_comcalib),
    upa          = as.character(upa),
    estrato      = as.character(estrato),
    ano          = as.integer(ano),
    in_union_bin = as.integer(choice == "in_union"),
    parda_preta  = as.integer(
      str_detect(as.character(cor_raca), regex("preta|parda", ignore_case = TRUE))
    ),
    freq_esc_bin = as.integer(
      str_detect(as.character(freq_esc), regex("^sim", ignore_case = TRUE))
    ),
    trab_bin     = as.integer(
      str_detect(as.character(trab_remun), regex("^sim", ignore_case = TRUE))
    ),
    neet_bin     = as.integer(freq_esc_bin == 0L & trab_bin == 0L),
    area         = if_else(
      str_detect(as.character(sit_domic), regex("rural", ignore_case = TRUE)),
      "Rural", "Urban"
    ),
    regiao       = get_regiao(uf),
    sm           = as.numeric(SM_LOOKUP[as.character(ano)]),
    rend_sm      = if_else(!is.na(rend) & sm > 0, rend / sm, NA_real_),
    pos_lei2019  = as.integer(ano >= 2019)
  )

message(sprintf(
  "dc_pnadc_dcm: %s obs | in_union = %s | wait = %s | years %d–%d",
  format(nrow(dc_pnadc_dcm),                         big.mark = "."),
  format(sum(dc_pnadc_dcm$in_union_bin, na.rm = TRUE), big.mark = "."),
  format(sum(1L - dc_pnadc_dcm$in_union_bin, na.rm = TRUE), big.mark = "."),
  min(dc_pnadc_dcm$ano), max(dc_pnadc_dcm$ano)
))

# ---- Survey design (COVID years excluded) ----------------------------------

pnadc_srvyr <- dc_pnadc_dcm |>
  filter(covid_year == 0L) |>
  as_survey_design(
    ids     = upa,
    strata  = estrato,
    weights = pes_comcalib,
    nest    = TRUE
  )

# ---- Analysis functions ----------------------------------------------------

build_prev_annual <- function(svy) {
  svy |>
    group_by(ano) |>
    summarise(
      prev    = survey_mean(in_union_bin, vartype = "ci", na.rm = TRUE),
      .groups = "drop"
    )
}

build_social_profile <- function(svy) {
  svy |>
    group_by(choice) |>
    summarise(
      school_rate  = survey_mean(freq_esc_bin, vartype = "ci", na.rm = TRUE),
      work_rate    = survey_mean(trab_bin,     vartype = "ci", na.rm = TRUE),
      neet_rate    = survey_mean(neet_bin,     vartype = "ci", na.rm = TRUE),
      parda_preta  = survey_mean(parda_preta,  vartype = "ci", na.rm = TRUE),
      matern_rate  = survey_mean(matern_bin,   vartype = "ci", na.rm = TRUE),
      mean_rend_sm = survey_mean(rend_sm,      vartype = "ci", na.rm = TRUE),
      .groups = "drop"
    )
}

build_schooling_annual <- function(svy) {
  svy |>
    group_by(ano, choice) |>
    summarise(
      school_rate = survey_mean(freq_esc_bin, vartype = "ci", na.rm = TRUE),
      .groups     = "drop"
    )
}

build_prev_regional <- function(svy) {
  svy |>
    filter(!is.na(regiao)) |>
    group_by(ano, regiao) |>
    summarise(
      prev    = survey_mean(in_union_bin, vartype = "ci", na.rm = TRUE),
      .groups = "drop"
    )
}

build_prev_area <- function(svy) {
  svy |>
    group_by(ano, area) |>
    summarise(
      prev    = survey_mean(in_union_bin, vartype = "ci", na.rm = TRUE),
      .groups = "drop"
    )
}

build_age_gap_dist <- function(df) {
  df |>
    filter(choice == "in_union", !is.na(delta), covid_year == 0L) |>
    mutate(delta_round = round(delta)) |>
    group_by(delta_round) |>
    summarise(n_weighted = sum(pes_comcalib, na.rm = TRUE), .groups = "drop") |>
    mutate(pct = n_weighted / sum(n_weighted))
}

# ---- Run analyses ----------------------------------------------------------

prev_annual      <- build_prev_annual(pnadc_srvyr)
social_profile   <- build_social_profile(pnadc_srvyr)
schooling_annual <- build_schooling_annual(pnadc_srvyr)
prev_regional    <- build_prev_regional(pnadc_srvyr)
prev_area        <- build_prev_area(pnadc_srvyr)
age_gap_dist     <- build_age_gap_dist(dc_pnadc_dcm)

mean_delta <- with(age_gap_dist,
  sum(delta_round * n_weighted, na.rm = TRUE) / sum(n_weighted, na.rm = TRUE))

message("\nSocial profile — in_union vs wait (survey-weighted):")
social_profile |>
  select(choice, school_rate, work_rate, neet_rate, parda_preta, mean_rend_sm) |>
  mutate(across(where(is.numeric), ~ round(., 3))) |>
  print()

write.csv(prev_annual,    file.path(OUT_DIR, "tbl_pnadc_prev_annual.csv"),    row.names = FALSE)
write.csv(social_profile, file.path(OUT_DIR, "tbl_pnadc_social_profile.csv"), row.names = FALSE)

# ---- Figures ---------------------------------------------------------------

ano_breaks <- sort(unique(prev_annual$ano))

# Figure 1: Annual prevalence
p_prev <- prev_annual |>
  ggplot(aes(x = ano, y = prev)) +
  geom_ribbon(aes(ymin = prev_low, ymax = prev_upp), alpha = 0.15, fill = "#2E4053") +
  geom_line(color = "#2E4053", linewidth = 1) +
  geom_point(color = "#2E4053", size = 2.5) +
  geom_vline(xintercept = 2019, linetype = "dashed", color = "red", alpha = 0.7) +
  annotate("text", x = 2019.15, y = max(prev_annual$prev_upp, na.rm = TRUE) * 0.97,
           label = "Lei 13.811/2019", hjust = 0, size = 3, color = "red") +
  scale_x_continuous(breaks = ano_breaks) +
  scale_y_continuous(labels = label_percent(accuracy = 0.1)) +
  labs(
    title    = "Annual Prevalence of Child Marriage (PNADC)",
    subtitle = "Share of girls aged 10–17 in a union — survey-weighted, COVID years excluded",
    x = NULL, y = "Prevalence (%)",
    caption  = "Source: PNADC, complex survey design (UPA + strata + calibrated weights). Band = 95% CI. Authors' elaboration."
  ) +
  theme_paper

# Figure 2: School attendance — in union vs not
p_school <- schooling_annual |>
  mutate(
    choice_label = if_else(choice == "in_union", "In union", "Not in union"),
    ano          = as.integer(ano)
  ) |>
  ggplot(aes(x = ano, y = school_rate, color = choice_label,
             fill = choice_label, group = choice_label)) +
  geom_ribbon(aes(ymin = school_rate_low, ymax = school_rate_upp),
              alpha = 0.12, color = NA) +
  geom_line(linewidth = 1) +
  geom_point(size = 2.5) +
  geom_vline(xintercept = 2019, linetype = "dashed", color = "gray40", alpha = 0.7) +
  scale_color_manual(values = c("In union" = "#C0392B", "Not in union" = "#2980B9"),
                     name = NULL) +
  scale_fill_manual(values  = c("In union" = "#C0392B", "Not in union" = "#2980B9"),
                    guide = "none") +
  scale_x_continuous(breaks = ano_breaks) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) +
  labs(
    title    = "School Attendance — Girls Aged 10–17",
    subtitle = "Survey-weighted; in union vs. not in union (COVID years excluded)",
    x = NULL, y = "School attendance rate (%)",
    caption  = "Source: PNADC. Band = 95% CI. Authors' elaboration."
  ) +
  theme_paper

# Figure 3: Age gap distribution
p_agegap <- age_gap_dist |>
  filter(delta_round >= 0, delta_round <= 35) |>
  ggplot(aes(x = delta_round, y = pct)) +
  geom_col(fill = "#C0392B", alpha = 0.8) +
  geom_vline(xintercept = mean_delta, linetype = "dashed", color = "gray30") +
  annotate("text", x = mean_delta + 0.5,
           y = max(age_gap_dist$pct[age_gap_dist$delta_round <= 35], na.rm = TRUE) * 0.9,
           label = sprintf("Mean = %.1f yrs", mean_delta),
           hjust = 0, size = 3.2, color = "gray30") +
  scale_x_continuous(breaks = seq(0, 35, by = 5)) +
  scale_y_continuous(labels = label_percent(accuracy = 0.1)) +
  labs(
    title    = "Age Gap Distribution — Girls in a Union",
    subtitle = "Difference between household head's age and girl's age (pooled, non-COVID years)",
    x = "Age gap (years)", y = "Share (%)",
    caption  = "Source: PNADC, survey-weighted. Authors' elaboration."
  ) +
  theme_paper

# Figure 4: Regional prevalence
p_regional <- prev_regional |>
  mutate(ano = as.integer(ano)) |>
  ggplot(aes(x = ano, y = prev, color = regiao, fill = regiao, group = regiao)) +
  geom_ribbon(aes(ymin = prev_low, ymax = prev_upp), alpha = 0.1, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  geom_vline(xintercept = 2019, linetype = "dashed", color = "gray40", alpha = 0.7) +
  scale_color_brewer(palette = "Set1", name = "Region") +
  scale_fill_brewer(palette  = "Set1", guide = "none") +
  scale_x_continuous(breaks = ano_breaks) +
  scale_y_continuous(labels = label_percent(accuracy = 0.1)) +
  labs(
    title    = "Child Marriage Prevalence by Region (PNADC)",
    subtitle = "Share of girls 10–17 in a union — regional comparison",
    x = NULL, y = "Prevalence (%)",
    caption  = "Source: PNADC. Band = 95% CI. Authors' elaboration."
  ) +
  theme_paper

# Figure 5: Urban vs rural
p_area <- prev_area |>
  mutate(ano = as.integer(ano)) |>
  ggplot(aes(x = ano, y = prev, color = area, fill = area, group = area)) +
  geom_ribbon(aes(ymin = prev_low, ymax = prev_upp), alpha = 0.12, color = NA) +
  geom_line(linewidth = 1) +
  geom_point(size = 2.5) +
  geom_vline(xintercept = 2019, linetype = "dashed", color = "gray40", alpha = 0.7) +
  scale_color_manual(values = c("Rural" = "#C0392B", "Urban" = "#2980B9"), name = NULL) +
  scale_fill_manual(values  = c("Rural" = "#C0392B", "Urban" = "#2980B9"), guide = "none") +
  scale_x_continuous(breaks = ano_breaks) +
  scale_y_continuous(labels = label_percent(accuracy = 0.1)) +
  labs(
    title    = "Child Marriage Prevalence — Urban vs. Rural",
    subtitle = "Share of girls 10–17 in a union by area of residence",
    x = NULL, y = "Prevalence (%)",
    caption  = "Source: PNADC. Band = 95% CI. Authors' elaboration."
  ) +
  theme_paper

# Save all figures
figures <- list(
  "fig_pnadc_prevalence.png" = p_prev,
  "fig_pnadc_schooling.png"  = p_school,
  "fig_pnadc_age_gap.png"    = p_agegap,
  "fig_pnadc_regional.png"   = p_regional,
  "fig_pnadc_urban_rural.png" = p_area
)

purrr::walk2(
  names(figures), figures,
  ~ ggsave(file.path(OUT_DIR, .x), .y,
           width = 22, height = 13, units = "cm", dpi = 300, bg = "white")
)

message(sprintf("\n04_analysis_pnadc.R complete. %d figures saved to: %s",
                length(figures), OUT_DIR))
