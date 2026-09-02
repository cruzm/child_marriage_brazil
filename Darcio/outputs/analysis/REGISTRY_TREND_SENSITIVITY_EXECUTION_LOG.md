# Registry trend sensitivity — execution log

## Attempt 1 — rejected before acceptance

- Timestamp recorded: 2026-09-02T13:46:57-03:00.
- Protocol hashes: unchanged from
  `REGISTRY_TREND_SENSITIVITY_LOCK_SHA256.txt`.
- Failure: the implementation used data.table's `.N` symbol while constructing a
  standalone `data.table()`. Outside grouped evaluation, this produced zero-row model
  records. The script stopped when `ggplot2` received an empty faceting variable.
- Information seen: only empty-object warnings and the error trace; no model coefficient,
  target effect, interval, rank, calibration tier, or ensemble weight was printed or
  inspected.
- Invalid partial CSVs written before the stop are not accepted outputs and will be
  overwritten by the corrected run.
- Correction before rerun: replace the three out-of-context `.N` subscripts with explicit
  `nrow()` indices and add row-count guards. No model, window, threshold, bootstrap rule,
  seed, or reporting rule changes.


## Parallel draft implementation — discarded

- A second, independently written implementation (`src/24_trend_sensitivity_registry.R`,
  draft scoring rules differing from the frozen lock: five common origins 2016Q4–2017Q4,
  MSFE selection, 1.25×min admissibility, 999 draws) ran once at ~13:40–13:43, after the
  lock freeze (13:38:30) and before the canonical run. Its qualitative conclusion was
  identical (global_linear selected, +2.0% [−18.3; +25.8]; no candidate admissible).
- Its outputs and the duplicate script were removed from the repository; the canonical
  implementation is `src/24_analyze_registry_trend_sensitivity.R`, which alone matches
  the frozen lock's scoring, calibration tiers, and required outputs.
