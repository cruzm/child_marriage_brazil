# ============================================================
# Bootstrap standard errors — Structural DCDP
# ============================================================
# Resamples rows of pnad_m (i.i.d.), re-optimizes from the
# converged theta (warm start), and collects coefficients.
# SEs = SD of bootstrap distribution.
# Delta method converts log-scale SEs to natural scale.
#
# Runtime: ~2-4 min for B = 200 on a modern laptop.
# ============================================================

# install.packages(c("tidyverse", "fixest", "maxLik"))
library(tidyverse)
library(fixest)
library(maxLik)

# ---- 0. Run main model to get converged theta ----
# Objects after sourcing: th, free, pnad_m, draws_by_age,
# mean_delta_by_age, ll_fn, compute_EV, AGES, N_MC, PR_PREG,
# phi_F_hat, w_fn, R_fn, s_fn, lse2, DISC, A_TERMINAL
source("code/model.R")

# ---- 1. Bootstrap setup ----

B <- 200L
set.seed(123)

# Save originals before the loop overwrites globals
pnad_orig   <- pnad_m
draws_orig  <- draws_by_age
mdelta_orig <- mean_delta_by_age

# Storage: B rows x length(free) cols
boot_mat <- matrix(
  NA_real_, nrow = B, ncol = length(free),
  dimnames = list(NULL, free)
)

cat(sprintf("\nBootstrap: %d replications  (%d free parameters)\n",
            B, length(free)))
pb <- txtProgressBar(min = 0, max = B, style = 3)

# ---- 2. Bootstrap loop ----

for (b in seq_len(B)) {

  # Resample rows with replacement
  idx <- sample(nrow(pnad_orig), replace = TRUE)
  dat <- pnad_orig[idx, ]

  # Update globals that ll_fn / compute_EV read at call time
  pnad_m <- dat

  dpool_b <- dat$delta_obs[!is.na(dat$delta_obs)]
  dage_b  <- split(dpool_b, dat$a[!is.na(dat$delta_obs)])
  draws_by_age <- setNames(
    lapply(as.character(AGES), function(ac) {
      pool <- dage_b[[ac]]
      if (length(pool) < 10) pool <- dpool_b
      sample(pool, N_MC, replace = TRUE)
    }),
    as.character(AGES)
  )
  mean_delta_by_age <- sapply(draws_by_age, mean)

  # Re-optimize from converged theta (warm start speeds convergence)
  fb <- tryCatch(
    maxLik(
      logLik  = ll_fn,
      start   = th,
      method  = "BFGS",
      fixed   = "kappa",
      control = list(iterlim = 200, printLevel = 0)
    ),
    error = function(e) NULL
  )

  if (!is.null(fb) && returnCode(fb) <= 2L)
    boot_mat[b, ] <- coef(fb)[free]

  setTxtProgressBar(pb, b)
}

close(pb)

# Restore globals
pnad_m            <- pnad_orig
draws_by_age      <- draws_orig
mean_delta_by_age <- mdelta_orig

# ---- 3. Convergence summary ----

n_ok <- sum(complete.cases(boot_mat))
cat(sprintf("\nConverged: %d / %d replications (%.0f%%)\n",
            n_ok, B, 100 * n_ok / B))

# ---- 4. SEs and confidence intervals ----

boot_se <- apply(boot_mat, 2, sd,       na.rm = TRUE)
boot_ci <- apply(boot_mat, 2, quantile, probs = c(0.025, 0.975), na.rm = TRUE)

results_boot <- tibble(
  parameter = free,
  estimate  = round(th[free], 4),
  boot_se   = round(boot_se,           4),
  ci_2.5    = round(boot_ci["2.5%",  ], 4),
  ci_97.5   = round(boot_ci["97.5%", ], 4),
  t_boot    = round(th[free] / boot_se, 2)
)

cat("\n---- Bootstrap results (log-scale parameters) ----\n")
print(results_boot)

# ---- 5. Derived parameters with delta-method SEs ----
# For f = exp(x): SE(f) ≈ f_hat * SE(x)   [delta method]

mu_hat     <- exp(unname(th["log_mu"]))
gamma1_hat <- exp(unname(th["log_gamma1"]))
sigma_hat  <- exp(unname(th["log_sigma"]))

se_mu     <- mu_hat     * boot_se["log_mu"]
se_gamma1 <- gamma1_hat * boot_se["log_gamma1"]
se_sigma  <- sigma_hat  * boot_se["log_sigma"]

alpha0_hat <- unname(th["alpha0"])
alpha1_hat <- unname(th["alpha1"])
gamma0_hat <- unname(th["gamma0"])
beta0_hat  <- unname(th["beta0"])
beta1_hat  <- unname(th["beta1"])

cat("\n---- Derived parameters (back-transformed) ----\n")
cat(sprintf("%-12s  %8s  %8s\n", "parameter", "estimate", "boot se"))
cat(sprintf("%-12s  %8.3f  %8.3f\n", "w(D=8)",
            alpha0_hat + alpha1_hat * 8, boot_se["alpha0"] + boot_se["alpha1"] * 8))
cat(sprintf("%-12s  %8.3f  %8.3f\n", "mu",      mu_hat,     se_mu))
cat(sprintf("%-12s  %8.4f  %8.4f\n", "gamma1",  gamma1_hat, se_gamma1))
cat(sprintf("%-12s  %8.3f\n",        "R(a=10)", exp(gamma0_hat + gamma1_hat * 10)))
cat(sprintf("%-12s  %8.3f\n",        "R(a=17)", exp(gamma0_hat + gamma1_hat * 17)))
cat(sprintf("%-12s  %8.3f  %8.3f\n", "s(a=10)",
            beta0_hat + beta1_hat * 10, boot_se["beta0"] + boot_se["beta1"] * 10))
cat(sprintf("%-12s  %8.3f  %8.3f\n", "s(a=17)",
            beta0_hat + beta1_hat * 17, boot_se["beta0"] + boot_se["beta1"] * 17))
cat(sprintf("%-12s  %8.3f  %8.3f\n", "sigma",   sigma_hat,  se_sigma))
cat(sprintf("%-12s  %8.3f  %8s\n",   "phi^F",   phi_F_hat,  "[DiD, first stage]"))

# ---- 6. Save ----

saveRDS(boot_mat, "data/boot_coef.rds")
cat("\nSaved: data/boot_coef.rds\n")
