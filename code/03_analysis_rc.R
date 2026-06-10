# ============================================================
# 03_analysis_rc.R — Civil Registry: descriptive analysis
# ============================================================
# Author: Yasmin Martins
# Date:   June 2026
# Input:  data/child_marriage.duckdb :: rc_panel
# Output: outputs/fig_rc_*.png
#         outputs/tbl_rc_*.csv
# ============================================================

library(tidyverse)
library(duckdb)
library(scales)
library(here)

DB_PATH <- here("data", "child_marriage.duckdb")
OUT_DIR <- here("outputs")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- Helpers ---------------------------------------------------------------

get_regiao <- function(uf) {
  norte      <- c("RO","AC","AM","RR","PA","AP","TO")
  nordeste   <- c("MA","PI","CE","RN","PB","PE","AL","SE","BA")
  sudeste    <- c("MG","ES","RJ","SP")
  sul        <- c("PR","SC","RS")
  centroeste <- c("MS","MT","GO","DF")
  case_when(
    uf %in% norte      ~ "North",
    uf %in% nordeste   ~ "Northeast",
    uf %in% sudeste    ~ "Southeast",
    uf %in% sul        ~ "South",
    uf %in% centroeste ~ "Central-West",
    TRUE               ~ NA_character_
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

# ---- Load ------------------------------------------------------------------

rc_panel <- read_duckdb_table("rc_panel", DB_PATH) |>
  mutate(regiao = get_regiao(uf))

message(sprintf("rc_panel: %d obs | %d UFs | years %d–%d",
                nrow(rc_panel), n_distinct(rc_panel$uf_cod),
                min(rc_panel$ano), max(rc_panel$ano)))

# ---- Analysis functions ----------------------------------------------------

build_annual_totals <- function(rc) {
  rc |>
    group_by(ano) |>
    summarise(
      total_marriages = sum(n_total_row, na.rm = TRUE),
      minor_brides    = sum(n_total_row * is_minor_w, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(pct_minor = minor_brides / total_marriages)
}

build_annual_by_age <- function(rc) {
  rc |>
    filter(!is.na(below_16)) |>
    group_by(ano, idade_m, below_16) |>
    summarise(n = sum(n_total_row, na.rm = TRUE), .groups = "drop") |>
    mutate(group = if_else(below_16 == 1L, "Treatment (<16)", "Control (16–17)"))
}

build_regional_trend <- function(rc) {
  rc |>
    filter(is_minor_w, !is.na(regiao)) |>
    group_by(ano, regiao) |>
    summarise(n_minor = sum(n_total_row, na.rm = TRUE), .groups = "drop")
}

build_prepost_did <- function(rc) {
  rc |>
    filter(!is.na(below_16)) |>
    group_by(pos_lei2019, below_16) |>
    summarise(
      mean_n  = mean(n_total_row, na.rm = TRUE),
      total_n = sum(n_total_row,  na.rm = TRUE),
      n_obs   = n(),
      .groups = "drop"
    ) |>
    mutate(
      period = if_else(pos_lei2019 == 1L, "Post-2019", "Pre-2019"),
      group  = if_else(below_16    == 1L, "Treatment (<16)", "Control (16–17)")
    )
}

# ---- Run analyses ----------------------------------------------------------

annual_totals  <- build_annual_totals(rc_panel)
annual_by_age  <- build_annual_by_age(rc_panel)
regional_trend <- build_regional_trend(rc_panel)
prepost_did    <- build_prepost_did(rc_panel)

message("\nPre/post DiD summary (mean marriages per municipality-year):")
prepost_did |>
  select(period, group, mean_n, total_n) |>
  mutate(across(c(mean_n, total_n), ~ round(., 1))) |>
  print()

write.csv(prepost_did, file.path(OUT_DIR, "tbl_rc_prepost.csv"), row.names = FALSE)

# ---- Figures ---------------------------------------------------------------

ano_breaks <- seq(min(rc_panel$ano), max(rc_panel$ano), by = 1)

# Figure 1: Annual trend in minor brides
p_trend <- annual_totals |>
  ggplot(aes(x = ano, y = minor_brides)) +
  geom_line(color = "#2E4053", linewidth = 1) +
  geom_point(color = "#2E4053", size = 2.5) +
  geom_vline(xintercept = 2019, linetype = "dashed", color = "red", alpha = 0.7) +
  annotate("text", x = 2019.15, y = max(annual_totals$minor_brides) * 0.9,
           label = "Lei 13.811/2019", hjust = 0, size = 3.2, color = "red") +
  scale_x_continuous(breaks = ano_breaks) +
  scale_y_continuous(labels = label_number(big.mark = ",")) +
  labs(
    title    = "Child Marriages in Brazil — Civil Registry",
    subtitle = "Annual count of registered marriages where the bride was under 18",
    x = NULL, y = "Number of marriages",
    caption  = "Source: IBGE Civil Registry Statistics (SIDRA Table 4406). Authors' elaboration."
  ) +
  theme_paper

# Figure 2: DiD structure — treatment vs control groups
age_labels <- c(
  "Menos de 15 anos" = "Under 15 (treated)",
  "15 anos"          = "Age 15 (treated)",
  "16 anos"          = "Age 16 (control)",
  "17 anos"          = "Age 17 (control)"
)

p_did <- annual_by_age |>
  mutate(age_label = recode(idade_m, !!!age_labels)) |>
  ggplot(aes(x = ano, y = n, color = age_label, linetype = group)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  geom_vline(xintercept = 2019, linetype = "dashed", color = "gray40", alpha = 0.7) +
  scale_color_brewer(palette = "Set1", name = "Bride age") +
  scale_linetype_manual(
    values = c("Treatment (<16)" = "solid", "Control (16–17)" = "dashed"),
    name   = "DiD group"
  ) +
  scale_x_continuous(breaks = ano_breaks) +
  scale_y_continuous(labels = label_number(big.mark = ",")) +
  labs(
    title    = "Child Marriages by Bride's Age — DiD Structure",
    subtitle = "Treatment: brides under 16 (banned in 2019)  |  Control: brides aged 16–17 (unaffected)",
    x = NULL, y = "Number of marriages",
    caption  = "Source: IBGE Civil Registry Statistics. Authors' elaboration."
  ) +
  theme_paper

# Figure 3: Regional trends
p_regional <- regional_trend |>
  ggplot(aes(x = ano, y = n_minor, color = regiao, group = regiao)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  geom_vline(xintercept = 2019, linetype = "dashed", color = "gray40", alpha = 0.7) +
  scale_color_brewer(palette = "Set2", name = "Region") +
  scale_x_continuous(breaks = ano_breaks) +
  scale_y_continuous(labels = label_number(big.mark = ",")) +
  labs(
    title    = "Child Marriages by Region",
    subtitle = "Annual count of registered marriages with at least one bride under 18",
    x = NULL, y = "Number of marriages",
    caption  = "Source: IBGE Civil Registry Statistics. Authors' elaboration."
  ) +
  theme_paper

# Save all figures
figures <- list(
  "fig_rc_trend.png"    = p_trend,
  "fig_rc_did.png"      = p_did,
  "fig_rc_regional.png" = p_regional
)

purrr::walk2(
  names(figures), figures,
  ~ ggsave(file.path(OUT_DIR, .x), .y,
           width = 22, height = 13, units = "cm", dpi = 300, bg = "white")
)

message(sprintf("\n03_analysis_rc.R complete. %d figures saved to: %s",
                length(figures), OUT_DIR))
