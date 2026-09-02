# Gate B — audit and feasibility complete

Completed: 2026-09-02T03:15:51-0300

- Inputs: 48 official PNADC quarterly files (2013T1–2024T4), 11 annual first-visit files, official SIDRA Registry cells (2013–2024), official dictionaries and legal/IBGE documentation.
- Registry validation: local complete-table cells and annual totals match official SIDRA; monthly sums match annual cells.
- PNADC validation: 24,704,364 source persons and 2,432,627 adolescents; valid V1028 weights, 27 UFs per quarter, no duplicate person keys within dwelling-period.
- Geography: region for quarterly formal-marriage incidence; Brazil for primary union prevalence; UF retained for annual and diagnostics only.
- Design: quarterly age-based DiD/event study, not RD; registration timing, not occurrence timing.
- Tests: all rows in `GATE_B_ACCEPTANCE_TESTS.csv` pass.
- Resources at completion: 20.3 GiB RAM available, 272.5 GiB disk free; maximum four workers.
- Remaining blockers are enumerated in `BLOCKERS.md`; none prevents the primary quarterly age-based design.
- No treatment effect was estimated before the specification lock.

