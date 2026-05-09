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
| 00 | `00_start_here.md` | Conceptual introduction — modeling approach, entities, processes, decisions, ecosystem overview |
| 01 | `01_core_engine_scaffold.md` | Core engine scaffold — schema, Entity, ModelBundle, Engine, variable blocks, single-entity runs |
| 02 | `02_cohort_forecast.md` | Cohort forecasting — running many independent entities, aggregating distributions |
| 03 | `03_decisions_policy.md` | Decision points and policy — DecisionPoint, action handlers, policy functions, trajectory records, counterfactual comparison |
| 04 | `04_data_preparation_and_model_training.md` | Data preparation and model training — synthetic logs, TTV splits, weather covariates, survival + regression models |
| 05 | `05_validation.md` | Validation — observed grids, masks, forecast-vs-observed comparison with fluxValidation |

Source `.Rmd` files live in `tutorials/src/`; rendered GitHub-viewable `.md`
files in this directory are the canonical reading surface.

Legacy drafts moved to archive:
- `archive/_00_ecosystem_welcome.Rmd`
- `archive/_01_prepare_ttv.Rmd`

## Maturity labels

- `draft`: useful but may change quickly
- `validated`: exercised against current v2.x behavior/tests
- `stable`: expected to change infrequently
