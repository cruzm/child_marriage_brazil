#!/usr/bin/env Rscript
# 23_export_sinasc_tables.R — LaTeX fragments for the SINASC extension results.
# Reads only outputs/tables/SINASC_*.csv produced by 22_analyze_sinasc.R.

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages(library(data.table))

root <- file.path(normalizePath(getwd(), mustWork = TRUE), "Darcio")
tdir <- file.path(root, "outputs", "tables")

fmt <- function(x, d = 1) formatC(x, format = "f", digits = d)
fmtp <- function(p) fifelse(p < 0.001, "$<$0.001", formatC(p, format = "f", digits = 3))
ci <- function(lo, hi) sprintf("[%s; %s]", fmt(lo), fmt(hi))

primary <- fread(file.path(tdir, "SINASC_STATUS_PRIMARY.csv"))
rob <- fread(file.path(tdir, "SINASC_STATUS_ROBUSTNESS.csv"))
plac <- fread(file.path(tdir, "SINASC_PLACEBO_DATES.csv"))
hac <- fread(file.path(tdir, "SINASC_BRAZIL_HAC.csv"))
miss <- fread(file.path(tdir, "SINASC_MISSINGNESS_DIAGNOSTIC.csv"))
s4 <- fread(file.path(tdir, "SINASC_FERTILITY_S4.csv"))
esd <- fread(file.path(tdir, "SINASC_EVENT_STUDY_DIAGNOSTICS.csv"))

lbl <- c(S1_married = "Married (S1)", S2_uniao_estavel = "Uni\\~ao est\\'avel (S2)",
         S3_any_union = "Any declared union (S3)")
nt_lookup <- rob[specification %chin% c("S1_no_trend", "S2_no_trend", "S3_no_trend"),
                 setNames(pct_change, sub("_no_trend", "", specification))]
primary[, key := c(S1_married = "S1", S2_uniao_estavel = "S2", S3_any_union = "S3")[specification]]

rows <- primary[, sprintf("%s & %s & %s & %s & %s & %s & %s & %s \\\\",
  lbl[specification],
  fmt(pct_change), ci(ci_lower_pct, ci_upper_pct), fmtp(p_holm),
  fmt(nt_lookup[key]),
  fmt(mde80_pct), fmtp(tost_p),
  format(n_treated_post_events, big.mark = ","))]

t11 <- c(
"\\begin{table}[!htbp]",
"\\centering",
"\\caption{SINASC status-at-birth contrasts, mothers 10--15 versus 17--19, 2019M4--M12 (extension lock v1.0.0). The frozen diagnostics reject a causal reading of these contrasts (Table~\\ref{tab:sinasc_diag}); they are reported as specification-dependence evidence.}",
"\\label{tab:sinasc_status}",
"\\begingroup\\small",
"\\begin{tabular}{lccccccc}",
"  \\hline",
" Outcome & \\% effect & 95\\% CI & $p$ (Holm) & No-trend \\% & MDE$_{80}$ \\% & TOST $p$ & Treated events \\\\ ",
"  \\hline",
rows,
"  \\hline",
"\\end{tabular}",
"\\endgroup",
"\\par\\smallskip\\begingroup\\footnotesize PPML on region-of-residence $\\times$ group $\\times$ month cells; offset = births with valid status; period-cluster inference; group-specific linear trends (column 2) or none (column 5). TOST margin: rate ratio in [0.85; 1.176].\\endgroup",
"\\end{table}")
writeLines(t11, file.path(tdir, "TABLE_11_SINASC_STATUS.tex"))

pl_rows <- plac[, sprintf("Placebo ban April %s & %s & %s & %s \\\\",
  sub("placebo_", "", specification), fmt(pct_change), ci(ci_lower_pct, ci_upper_pct), fmtp(p_value))]
s4_rows <- s4[, sprintf("%s & %s & %s & %s \\\\",
  fifelse(specification == "S4_fertility_age15", "Fertility, age 15 (S4)", "Fertility, age 14 (S4 rob.)"),
  fmt(pct_change), ci(ci_lower_pct, ci_upper_pct), fmtp(p_holm))]

t12 <- c(
"\\begin{table}[!htbp]",
"\\centering",
"\\caption{SINASC frozen diagnostics: placebo reform dates, lead test, aggregate HAC, misreporting, and fertility-composition contrasts.}",
"\\label{tab:sinasc_diag}",
"\\begingroup\\small",
"\\begin{tabular}{lccc}",
"  \\hline",
" Object & \\% effect & 95\\% CI & $p$ \\\\ ",
"  \\hline",
pl_rows,
sprintf("Brazil monthly gap, HAC(12) & %s & %s & %s \\\\",
        fmt(hac$pct_change), ci(hac$ci_lower_pct, hac$ci_upper_pct), fmtp(hac$p_value)),
sprintf("Unknown-status share (misreporting) & %s & %s & %s \\\\",
        fmt(miss$pct_change), ci(miss$ci_lower_pct, miss$ci_upper_pct), fmtp(miss$p_value)),
s4_rows,
sprintf("Joint test, 24 monthly leads & \\multicolumn{3}{c}{$p %s$} \\\\",
        fifelse(esd$joint_leads_p < 0.001, "< 0.001", paste0("= ", fmt(esd$joint_leads_p, 3)))),
"  \\hline",
"\\end{tabular}",
"\\endgroup",
"\\par\\smallskip\\begingroup\\footnotesize Placebo bans use pre-2019 data only, with the true model and windows transposed to each placebo year. Fertility rows: PPML per 100{,}000 female residents of the same age (PNADC denominators), quarterly, Holm within family.\\endgroup",
"\\end{table}")
writeLines(t12, file.path(tdir, "TABLE_12_SINASC_DIAGNOSTICS.tex"))

cat("written: TABLE_11_SINASC_STATUS.tex, TABLE_12_SINASC_DIAGNOSTICS.tex\n")
