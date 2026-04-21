# Maintainer Notes: Repo Rename + Submodule URL Sync

This file is for maintainers performing repository administration tasks.

## Context

The super-repo uses submodules:

- `fluxCore`
- `fluxPrepare`
- `fluxForecast`
- `fluxValidation`
- `fluxOrchestrate`
- `fluxASCVD`
- `fluxModelTemplate`

If GitHub repositories are renamed from `patientSim*` to `flux*`, update
submodule URLs and local remotes afterward.

## Steps

1. Rename each repository in GitHub (UI or `gh` CLI).
2. From super-repo root, run:

```bash
./scripts/maintenance/sync_submodule_urls_to_flux.sh
git submodule sync --recursive
git submodule update --init --recursive
```

3. Commit the `.gitmodules` changes:

```bash
git add .gitmodules
git commit -m "Update submodule URLs to flux* repos"
git push
```
