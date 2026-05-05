# End-to-End v1.x Path

Maturity: validated

This path is aligned with current v1.x contracts and existing package/ecosystem tests.

## Preconditions

- Clone super-repo with submodules:

```bash
git clone --recurse-submodules https://github.com/jarrod-dalton/flux.git
cd flux
```

- Ensure R dependencies are installed.

## Step 1: package-level unit tests

```r
setwd("subrepos/fluxCore"); devtools::load_all(); devtools::test()
setwd("../fluxPrepare"); devtools::load_all(); devtools::test()
setwd("../fluxForecast"); devtools::load_all(); devtools::test()
setwd("../fluxValidation"); devtools::load_all(); devtools::test()
setwd("../fluxOrchestrate"); devtools::load_all(); devtools::test()
setwd("../fluxModelTemplate"); devtools::load_all(); devtools::test()
```

## Step 2: ecosystem tiers

From super-repo root:

```bash
make ecosystem-tier1
make ecosystem-tier2
make ecosystem-tier3
```

Or run all tiers:

```bash
make ecosystem-all
```

## Step 3: optional domain walkthrough

Use the ASCVD reference scripts in this folder:

- `06_ascvd_ecosystem_welcome.md`
- `07_ascvd_prepare_ttv.md`

These demonstrate a concrete domain package while preserving the abstract ecosystem architecture.
