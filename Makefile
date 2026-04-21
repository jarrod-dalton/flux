SHELL := /bin/zsh

.PHONY: ecosystem-tier1 ecosystem-tier2 ecosystem-tier3 ecosystem-all ecosystem-clean-reports release-dry release-exec release-gh

ecosystem-tier1:
	Rscript tests_ecosystem/run_all.R tier1

ecosystem-tier2:
	Rscript tests_ecosystem/run_all.R tier2

ecosystem-tier3:
	Rscript tests_ecosystem/run_all.R tier3

ecosystem-all:
	Rscript tests_ecosystem/run_all.R

ecosystem-clean-reports:
	find tests_ecosystem/reports -type f ! -name '.gitkeep' -delete

release-dry:
	./scripts/release/release_1_5_0.sh

release-exec:
	./scripts/release/release_1_5_0.sh --execute

release-gh:
	./scripts/release/release_1_5_0.sh --execute --gh-release
