# flux Tutorials (Canonical)

This folder is the canonical user-learning path for the `flux` ecosystem.

If a package-level docs file has overlapping narrative content, it should link here
rather than maintain a duplicate copy.

## Start Here

- See [00_start_here.md](./00_start_here.md).

## Staged sequence

- `00_start_here.md` — onboarding map and learning order
- `01_core_engine_scaffold.Rmd` — Core simulation scaffold
- `02_prepare_ttv.md` — building train/test/validation datasets from irregular tables
- `03_validation_observed_grids_and_masks.Rmd` — mask-driven observed grids
- `04_validation_event_risk_apples_to_apples.Rmd` — forecast-compatible event-risk estimands
- `05_orchestration_framework.md` — multi-bundle orchestration
- `06_ascvd_ecosystem_welcome.R` — ASCVD reference walkthrough script
- `07_ascvd_prepare_ttv.R` — ASCVD prepare/TTV walkthrough script
- `08_end_to_end_v1_path.md` — validated end-to-end v1.x path

## Maturity labels

- `draft`: useful but may change quickly
- `validated`: exercised against current v1.x behavior/tests
- `stable`: expected to change infrequently
