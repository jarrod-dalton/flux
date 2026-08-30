# Tutorial Source Files

This folder contains the authoring sources for tutorials that are rendered into
GitHub-viewable Markdown (`.md`) files in the parent `tutorials/` directory.

| Source | Renders to |
|---|---|
| `01_core_engine_scaffold.Rmd` | `../01_core_engine_scaffold.md` |
| `02_cohort_forecast.Rmd` | `../02_cohort_forecast.md` |
| `03_decisions_policy.Rmd` | `../03_decisions_policy.md` |
| `04_data_preparation_and_model_training.Rmd` | `../04_data_preparation_and_model_training.md` |
| `05_validation.Rmd` | `../05_validation.md` |

To regenerate all rendered tutorials:

```bash
cd <repo-root>
Rscript tutorials/render_for_github.R
```

Tutorial `00_start_here.md` is hand-authored Markdown with no source counterpart.
