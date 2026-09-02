# Gate C — specification lock complete

Validated: 2026-09-02T03:15:52-0300

- Frozen at: 2026-09-02T00:56:08-03:00
- Human-readable specification SHA-256: `537fe0474cc1cd69a99251ddbc08c222b14f9685e9edf198ebce88e623b07449`
- Machine-readable YAML SHA-256: `17f690311168b0953779e533f8a3a5b7ebf79e502237e0a4bbde3b8d07c465c2`
- Acceptance tests: 12/12 passed.
- Primary estimand: civil-registration incidence at age 15 per 100,000 age-15 residents, both sexes combined.
- Primary window: 2013T1–2018T4 versus 2019T2–T4; 2019T1 omitted.
- Primary model: region-level age-based PPML DiD with population offset, age-specific seasonality and trends.
- Primary inference: clustering by quarter-period, triangulated with HAC, temporal block bootstrap, two-way clustering, and placebos.
- Any amendment must be documented before re-estimation in `SPECIFICATION_AMENDMENTS.md`.

