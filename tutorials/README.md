# flux Tutorials (Canonical)

This folder is the canonical user-learning path for the `flux` ecosystem.

If a package-level docs file has overlapping narrative content, it should link here
rather than maintain a duplicate copy.

## Start Here

Begin with **[00_start_here.md](./00_start_here.md)** — a conceptual introduction to process-explicit
simulation, entities, events, decisions, and the single-entity → multi-entity modeling spectrum.
No code; just the ideas you need before touching the tutorials below.

## Staged sequence

| # | File | Topic |
|---|---|---|
| 00 | `00_start_here.md` | Conceptual introduction — modeling approach, entities, processes, decisions, ABM, ecosystem overview |
| 01 | `01_core_engine_scaffold.md` | Core engine scaffold — schema, Entity, ModelBundle, Engine, variable blocks, cohort runs, policy layering |
| 02 | `02_prepare_ttv.md` | Data preparation — train/test/validation datasets from irregular longitudinal tables |
| 03 | `03_validation_observed_grids_and_masks.md` | Validation — mask-driven observed grids and denominators |
| 04 | `04_validation_event_risk_apples_to_apples.md` | Validation — forecast-compatible event-risk estimands |
| 05 | `05_orchestration_framework.md` | Orchestration — multi-bundle composition, eligibility gating, priority encoding |
| 06 | `06_ascvd_ecosystem_welcome.md` | ASCVD reference walkthrough — a concrete domain model exercising the ecosystem |
| 07 | `07_ascvd_prepare_ttv.md` | ASCVD data preparation — fluxPrepare applied to cardiovascular EHR data |
| 08 | `08_end_to_end_v1_path.md` | End-to-end validation path — clone to green on the full test stack |

Source authoring files are retained (`.Rmd` and `.R`) where relevant, and rendered
GitHub-viewable markdown (`.md`) is the canonical reading surface.

Legacy drafts moved to archive:
- `archive/_00_ecosystem_welcome.Rmd`
- `archive/_01_prepare_ttv.Rmd`

## Maturity labels

- `draft`: useful but may change quickly
- `validated`: exercised against current v1.x behavior/tests
- `stable`: expected to change infrequently
