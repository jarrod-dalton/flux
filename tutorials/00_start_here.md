# Start Here

Maturity: stable

This is the recommended learning order for new flux users.

1. Core mental model
- Read `01_core_engine_scaffold.Rmd`
- Goal: understand `Entity`, `Engine`, and `ModelBundle`.

2. Data preparation for model training
- Read `02_prepare_ttv.md`
- Goal: construct train/test/validation datasets with explicit time semantics.

3. Validation semantics
- Read `03_validation_observed_grids_and_masks.Rmd`
- Read `04_validation_event_risk_apples_to_apples.Rmd`
- Goal: compare observed vs predicted quantities using matching estimands.

4. Multi-model orchestration
- Read `05_orchestration_framework.md`
- Goal: understand eligibility gating, tie-breaking, and orchestration policy hooks.

5. Reference package walkthrough
- Review `06_ascvd_ecosystem_welcome.R` and `07_ascvd_prepare_ttv.R`
- Goal: inspect a concrete domain package using ecosystem contracts.

6. Validated integrated path
- Run `08_end_to_end_v1_path.md`
- Goal: execute a known-good v1.x path end-to-end.
