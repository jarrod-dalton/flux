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

strip_yaml_frontmatter <- function(lines) {

  # Remove YAML frontmatter (---...---) from rendered .md so GitHub doesn't

  # display it as a formatted table.
  if (length(lines) >= 2L && lines[1L] == "---") {
    close <- which(lines[-1L] == "---")[1L] + 1L
    if (!is.na(close)) {
      lines <- lines[(close + 1L):length(lines)]
      # strip leading blank lines after frontmatter removal
      while (length(lines) > 0L && lines[1L] == "") lines <- lines[-1L]
    }
  }
  lines
}

render_knit <- function(input) {
  # Output always goes into tutorials/ (parent of src/), not src/ itself
  out_dir <- if (basename(dirname(input)) == "src") dirname(dirname(input)) else dirname(input)
  output <- file.path(out_dir, paste0(tools::file_path_sans_ext(basename(input)), ".md"))
  message("Knitting ", input, " -> ", output)
  knitr::knit(input, output = output, quiet = TRUE)
  txt <- readLines(output, warn = FALSE)
  txt <- gsub("\\(tutorials/figure/", "(figure/", txt)
  txt <- strip_yaml_frontmatter(txt)
  writeLines(txt, output)
}

render_spin <- function(input) {
  out_dir <- if (basename(dirname(input)) == "src") dirname(dirname(input)) else dirname(input)
  output <- file.path(out_dir, paste0(tools::file_path_sans_ext(basename(input)), ".md"))
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
  txt <- strip_yaml_frontmatter(txt)
  writeLines(txt, output)
  unlink(spun_rmd)
}

ensure_dir("tutorials/figure")
knitr::opts_knit$set(base.dir = repo_root, root.dir = repo_root)
knitr::opts_chunk$set(fig.path = "figure/")

knit_inputs <- c(
  "tutorials/src/01_core_engine_scaffold.Rmd",
  "tutorials/src/02_cohort_forecast.Rmd",
  "tutorials/src/03_decisions_policy.Rmd",
  "tutorials/src/04_prepare_operational_data.Rmd",
  "tutorials/src/05_validation.Rmd"
)

spin_inputs <- character(0)

for (f in knit_inputs) render_knit(f)
for (f in spin_inputs) render_spin(f)

if (dir.exists("figure")) {
  file.copy(from = list.files("figure", full.names = TRUE), to = "tutorials/figure", recursive = TRUE)
  unlink("figure", recursive = TRUE)
}

message("Tutorial rendering complete.")
