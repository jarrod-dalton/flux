# tests_ecosystem

Cross-package ecosystem tests for the flux stack.

This harness is intentionally outside package-level `tests/testthat` to verify
integration behavior across repos in realistic install/load orders.

## Tiered strategy

1. Tier 1 (`run_tier1_smoke.R`): fast smoke checks
- Confirms package loads and a minimal end-to-end path across Core + Prepare + Forecast + Validation.
- Intended to run frequently (every release candidate, and often during refactors).

2. Tier 2 (`run_tier2_package_tests.R`): package test battery
- Runs each package's native unit tests in sequence.
- Emits `devtools::test()`-style summaries (`FAIL/WARN/SKIP/PASS`) per package.
- Useful before coordinated version bumps/releases.

3. Tier 3 (`run_tier3_ascvd_demo.R`): realistic model-driven integration
- Leverages fluxASCVD example data and prep workflow as a higher-fidelity
  ecosystem scenario.
- Intended for release gating and regression detection.

## Running

From `/Users/daltonj/patientSim`:

```bash
Rscript tests_ecosystem/run_tier1_smoke.R
Rscript tests_ecosystem/run_tier2_package_tests.R
Rscript tests_ecosystem/run_tier3_ascvd_demo.R
Rscript tests_ecosystem/run_all.R
```

Or with `Makefile` targets:

```bash
make ecosystem-tier1
make ecosystem-tier2
make ecosystem-tier3
make ecosystem-all
```

Notes:
- These scripts assume local package directories are present under `subrepos/` in this parent folder.
- Tier 3 intentionally skips if `fluxASCVD` internals are unavailable.
- Each run writes logs/reports under `tests_ecosystem/reports/`.
- Any `make ecosystem-*` invocation produces one consolidated `ecosystem_*.txt` report file.
- Tier 1 and Tier 3 print step-by-step checks with explicit pass/fail markers.
- Report retention is automatic (default keeps latest 10 per report type). Override with `FLUX_MAX_REPORTS`.
