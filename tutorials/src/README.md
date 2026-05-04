# Tutorial Source Files

This folder contains the authoring sources for tutorials that are rendered into
GitHub-viewable Markdown (`.md`) files in the parent `tutorials/` directory.

| Source | Renders to |
|---|---|
| `01_core_engine_scaffold.Rmd` | `../01_core_engine_scaffold.md` |
| `03_validation_observed_grids_and_masks.Rmd` | `../03_validation_observed_grids_and_masks.md` |
| `04_validation_event_risk_apples_to_apples.Rmd` | `../04_validation_event_risk_apples_to_apples.md` |
| `06_ascvd_ecosystem_welcome.R` | `../06_ascvd_ecosystem_welcome.md` |
| `07_ascvd_prepare_ttv.R` | `../07_ascvd_prepare_ttv.md` |

To regenerate all rendered tutorials:

```bash
cd <repo-root>
Rscript tutorials/render_for_github.R
```

Files `02_prepare_ttv.md`, `05_orchestration_framework.md`, and
`08_end_to_end_v1_path.md` are hand-authored Markdown with no source counterpart.
