# Registry/SAR exact-date redesign — R0 local readiness

**R0 status: `LOCAL_READY_EXTERNAL_PENDING`.**
**Causal-identification status: `NOT_EVALUATED`.**
**External request: `READY_NOT_SENT`.**

Generated: 2026-09-04T16:09:29-0300

R0 completes the work that can be done without restricted RC.2 files. It
does not estimate a reform effect. Public Registry counts screen power only;
the synthetic coefficient tests software only.

## Public count and power screen

For combined sexes, the public registration-age cells contain 3,394 age-15 and 94,107 age-16 person-events in 2013-2018, versus 928 and 39,543 in 2019-2024.
The frozen base screen gives an 80%-power decline MDE of 19.09% at 90 days (threshold 20%). The stress screen gives 25.88% at 180 days (threshold 30%). Both pass provisionally.
These are not exact-window counts: the public source records completed age
and year at registration rather than exact age and date at celebration.

## Denominator package

The selected national quarterly PNADC exposure contains 288 cells for ages 15/16 and combined/female/male populations. For the combined primary population, maximum CV is 2.354% and the largest annual-versus-quarterly difference is 3.444%.
The exported file converts each population stock into approximate exact-age-
day stocks and quarterly person-time. This smooth allocation is explicit;
survey uncertainty must remain in the restricted analysis.

## Synthetic pipeline

The PPML dry run used 51,623 synthetic cells and 125,416 simulated events. It recovered a true log IRR of -0.5108 as -0.4911 (95% CI [-0.5849, -0.3973]). Recovery passes the frozen tolerance.
Every synthetic row is marked `synthetic=TRUE`; this output is barred from
substantive tables and figures.

## Binding external items

IBGE must confirm annual field retention, SEADE coverage, edit/imputation
flags, an internal deduplication key, import of the aggregate exposure, and
disclosure-reviewed exports. Researcher identity, institutional signatory,
and explicit sending authorization remain pending outside version control.
After access, date validity (>=99%), residence validity (>=95%), public-total
reconciliation, exact-window power, counterfactual placebos, and final
inference must pass before any causal-core decision.

## Decision

The local package is ready for external transmission. The paper's causal
score does not change at R0 because no new identifying evidence has been
observed. SINASC remains complementary and inconclusive.

## Main artifacts

- `config/registry_sar_r0_lock.yml`
- `paper/ledgers/REGISTRY_SAR_R0_PROTOCOL.md`
- `paper/ledgers/IBGE_SAR_TECHNICAL_INQUIRY_READY.md`
- `outputs/tables/REGISTRY_SAR_R0_POWER_ENVELOPE.csv`
- `outputs/data/REGISTRY_SAR_R0_PNADC_EXPOSURE.csv`
- `outputs/tables/REGISTRY_SAR_R0_SYNTHETIC_RECOVERY.csv`
- `outputs/audit/REGISTRY_SAR_R0_GATE_STATUS.csv`
