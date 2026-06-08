# ============================================================
# Child Marriage in Brazil — Structural DCDP Model
# ============================================================
# Model:   dynamic discrete choice (DCDP) with logit errors
# Choices: {in_union, wait}
# State:   (a, p)  where a in {10,...,17}, p in {0, 1}
#
# Stage 1 — Registro Civil aggregate panel (2003-2022):
#   phi^F via DiD on Lei 13.811/2019 reform
#   Treatment: below_16 x post_2019
#
# Stage 2 — PNAD-C individual panel (2012-2023):
#   Structural MLE for theta = (alpha0, alpha1, kappa, mu,
#                               gamma0, gamma1, beta0, beta1, sigma)
#   Functional forms:
#     w(Delta) = alpha0 + alpha1 * Delta   [wealth transfer, up in age gap]
#     R(a)     = exp(gamma0 + gamma1 * a)  [reputational risk, up in age]
#     s(a)     = beta0 + beta1 * a         [schooling return]
#
# Utilities:
#   U_union = w(Delta) + kappa + mu * R(a)
#   U_wait  = Y_i/1000 + s(a) - sigma * p + delta * EV(a+1, p')
#
# EV(a, p): backward induction from a = 17 -> 10.
#   Logit shocks give EV = E_Delta[log(exp(V_u) + exp(V_w))],
#   approximated by MC over the empirical Delta | a distribution.
# ============================================================

library(tidyverse)
library(fixest)
library(maxLik)

# ---- 0. Constants ----

AGES       <- 10L:17L
A_TERMINAL <- 18L
DISC       <- 0.95     # delta: discount factor (calibrated)
N_MC       <- 300L     # Monte Carlo draws per age for EV integration
set.seed(42)

# Pr(p' = 1 | p = 0, a): pregnancy transition by age.
# Calibrated from SINASC teenage birth hazards (single year of age).
PR_PREG <- c(
  `10` = 0.005, `11` = 0.010, `12` = 0.020, `13` = 0.035,
  `14` = 0.060, `15` = 0.095, `16` = 0.140, `17` = 0.180
)

# ---- 1. Load data ----

rc   <- readRDS("data/dc_rc_dcm.rds")
pnad <- readRDS("data/dc_pnadc_dcm.rds")

# ---- 2. Stage 1: phi^F via DiD (Registro Civil) ----
# Lei 13.811/2019 closed the pregnancy exception for formal marriages
# of girls under 16. Treatment cell: below_16 == 1 AND pos_lei2019 == 1.
# Outcome: log count of formal marriages per (year, UF, age-group) cell.

rc_est <- rc |>
  filter(is_minor_w, !is.na(below_16)) |>
  mutate(log_n = log(n_total_row + 1))

did_phi_F <- feols(
  log_n ~ i(pos_lei2019, below_16, ref = 0) | uf + idade_m + ano,
  data    = rc_est,
  cluster = ~uf
)

# Sign-flip: treatment reduced marriages -> phi^F is positive deterrence
phi_F_hat <- -coef(did_phi_F)["pos_lei2019::1:below_16"]
phi_F_se  <-  se(did_phi_F)["pos_lei2019::1:below_16"]
cat(sprintf("phi^F (DiD, first stage): %.4f  [se = %.4f]\n",
            phi_F_hat, phi_F_se))

# ---- 3. Stage 2 data preparation (PNAD-C) ----
# Keep all girls aged 10-17, including the wait group (NA delta).
# Delta is observed only for in_union girls (accepted offer).

pnad_m <- pnad |>
  filter(a %in% AGES) |>
  mutate(
    y         = as.integer(choice == "in_union"),
    p         = as.integer(matern_bin > 0),
    Y         = pmax(ifelse(is.na(rend),
                            median(rend, na.rm = TRUE), rend), 1) / 1000,
    wt        = pes_comcalib / mean(pes_comcalib, na.rm = TRUE),
    a         = as.integer(a),
    delta_obs = ifelse(choice == "in_union", delta, NA_real_)
  )

cat(sprintf("PNAD-C sample: %d obs  (%d in_union, %d wait)\n",
            nrow(pnad_m), sum(pnad_m$y), sum(1 - pnad_m$y)))

# Empirical Delta | a from accepted offers (in_union only).
# Used for (i) MC draws in EV backward induction,
# (ii) counterfactual offer for wait-group likelihood.
delta_pool    <- pnad_m$delta_obs[!is.na(pnad_m$delta_obs)]
delta_by_age  <- split(delta_pool, pnad_m$a[!is.na(pnad_m$delta_obs)])

draws_by_age <- setNames(
  lapply(as.character(AGES), function(a_chr) {
    pool <- delta_by_age[[a_chr]]
    if (length(pool) < 10) pool <- delta_pool
    sample(pool, N_MC, replace = TRUE)
  }),
  as.character(AGES)
)

mean_delta_by_age <- sapply(draws_by_age, mean)

# ---- 4. Functional forms ----

w_fn  <- function(delta, a0, a1) a0 + a1 * delta
R_fn  <- function(a, g0, g1)    exp(g0 + g1 * a)
s_fn  <- function(a, b0, b1)    b0 + b1 * a

# Numerically stable log(exp(x) + exp(y))
lse2 <- function(x, y) {
  m <- pmax(x, y)
  m + log(exp(x - m) + exp(y - m))
}

# ---- 5. Backward induction: EV(a, p) ----
# EV[a, p] = E_Epsilon[max(U_union + eps_u, U_wait + eps_w)]
# Logit shocks -> EV = E_Delta[log(exp(V_u) + exp(V_w))]
# Mean household income used in EV (integrates out Y heterogeneity).

compute_EV <- function(theta) {
  a0 <- theta["alpha0"]; a1 <- theta["alpha1"]
  kp <- theta["kappa"];  mu <- exp(theta["log_mu"])
  g0 <- theta["gamma0"]; g1 <- exp(theta["log_gamma1"])
  b0 <- theta["beta0"];  b1 <- theta["beta1"]
  sg <- exp(theta["log_sigma"])

  mean_Y <- mean(pnad_m$Y, na.rm = TRUE)

  EV <- matrix(0, nrow = length(AGES) + 1L, ncol = 2L,
               dimnames = list(c(AGES, A_TERMINAL), c("0", "1")))

  for (a in rev(AGES)) {
    R_a  <- R_fn(a, g0, g1)
    s_a  <- s_fn(a, b0, b1)
    pr   <- PR_PREG[[as.character(a)]]
    a_n  <- as.character(a + 1L)
    D_mc <- draws_by_age[[as.character(a)]]

    for (p in 0:1) {
      ev_next <- if (p == 0L)
        pr * EV[a_n, "1"] + (1 - pr) * EV[a_n, "0"]
      else
        EV[a_n, "1"]

      V_u <- w_fn(D_mc, a0, a1) + kp + mu * R_a
      V_w <- mean_Y + s_a - sg * p + DISC * ev_next

      EV[as.character(a), as.character(p)] <- mean(lse2(V_u, V_w))
    }
  }
  EV
}

# ---- 6. Log-likelihood ----
# in_union obs: Delta observed  -> use individual Delta_i
# wait obs:     Delta unobserved -> use age-specific mean accepted offer

ll_fn <- function(theta) {
  a0 <- theta["alpha0"]; a1 <- theta["alpha1"]
  kp <- theta["kappa"];  mu <- exp(theta["log_mu"])
  g0 <- theta["gamma0"]; g1 <- exp(theta["log_gamma1"])
  b0 <- theta["beta0"];  b1 <- theta["beta1"]
  sg <- exp(theta["log_sigma"])

  N   <- nrow(pnad_m)
  EV  <- tryCatch(compute_EV(theta), error = function(e) NULL)
  if (is.null(EV)) return(-1e10)

  a_i <- pnad_m$a
  p_i <- pnad_m$p
  Y_i <- pnad_m$Y
  y_i <- pnad_m$y
  wt  <- pnad_m$wt

  D_i <- ifelse(y_i == 1L,
                pnad_m$delta_obs,
                mean_delta_by_age[as.character(a_i)])

  # EV next period
  a_n   <- pmin(a_i + 1L, A_TERMINAL)
  pr    <- unname(PR_PREG[as.character(a_i)])
  ev_p0 <- EV[cbind(as.character(a_n), rep("0", N))]
  ev_p1 <- EV[cbind(as.character(a_n), rep("1", N))]
  ev_nx <- ifelse(p_i == 0L,
                  pr * ev_p1 + (1 - pr) * ev_p0,
                  ev_p1)

  V_u   <- w_fn(D_i, a0, a1) + kp + mu * R_fn(a_i, g0, g1)
  V_w   <- Y_i + s_fn(a_i, b0, b1) - sg * p_i + DISC * ev_nx

  p_hat <- plogis(V_u - V_w)
  ll    <- y_i * log(p_hat + 1e-12) + (1L - y_i) * log(1 - p_hat + 1e-12)

  # BFGS uses scalar LL; SEs come from the numerical Hessian
  sum(wt * ll, na.rm = TRUE)
}

# ---- 7. Estimation ----

# kappa is absorbed into alpha0 to resolve collinearity:
# both are additive intercepts in V_union = w(Delta) + kappa + mu*R(a).
# Fix kappa = 0; interpret alpha0 as the combined union-entry intercept.

theta_init <- c(
  alpha0     =  0.00,   # V_union intercept [absorbs kappa]
  alpha1     =  0.05,   # w(Delta) slope on age gap
  kappa      =  0.00,   # fixed at 0 (collinear with alpha0; see above)
  log_mu     =  0.00,   # log(mu > 0): weight on reputational risk R(a)
  gamma0     = -2.00,   # log R(a) intercept
  log_gamma1 = -2.00,   # log(gamma1 > 0): R(a) slope in age
  beta0      =  1.00,   # s(a) intercept
  beta1      = -0.05,   # s(a) slope in age
  log_sigma  =  0.00    # log(sigma > 0): cost of pregnancy while waiting
)

fit <- maxLik(
  logLik  = ll_fn,
  start   = theta_init,
  method  = "BFGS",
  fixed   = "kappa",           # kappa collinear with alpha0; fix at 0
  control = list(iterlim = 500, printLevel = 1)
)

# ---- 8. Results ----

summary(fit)

th   <- coef(fit)
free <- names(th)[th != 0 | names(th) != "kappa"]   # exclude fixed kappa

# BFGS's quasi-Newton Hessian can be ill-conditioned; recompute numerically
ll_free <- function(par) {
  full_par        <- th
  full_par[free]  <- par
  ll_fn(full_par)
}
H_num <- tryCatch(
  optimHess(th[free], ll_free),
  error = function(e) NULL
)
se_num <- if (!is.null(H_num)) {
  tryCatch(sqrt(diag(solve(-H_num))), error = function(e) rep(NA_real_, length(free)))
} else {
  rep(NA_real_, length(free))
}

se                <- rep(NA_real_, length(th))
names(se)         <- names(th)
se[free]          <- se_num
se[is.nan(se)]    <- NA_real_

# Back-transform log-scale parameters for reporting (unname avoids "log_mu.log_mu" etc.)
alpha0 <- unname(th["alpha0"])
alpha1 <- unname(th["alpha1"])
mu     <- exp(unname(th["log_mu"]))
gamma0 <- unname(th["gamma0"])
gamma1 <- exp(unname(th["log_gamma1"]))
beta0  <- unname(th["beta0"])
beta1  <- unname(th["beta1"])
sigma  <- exp(unname(th["log_sigma"]))

results <- tibble(
  parameter = names(th),
  estimate  = round(th, 4),
  std_error = round(se, 4),
  t_stat    = round(th / se, 2)
)
print(results)

cat("\n---- Derived parameters (back-transformed) ----\n")
cat(sprintf("w(Delta = 8)  = %.3f   [avg age gap ~ 8 yrs]\n",  alpha0 + alpha1 * 8))
cat(sprintf("mu            = %.3f   [exp(log_mu)]\n",           mu))
cat(sprintf("gamma1        = %.4f  [exp(log_gamma1)]\n",        gamma1))
cat(sprintf("R(a = 10)     = %.3f\n", exp(gamma0 + gamma1 * 10)))
cat(sprintf("R(a = 17)     = %.3f\n", exp(gamma0 + gamma1 * 17)))
cat(sprintf("s(a = 10)     = %.3f\n", beta0 + beta1 * 10))
cat(sprintf("s(a = 17)     = %.3f\n", beta0 + beta1 * 17))
cat(sprintf("sigma         = %.4f  [exp(log_sigma)]\n",         sigma))
cat(sprintf("phi^F         = %.3f   [DiD first stage]\n",       phi_F_hat))
