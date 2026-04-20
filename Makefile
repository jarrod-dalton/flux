SHELL := /bin/zsh

.PHONY: ecosystem-tier1 ecosystem-tier2 ecosystem-tier3 ecosystem-all release-dry release-exec release-gh

ecosystem-tier1:
	Rscript tests_ecosystem/run_tier1_smoke.R

ecosystem-tier2:
	Rscript tests_ecosystem/run_tier2_package_tests.R

ecosystem-tier3:
	Rscript tests_ecosystem/run_tier3_ascvd_demo.R

ecosystem-all:
	Rscript tests_ecosystem/run_all.R

release-dry:
	./release_1_5_0.sh

release-exec:
	./release_1_5_0.sh --execute

release-gh:
	./release_1_5_0.sh --execute --gh-release
