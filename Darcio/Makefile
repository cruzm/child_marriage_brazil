.PHONY: all test reports sinasc-daily-lock sinasc-daily-g0 sinasc-daily-g0-check sinasc-daily-g1 sinasc-daily-g1-check sinasc-daily-g2 sinasc-daily-g2-check sinasc-daily-g3 sinasc-daily-g3-check sinasc-daily-paper-table registry-sar-r0-lock registry-sar-r0 registry-sar-r0-check

all:
	./Darcio/run_all.sh

test:
	Rscript Darcio/tests/run_tests.R

reports:
	Rscript Darcio/src/19_export_results.R
	Rscript Darcio/src/20_write_reports.R

sinasc-daily-lock:
	Rscript Darcio/src/26_validate_sinasc_daily_lock.R

# Runs only the frozen SINASC daily data gate. No effect is estimated.
sinasc-daily-g0:
	Rscript Darcio/src/26_validate_sinasc_daily_lock.R
	Rscript Darcio/src/27_sinasc_daily_gate_g0.R
	Rscript Darcio/src/28_validate_sinasc_daily_gate_g0.R

sinasc-daily-g0-check:
	Rscript Darcio/src/28_validate_sinasc_daily_gate_g0.R

# Runs only G1 after read-only lock/G0 checks. It does not run G2/G3 or estimate
# the married-status outcome.
sinasc-daily-g1:
	Rscript Darcio/src/26_validate_sinasc_daily_lock.R
	Rscript Darcio/src/28_validate_sinasc_daily_gate_g0.R
	Rscript Darcio/src/29_sinasc_daily_gate_g1.R
	Rscript Darcio/src/30_validate_sinasc_daily_gate_g1.R

sinasc-daily-g1-check:
	Rscript Darcio/src/30_validate_sinasc_daily_gate_g1.R

# Runs only G2 after read-only checks of the lock, G0, and G1. It estimates the
# frozen placebo/stability diagnostics, never the full primary G3 model.
sinasc-daily-g2:
	Rscript Darcio/src/26_validate_sinasc_daily_lock.R
	Rscript Darcio/src/28_validate_sinasc_daily_gate_g0.R
	Rscript Darcio/src/30_validate_sinasc_daily_gate_g1.R
	Rscript Darcio/src/31_sinasc_daily_gate_g2.R
	Rscript Darcio/src/32_validate_sinasc_daily_gate_g2.R

sinasc-daily-g2-check:
	Rscript Darcio/src/32_validate_sinasc_daily_gate_g2.R

# Runs the complete frozen G3 analysis after read-only checks of every prior
# gate. G2=QUALIFIED remains binding and cannot be overwritten by G3.
sinasc-daily-g3:
	Rscript Darcio/src/26_validate_sinasc_daily_lock.R
	Rscript Darcio/src/28_validate_sinasc_daily_gate_g0.R
	Rscript Darcio/src/30_validate_sinasc_daily_gate_g1.R
	Rscript Darcio/src/32_validate_sinasc_daily_gate_g2.R
	Rscript Darcio/src/33_sinasc_daily_gate_g3.R
	Rscript Darcio/src/34_validate_sinasc_daily_gate_g3.R
	Rscript Darcio/src/39_export_sinasc_daily_paper.R

sinasc-daily-g3-check:
	Rscript Darcio/src/34_validate_sinasc_daily_gate_g3.R

# Exports the manuscript table only from validated, observed SINASC outputs.
# It never reads the Registry/SAR synthetic software-test artifacts.
sinasc-daily-paper-table:
	Rscript Darcio/src/34_validate_sinasc_daily_gate_g3.R
	Rscript Darcio/src/39_export_sinasc_daily_paper.R

# Completes only the local Registry/SAR readiness package. It audits public
# planning inputs, exports an aggregate denominator, screens power, and runs a
# synthetic recovery test. It neither sends a request nor estimates a policy
# effect from restricted data.
registry-sar-r0-lock:
	Rscript Darcio/src/35_validate_registry_sar_r0_lock.R

registry-sar-r0:
	Rscript Darcio/src/35_validate_registry_sar_r0_lock.R
	Rscript Darcio/src/36_registry_sar_r0_local.R
	Rscript Darcio/src/37_registry_sar_r0_synthetic.R
	Rscript Darcio/src/38_validate_registry_sar_r0.R

registry-sar-r0-check:
	Rscript Darcio/src/35_validate_registry_sar_r0_lock.R
	Rscript Darcio/src/38_validate_registry_sar_r0.R
