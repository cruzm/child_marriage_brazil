# Child Marriage in Brazil

Research project evaluating the causal effects of Lei 13.811/2019 — the 2019
reform that eliminated all exceptions to the minimum marriage age of 16 in
Brazil. The paper decomposes the reform's effect on formal vs. informal child
marriage into legal, economic (Bolsa Família), and normative mechanisms.

1. **Structural DCDP model** (discrete-choice dynamic programming) estimated
   on PNADC — recovers mechanism shares.
2. **Causal identification of the reform** — DiD event study on Registro
   Civil, McCrary bunching test, and age-based DiD on the PNADC informal
   margin.

Data sources: PNADC (2012–present), Registro Civil/SIDRA (2003–2024), Census
2010/2022, SINASC, SINAN, CadÚnico (restricted). Funded by the Becker
Friedman Institute (BFI); working paper targeted for late 2026.

## Repository structure

```
child_marriage_brazil/
├── code/                     # main pipeline (see below)
│   ├── structural-model/     # DCDP model track
│   └── old/                  # archived pipelines from prior contributors
├── data/
│   ├── raw/                  # SIDRA/PNADC download cache
│   ├── processed/            # analysis-ready panels
│   ├── cache/                # intermediate .rds caches (safe to delete/rebuild)
│   ├── old/                  # superseded data snapshots
│   └── child_marriage.duckdb # rc_raw, rc_panel, pnadc_raw, dc_pnadc_dcm tables
├── literature/                # PDFs of cited papers
├── notes/                     # data dictionaries, literature notes
├── output/figures/            # exported plots
└── presentation/              # Beamer slides
```

### `code/` — main pipeline (Yasmin Martins)

Numbered R scripts, run in order, driven by `00_setup.R` (paths, packages,
helpers) via `source(here::here("00_setup.R"))`. This is the project's
primary, actively maintained pipeline.

| Script | Purpose |
|---|---|
| `00_setup.R` | Global config: packages, paths (`RC_DIR`, `OUT_DIR`, `CACHE_DIR`), helper functions |
| `01_importacao.R` | Imports raw Registro Civil (xlsx) and PNADC (API) data |
| `02_preparacao.R` | Data cleaning / variable construction |
| `03_analises_RC.R` | Descriptive Registro Civil analysis |
| `04_analises_PNADC.R` | Descriptive PNADC analysis, incl. RC × PNADC sub-registration comparison |
| `05_analises_mercado.R` | Labor market outcomes |
| `06_analises_educacao.R` | Education module outcomes |
| `07_exportar.R` | Exports processed tables/figures |
| `08_didc.R` | Difference-in-differences-in-changes (DiDC) estimation |
| `09_figuras_paper.R` | Final paper-ready figures |
| `10_inf_causal.R` / `.Rmd` / `.html` | Causal inference: event study, bunching, DiD (script, source, and knitted report) |
| `Pesquisa_Casamento_infantil.Rproj` | RStudio project file for this pipeline |

Open this project via the repository root (not by double-clicking the
`.Rproj` directly) so that `here::here()` calls in `00_setup.R` resolve
`data/raw`, `data/cache`, etc. to the repo-level `data/` folder.
`RC_DIR` in `00_setup.R` still points at an external `PIBIC/...` folder with
the raw Registro Civil `.xlsx` files, which is not part of this repository
and must be provided locally.

### `code/structural-model/` — DCDP structural model track

A separate, still-active track authored by Maria Cruz that downloads its own
data via API/DuckDB rather than reading Yasmin's imported files.

| Script | Purpose |
|---|---|
| `01_download_rc.R` | Downloads Registro Civil marriage counts from IBGE SIDRA (table 4406) → `rc_raw` in DuckDB |
| `02_download_pnadc.R` | Downloads PNADC (girls 10–17) via `PNADcIBGE` → `pnadc_raw` / `dc_pnadc_dcm` in DuckDB |
| `03_analysis_rc.R` | Descriptive RC analysis from DuckDB `rc_panel` |
| `04_analysis_pnadc.R` | Descriptive PNADC analysis from DuckDB `dc_pnadc_dcm` |
| `model.R` | Two-stage DCDP model: Stage 1 DiD on Registro Civil for `phi^F`; Stage 2 MLE on PNADC for `theta = (alpha0, alpha1, kappa, mu, gamma0, gamma1, beta0, beta1, sigma)`. Reads `data/processed/dc_rc_dcm.rds` and `data/processed/dc_pnadc_dcm.rds`. |

### `code/old/` — archived pipelines (not maintained)

- `2022_2025_felipe/` — original 8-script pipeline (00–07) by a prior
  contributor (Felipe).
- `2026_yasmin/` — earlier iteration of Yasmin's pipeline (00–10), superseded
  by the scripts now at `code/` root; kept for reference (e.g. its
  `10_prep_discrete_choice.R` documents how `dc_rc_dcm`/`dc_pnadc_dcm` were
  first constructed).
- `v50c02.R` — standalone scratch script (choice-experiment design example,
  `support.CEs` package), unrelated to the main pipeline.

## `data/`

- `child_marriage.duckdb` — single DuckDB file with tables `rc_raw`,
  `rc_panel`, `pnadc_raw`, `dc_pnadc_dcm` (written by
  `code/structural-model/01_download_rc.R` and `02_download_pnadc.R`).
- `raw/` — cached SIDRA downloads, `rc_sidra_<year>.rds` (2013–2024, one file
  per year), used by the structural-model download scripts.
- `processed/` — analysis-ready panels: `dc_rc_dcm.rds` (Registro Civil,
  UF × year × bride age-group cells) and `dc_pnadc_dcm.rds` (PNADC individual
  panel, girls 10–17, `choice` = in_union/wait). Consumed by
  `code/structural-model/model.R`.
- `cache/` — intermediate caches used by the `code/` pipeline to avoid
  re-downloading/re-processing: `rc_raw_cache.rds` (from `01_importacao.R`)
  and `didc_pnadc_cache.rds` (from `08_didc.R`). Safe to delete and rebuild
  by re-running the corresponding script.
- `old/` — superseded data snapshots from prior contributors
  (`2025_felipe/`, `2026_yasmin/`).

## `literature/`

PDFs of cited papers, split into `brazil/` (11), `global/` (30), and
`reports/` (5, incl. BFI project description and child-marriage briefs).

## `notes/`

- `data dictionary/` — variable dictionaries for PNADC, PNS, and Registro
  Civil microdata.
- `literature notes/` — literature review drafts, summaries, and a
  `references.bib` bibliography.
- `data_structure.xlsx` — overview of dataset structures.

## `output/figures/`

Exported plots (`.png`): motivation figures (`plot1`–`plot5`, law/CDF
pre/post-2019), age distribution/PMF figures, and `model_mechanisms.png`.

## `presentation/`

Beamer slides (`apresentacao_casamento_infantil.tex`, with
`section_methods_results.tex` included for the structural results section)
plus exported PDFs. Note: the `.tex` files reference figures as
`../output/*.pdf`, but `output/figures/` currently only contains `.png`
files — regenerate as PDF or update the includegraphics paths before
compiling.

## Known issues

- `code/03_analises_RC.R` / `04_analises_PNADC.R` (structural-model track)
  write to `OUT_DIR <- here("outputs")`, but the actual figures directory is
  `output/figures/` (singular, with a `figures/` subfolder) — verify output
  paths before relying on a fresh run.
- No `.gitignore`; large binary data/report files are currently committed
  directly.
