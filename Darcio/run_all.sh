#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

run_step() {
  local script="$1"
  echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] ${script}"
  Rscript "Darcio/src/${script}"
}

run_step "00_check_dependencies.R"
run_step "00_inspect_documentation.R"
run_step "00_inventory.R"
run_step "01_audit_sources.R"
run_step "01_acquire_pnadc.R"
run_step "02_build_pnadc.R"
run_step "03_build_denominators.R"
run_step "03b_build_total_population.R"
run_step "04_acquire_registry_sidra.R"
run_step "05_build_registry.R"
run_step "07_acquire_pnadc_quarterly.R"
run_step "08_build_pnadc_quarterly.R"
run_step "09_build_quarterly_cells.R"
run_step "06_finalize_audit.R"
run_step "10_finalize_gate_b.R"
run_step "11_validate_specification_lock.R"
run_step "12_build_analysis_panels.R"
run_step "13_analyze_registry.R"
run_step "14_analyze_delay_exposure.R"
run_step "15_analyze_pnadc_cells.R"
run_step "16_analyze_pnadc_microdata.R"
run_step "17_analyze_registry_monthly.R"
run_step "18_diagnostics_power.R"
run_step "21_build_sinasc.R"
run_step "22_analyze_sinasc.R"
run_step "23_export_sinasc_tables.R"
run_step "24_analyze_registry_trend_sensitivity.R"
run_step "19_export_results.R"
run_step "20_write_reports.R"

Rscript Darcio/tests/run_tests.R
echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] replication_complete"
