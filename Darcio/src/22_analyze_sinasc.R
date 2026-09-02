#!/usr/bin/env Rscript
# 22_analyze_sinasc.R — estimate the frozen SINASC extension estimands
# (config/sinasc_extension_lock.yml v1.0.0, frozen 2026-09-02T11:28:14-03:00,
# hashes in outputs/analysis/SINASC_EXTENSION_LOCK_SHA256.txt).
# Every model below implements a rule stated in the lock; nothing here was
# chosen after seeing a post-reform SINASC contrast.

.libPaths(c(file.path("Darcio", "library"), .libPaths()))
suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(sandwich)
  library(lmtest)
  library(yaml)
})

started <- Sys.time()
set.seed(13811)
setFixest_nthreads(1)
setFixest_notes(FALSE)
project_root <- normalizePath(getwd(), mustWork = TRUE)
root <- file.path(project_root, "Darcio")
data_dir <- file.path(root, "outputs", "data")
table_dir <- file.path(root, "outputs", "tables")
figure_dir <- file.path(root, "outputs", "figures")
log_dir <- file.path(root, "outputs", "logs")
log_file <- file.path(log_dir, "22_analyze_sinasc.log")
log_line <- function(...) {
  msg <- sprintf("[%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), paste0(...))
  cat(msg, "\n"); cat(msg, "\n", file = log_file, append = TRUE)
}
lock <- read_yaml(file.path(root, "config", "sinasc_extension_lock.yml"))
log_line("start | lock version ", lock$extension$version, " frozen ", lock$extension$frozen_at)

cells <- fread(file.path(data_dir, "SINASC_MONTHLY_STATUS_CELLS.csv"))
exact <- fread(file.path(data_dir, "SINASC_MONTHLY_STATUS_CELLS_EXACT.csv"))

# Amendment A1 (2026-09-02, logged in SINASC_EXTENSION_AMENDMENTS.md BEFORE this
# re-estimation): the official open export for 2015 is materially incomplete
# (2,786,525 records vs. 3,017,668 implied by the SVSA bulletin sum identity;
# deficit concentrated in Oct-Dec). Calendar year 2015 is excluded from every
# estimation sample; placebo April/2015 is dropped.
cells <- cells[birth_year != 2015L]
exact <- exact[birth_year != 2015L]
log_line("Amendment A1 applied: birth_year 2015 excluded from all samples")

# ---------------------------------------------------------------- panel setup
prep_panel <- function(d, treated_ages = 10:15, control_ages = c(17L, 18L, 19L),
                       treated_label = "g_treated") {
  z <- copy(d)[region >= 1L & region <= 5L]
  z[, group := fifelse(age %in% treated_ages, treated_label,
               fifelse(age %in% control_ages, paste0("a", age), NA_character_))]
  z <- z[!is.na(group)]
  z <- z[, .(n_births = sum(n_births), n_valid = sum(n_valid_status),
             n_married = sum(n_married), n_ue = sum(n_uniao_estavel),
             n_union = sum(n_married) + sum(n_uniao_estavel),
             n_unknown = sum(n_unknown)),
         by = .(birth_year, birth_month, region, group)]
  z[, period_index := (birth_year - 2013L) * 12L + birth_month]
  z[, period := sprintf("%d-%02d", birth_year, birth_month)]
  z[, cal_month := birth_month]
  z[, treated := as.integer(group == treated_label)]
  z
}

apply_window <- function(z, pre_start = "2013-01", post_year = 2019L) {
  z[period >= pre_start &
    (birth_year < post_year |
     (birth_year == post_year & birth_month != 3L))][birth_year <= post_year]
}

mark_post <- function(z, post_year = 2019L) {
  z[, post := as.integer(birth_year == post_year & birth_month >= 4L)]
  z
}

# --------------------------------------------------------------- estimators
fit_status <- function(z, outcome, trends = TRUE, exposure = "n_valid") {
  z <- z[get(exposure) > 0]
  fml <- if (trends) {
    xpd(~ treated:post + i(group, period_index, ref = "a19"))
  } else {
    xpd(~ treated:post)
  }
  fepois(fml, data = z,
         fixef = c("region^group", "region^period", "group^cal_month"),
         offset = z[, log(get(exposure))],
         env.offset = TRUE,
         vcov = ~period,
         glm.iter = 100,
         y = z[[outcome]])
}
# fixest quirk: pass outcome/offset explicitly to keep one code path per lock rule
fit_status <- function(z, outcome, trends = TRUE, exposure = "n_valid") {
  z <- copy(z)[get(exposure) > 0]
  z[, y_out := get(outcome)]
  z[, off := log(get(exposure))]
  rhs <- if (trends) "treated:post + i(group, period_index, ref = \"a19\")" else "treated:post"
  fml <- as.formula(paste0("y_out ~ ", rhs, " | region^group + region^period + group^cal_month"))
  fepois(fml, data = z, offset = ~off, vcov = ~period)
}

extract_est <- function(m, label, n_treated_post_events = NA_real_) {
  ct <- coeftable(m)
  row <- grep("treated:post", rownames(ct))
  b <- ct[row, 1]; se <- ct[row, 2]; p <- ct[row, 4]
  data.table(
    specification = label, coef_log = b, se_log = se, p_value = p,
    rate_ratio = exp(b), pct_change = 100 * (exp(b) - 1),
    ci_lower_pct = 100 * (exp(b - 1.959964 * se) - 1),
    ci_upper_pct = 100 * (exp(b + 1.959964 * se) - 1),
    n_cells = m$nobs, n_treated_post_events = n_treated_post_events
  )
}

tost_p <- function(b, se, lo = log(0.85), hi = log(1.176)) {
  p1 <- pnorm((b - lo) / se, lower.tail = FALSE)  # H0: b <= lo
  p2 <- pnorm((b - hi) / se, lower.tail = TRUE)   # H0: b >= hi
  max(p1, p2)
}

# ------------------------------------------------- S1-S3 primary (short run)
base <- mark_post(apply_window(prep_panel(cells)))
zero_exposure <- base[n_valid == 0, .N]
log_line("primary panel | cells=", nrow(base), " | zero-exposure cells dropped=", zero_exposure)

ev_counts <- base[treated == 1 & post == 1,
                  .(married = sum(n_married), ue = sum(n_ue), union = sum(n_union),
                    valid = sum(n_valid))]
log_line("treated post events | married=", ev_counts$married, " ue=", ev_counts$ue,
         " valid=", ev_counts$valid)

m_s1 <- fit_status(base, "n_married")
m_s2 <- fit_status(base, "n_ue")
m_s3 <- fit_status(base, "n_union")
primary <- rbindlist(list(
  extract_est(m_s1, "S1_married", ev_counts$married),
  extract_est(m_s2, "S2_uniao_estavel", ev_counts$ue),
  extract_est(m_s3, "S3_any_union", ev_counts$union)
))
primary[, p_holm := p.adjust(p_value, method = "holm")]
primary[, mde80_pct := 100 * (exp(2.8 * se_log) - 1)]
primary[, tost_p := mapply(tost_p, coef_log, se_log)]

# ------------------------------------------------------------- robustness grid
rob <- list()
rob$s1_no_trend <- extract_est(fit_status(base, "n_married", trends = FALSE), "S1_no_trend")
rob$s2_no_trend <- extract_est(fit_status(base, "n_ue", trends = FALSE), "S2_no_trend")
rob$s3_no_trend <- extract_est(fit_status(base, "n_union", trends = FALSE), "S3_no_trend")
rob$s1_ctrl_1819 <- extract_est(
  fit_status(mark_post(apply_window(prep_panel(cells, control_ages = c(18L, 19L)))), "n_married"),
  "S1_controls_18_19")
rob$s1_ctrl_1619 <- extract_est(
  fit_status(mark_post(apply_window(prep_panel(cells, control_ages = 16:19))), "n_married"),
  "S1_controls_16_19")
rob$s1_treated_15 <- extract_est(
  fit_status(mark_post(apply_window(prep_panel(cells, treated_ages = 15L))), "n_married"),
  "S1_treated_age15_only")
rob$s1_pre2014 <- extract_est(
  fit_status(mark_post(apply_window(prep_panel(cells), pre_start = "2014-01")), "n_married"),
  "S1_pre_window_2014")
rob$s1_pre2015 <- extract_est(
  fit_status(mark_post(apply_window(prep_panel(cells), pre_start = "2015-01")), "n_married"),
  "S1_pre_window_2015")
rob$s1_missing_denom <- extract_est(
  fit_status(base, "n_married", exposure = "n_births"), "S1b_missing_as_unmarried")
rob$s1_exact_age <- extract_est(
  fit_status(mark_post(apply_window(prep_panel(exact))), "n_married"),
  "S1_exact_age_groups")

# quarterly aggregation variant
qbase <- copy(base)
qbase[, quarter := ceiling(birth_month / 3)]
qq <- qbase[, .(n_married = sum(n_married), n_ue = sum(n_ue), n_union = sum(n_union),
                n_valid = sum(n_valid), n_births = sum(n_births),
                post = max(post), treated = max(treated)),
            by = .(birth_year, quarter, region, group)]
qq <- qq[!(birth_year == 2019L & quarter == 1L)]  # mixed quarter, mirror registry
qq[, period_index := (birth_year - 2013L) * 4L + quarter]
qq[, period := sprintf("%dQ%d", birth_year, quarter)]
qq[, cal_month := quarter]
rob$s1_quarterly <- extract_est(fit_status(qq, "n_married"), "S1_quarterly")

robustness <- rbindlist(rob, fill = TRUE)

# --------------------------------------------------------- missingness DiD
miss <- extract_est(fit_status(base, "n_unknown", exposure = "n_births"),
                    "diagnostic_unknown_status_share")

# ------------------------------------------------------------ placebo dates
placebos <- rbindlist(lapply(c(2016L, 2017L, 2018L), function(py) {  # 2015 dropped, Amendment A1
  zp <- prep_panel(cells)
  zp <- zp[period >= "2013-01" & birth_year <= py][!(birth_year == py & birth_month == 3L)]
  zp <- mark_post(zp, post_year = py)
  out <- extract_est(fit_status(zp, "n_married"), sprintf("placebo_%d", py))
  out
}))

# ----------------------------------------------- event study (per lock rules)
es_base <- copy(base)
es_base[, event_bin := fifelse(treated == 0L, "ctrl",
                fifelse(period < "2017-03", "base", period))]
es_base[, event_bin := relevel(factor(event_bin), ref = "base")]
# Own-group linear slope omitted in the saturated span (rank rule mirroring
# registry Amendments 1-2); control-age slopes retained.
es_base <- es_base[n_valid > 0]
es_base[, off := log(n_valid)]
m_es <- fepois(n_married ~ i(event_bin, ref = c("base", "ctrl")) +
                 i(group, period_index, ref = c("a19", "g_treated")) |
                 region^group + region^period + group^cal_month,
               data = es_base, offset = ~off, vcov = ~period)
es_ct <- as.data.table(coeftable(m_es), keep.rownames = "term")[grepl("event_bin", term)]
es_ct[, period := gsub(".*event_bin::", "", term)]
es_ct[, `:=`(pct = 100 * (exp(Estimate) - 1),
             ci_lo = 100 * (exp(Estimate - 1.959964 * `Std. Error`) - 1),
             ci_hi = 100 * (exp(Estimate + 1.959964 * `Std. Error`) - 1))]
lead_terms <- es_ct[period < "2019-03", term]
joint_leads <- tryCatch(wald(m_es, keep = paste0("^", gsub("([:()])", "\\\\\\1", lead_terms), "$")),
                        error = function(e) NULL)
joint_leads_p <- if (!is.null(joint_leads)) joint_leads$p else {
  w <- wald(m_es, keep = "event_bin"); NA_real_
}
# fallback: joint test via linear hypothesis on all leads at once
if (is.na(joint_leads_p)) {
  V <- vcov(m_es)[lead_terms, lead_terms]
  bvec <- coef(m_es)[lead_terms]
  stat <- as.numeric(t(bvec) %*% solve(V) %*% bvec)
  joint_leads_p <- pchisq(stat, df = length(bvec), lower.tail = FALSE)
}
log_line("event study | leads=", length(lead_terms), " joint p=", round(joint_leads_p, 4))

# -------------------------------------------- Brazil aggregate HAC (NW lag 12)
bra <- cells[region == 0L]
bra[, group := fifelse(age <= 15L, "treated", fifelse(age >= 17L, "ctrl", NA_character_))]
hac_d <- bra[!is.na(group),
             .(married = sum(n_married), valid = sum(n_valid_status)),
             by = .(birth_year, birth_month, group)]
hac_w <- dcast(hac_d, birth_year + birth_month ~ group, value.var = c("married", "valid"))
hac_w <- hac_w[birth_year <= 2019L & !(birth_year == 2019L & birth_month == 3L)]
hac_w[, gap := log(married_treated / valid_treated) - log(married_ctrl / valid_ctrl)]
hac_w[, trend := (birth_year - 2013L) * 12L + birth_month]
hac_w[, post := as.integer(birth_year == 2019L & birth_month >= 4L)]
m_hac <- lm(gap ~ trend + factor(birth_month) + post, data = hac_w)
hac_ct <- coeftest(m_hac, vcov = NeweyWest(m_hac, lag = 12, prewhite = FALSE))
hac_row <- data.table(specification = "brazil_monthly_HAC_nw12",
                      coef_log = hac_ct["post", 1], se_log = hac_ct["post", 2],
                      p_value = hac_ct["post", 4],
                      rate_ratio = exp(hac_ct["post", 1]),
                      pct_change = 100 * (exp(hac_ct["post", 1]) - 1),
                      ci_lower_pct = 100 * (exp(hac_ct["post", 1] - 1.959964 * hac_ct["post", 2]) - 1),
                      ci_upper_pct = 100 * (exp(hac_ct["post", 1] + 1.959964 * hac_ct["post", 2]) - 1),
                      n_cells = nrow(hac_w))

# ------------------------------------------------- S4 fertility-composition
den <- fread(file.path(data_dir, "QUARTERLY_DENOMINATORS_AGE_SEX.csv"))
den <- den[geography_level == "region" & sex == "female" &
           age %in% c(14L, 15L, 17L, 18L, 19L)]
stopifnot(nrow(den) > 0)
den[, region := as.integer(geography_value)]

qb <- cells[region >= 1L & age %in% c(14L, 15L, 17L, 18L, 19L)]
qb[, quarter := ceiling(birth_month / 3)]
qb <- qb[, .(births = sum(n_births)), by = .(birth_year, quarter, region, age)]
qb <- merge(qb, den[, .(region, age, year, quarter, population)],
            by.x = c("birth_year", "quarter", "region", "age"),
            by.y = c("year", "quarter", "region", "age"), all.x = TRUE)
stopifnot(qb[is.na(population), .N] == 0)

fit_s4 <- function(treated_age) {
  z <- qb[age %in% c(treated_age, 17L, 18L, 19L) & birth_year <= 2019L]
  z <- z[!(birth_year == 2019L & quarter == 1L)]
  z[, period := sprintf("%dQ%d", birth_year, quarter)]
  z[, period_index := (birth_year - 2013L) * 4L + quarter]
  z[, cal_q := quarter]
  z[, treated := as.integer(age == treated_age)]
  z[, post := as.integer(birth_year == 2019L & quarter >= 2L)]
  z[, off := log(population)]
  m <- fepois(births ~ treated:post + i(age, period_index, ref = 19) |
                region^age + region^period + age^cal_q,
              data = z, offset = ~off, vcov = ~period)
  extract_est(m, sprintf("S4_fertility_age%d", treated_age),
              z[treated == 1 & post == 1, sum(births)])
}
s4 <- rbindlist(list(fit_s4(15L), fit_s4(14L)))
s4[, p_holm := p.adjust(p_value, method = "holm")]

# ------------------------------------------------------------------- exports
fwrite(primary, file.path(table_dir, "SINASC_STATUS_PRIMARY.csv"))
fwrite(robustness, file.path(table_dir, "SINASC_STATUS_ROBUSTNESS.csv"))
fwrite(placebos, file.path(table_dir, "SINASC_PLACEBO_DATES.csv"))
fwrite(miss, file.path(table_dir, "SINASC_MISSINGNESS_DIAGNOSTIC.csv"))
fwrite(hac_row, file.path(table_dir, "SINASC_BRAZIL_HAC.csv"))
fwrite(s4, file.path(table_dir, "SINASC_FERTILITY_S4.csv"))
fwrite(es_ct[, .(period, Estimate, `Std. Error`, pct, ci_lo, ci_hi)],
       file.path(table_dir, "SINASC_STATUS_EVENT_STUDY.csv"))
fwrite(data.table(joint_leads_p = joint_leads_p, n_leads = length(lead_terms),
                  zero_exposure_cells = zero_exposure),
       file.path(table_dir, "SINASC_EVENT_STUDY_DIAGNOSTICS.csv"))

# ------------------------------------------------------------------- figures
plot_shares <- function() {
  br <- cells[region == 0L]
  br[, group := fifelse(age <= 15L, "Mothers 10–15", fifelse(age >= 17L, "Mothers 17–19", NA_character_))]
  s <- br[!is.na(group), .(married = 100 * sum(n_married) / sum(n_valid_status),
                           ue = 100 * sum(n_uniao_estavel) / sum(n_valid_status)),
          by = .(birth_year, birth_month, group)]
  s[, t := birth_year + (birth_month - 0.5) / 12]
  for (fmt in c("pdf", "png")) {
    f <- file.path(figure_dir, paste0("FIGURE_11_SINASC_STATUS_SHARES.", fmt))
    if (fmt == "pdf") pdf(f, width = 9, height = 5.5) else png(f, width = 2100, height = 1300, res = 220)
    par(mfrow = c(1, 2), mar = c(4, 4, 2.5, 1))
    for (out in c("married", "ue")) {
      ttl <- if (out == "married") "Married share at birth (%)" else "União estável share at birth (%)"
      yl <- range(s[[out]])
      plot(NA, xlim = range(s$t), ylim = yl, xlab = "Year", ylab = "%", main = ttl)
      for (g in unique(s$group)) {
        d <- s[group == g][order(t)]
        lines(d$t, d[[out]], lwd = 1.6, col = if (g == "Mothers 10–15") "firebrick" else "grey40")
      }
      abline(v = 2019 + 2.5 / 12, lty = 2)
      legend("topright", legend = unique(s$group), lwd = 1.6,
             col = c("firebrick", "grey40"), bty = "n", cex = 0.8)
    }
    dev.off()
  }
}
plot_shares()

plot_es <- function() {
  d <- es_ct[order(period)]
  d[, t := as.integer(substr(period, 1, 4)) + (as.integer(substr(period, 6, 7)) - 0.5) / 12]
  for (fmt in c("pdf", "png")) {
    f <- file.path(figure_dir, paste0("FIGURE_12_SINASC_STATUS_EVENT_STUDY.", fmt))
    if (fmt == "pdf") pdf(f, width = 9, height = 5.5) else png(f, width = 2100, height = 1300, res = 220)
    par(mar = c(4, 4, 2.5, 1))
    plot(d$t, d$pct, pch = 16, cex = 0.7, ylim = range(c(d$ci_lo, d$ci_hi)),
         xlab = "Month", ylab = "% difference vs. controls",
         main = "Married-at-birth, mothers 10–15: monthly event study")
    segments(d$t, d$ci_lo, d$t, d$ci_hi, col = "grey60")
    points(d$t, d$pct, pch = 16, cex = 0.7,
           col = fifelse(d$period >= "2019-04", "firebrick", "grey20"))
    abline(h = 0, lty = 1, col = "grey")
    abline(v = 2019 + 2.5 / 12, lty = 2)
    mtext("Period-cluster CIs; simultaneous bands not shown — diagnostic per lock", cex = 0.7)
    dev.off()
  }
}
plot_es()

log_line(sprintf("done in %.1f min", as.numeric(difftime(Sys.time(), started, units = "mins"))))
print(primary)
print(s4)
print(hac_row)
print(placebos)
print(robustness)
print(miss)
