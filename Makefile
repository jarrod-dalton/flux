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
	./resources/scripts/release/release_ecosystem.sh

release-exec:
	./resources/scripts/release/release_ecosystem.sh --execute

release-gh:
	./resources/scripts/release/release_ecosystem.sh --execute --gh-release
