#!/usr/bin/env Rscript

# Render tutorials into GitHub-viewable markdown without requiring pandoc.
# - Knits .Rmd and literate .md sources directly.
# - Spins .R tutorial scripts to temporary .Rmd, normalizes chunk headers,
#   then knits to .md.
# - Writes figures under tutorials/figure so image links resolve on GitHub.

`%||%` <- function(x, y) if (is.null(x)) y else x

script_path <- normalizePath(commandArgs(trailingOnly = FALSE), mustWork = FALSE)
script_arg <- grep("^--file=", script_path, value = TRUE)
script_file <- sub("^--file=", "", script_arg[1])
script_file <- if (is.na(script_file) || script_file == "") "tutorials/render_for_github.R" else script_file
repo_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = FALSE)
setwd(repo_root)

ensure_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
}

render_knit <- function(input) {
  output <- file.path(dirname(input), paste0(tools::file_path_sans_ext(basename(input)), ".md"))
  message("Knitting ", input, " -> ", output)
  knitr::knit(input, output = output, quiet = TRUE)
  txt <- readLines(output, warn = FALSE)
  txt <- gsub("\\(tutorials/figure/", "(figure/", txt)
  writeLines(txt, output)
}

render_spin <- function(input) {
  output <- file.path(dirname(input), paste0(tools::file_path_sans_ext(basename(input)), ".md"))
  message("Spinning ", input)
  spun_rmd <- knitr::spin(input, knit = FALSE, format = "Rmd")

  # knitr::spin can emit chunk headers like ```{rlabel}; normalize to ```{r label}
  txt <- readLines(spun_rmd, warn = FALSE)
  txt <- sub("^```\\{r([^ ,}])", "```{r \\1", txt)
  writeLines(txt, spun_rmd)

  message("Knitting ", spun_rmd, " -> ", output)
  knitr::knit(spun_rmd, output = output, quiet = TRUE)
  txt <- readLines(output, warn = FALSE)
  txt <- gsub("\\(tutorials/figure/", "(figure/", txt)
  writeLines(txt, output)
  unlink(spun_rmd)
}

ensure_dir("tutorials/figure")
knitr::opts_knit$set(base.dir = repo_root, root.dir = repo_root)
knitr::opts_chunk$set(fig.path = "figure/")

knit_inputs <- c(
  "tutorials/01_core_engine_scaffold.Rmd",
  "tutorials/03_validation_observed_grids_and_masks.Rmd",
  "tutorials/04_validation_event_risk_apples_to_apples.Rmd",
  "tutorials/05_orchestration_framework.md"
)

spin_inputs <- c(
  "tutorials/06_ascvd_ecosystem_welcome.R",
  "tutorials/07_ascvd_prepare_ttv.R"
)

for (f in knit_inputs) render_knit(f)
for (f in spin_inputs) render_spin(f)

if (dir.exists("figure")) {
  file.copy(from = list.files("figure", full.names = TRUE), to = "tutorials/figure", recursive = TRUE)
  unlink("figure", recursive = TRUE)
}

message("Tutorial rendering complete.")
