#!/usr/bin/env Rscript

message("[Tier 2] Package-level test battery")
t0 <- Sys.time()
status <- "PASS"

repos <- c(
  "subrepos/fluxCore",
  "subrepos/fluxPrepare",
  "subrepos/fluxForecast",
  "subrepos/fluxValidation",
  "subrepos/fluxOrchestrate",
  "subrepos/fluxModelTemplate"
)

cmd_args <- commandArgs(trailingOnly = FALSE)
file_arg <- "--file="
script_path <- sub(file_arg, "", cmd_args[grep(file_arg, cmd_args)][1])
if (!is.na(script_path) && nzchar(script_path)) {
  root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = FALSE)
} else {
  root <- getwd()
}

reports_dir <- file.path(root, "tests_ecosystem", "reports")
if (!dir.exists(reports_dir)) dir.create(reports_dir, recursive = TRUE, showWarnings = FALSE)
now_stamp <- Sys.time()
stamp <- sprintf("%s_%03d", format(now_stamp, "%Y%m%d_%H%M%S"), as.integer((as.numeric(now_stamp) %% 1) * 1000))
report_path <- file.path(reports_dir, paste0("tier2_", stamp, ".txt"))
disable_report <- identical(tolower(Sys.getenv("FLUX_DISABLE_REPORT_FILE", unset = "0")), "1")
if (disable_report) report_path <- NULL
max_reports <- suppressWarnings(as.integer(Sys.getenv("FLUX_MAX_REPORTS", unset = "10")))
if (is.na(max_reports) || max_reports < 1L) max_reports <- 10L

prune_reports <- function(prefix) {
  patt <- paste0("^", prefix, "_[0-9]{8}_[0-9]{6}(_[0-9]{3})?\\.txt$")
  files <- list.files(reports_dir, pattern = patt, full.names = TRUE)
  if (length(files) <= max_reports) return(invisible(NULL))
  info <- file.info(files)
  ord <- order(info$mtime, decreasing = TRUE, na.last = TRUE)
  old <- files[ord[(max_reports + 1L):length(files)]]
  unlink(old)
}

results <- vector("list", length(repos))
names(results) <- repos

run_pkg_tests <- function(pkg_path) {
  script <- tempfile("tier2_pkg_", fileext = ".R")
  on.exit(unlink(script), add = TRUE)
  lines <- c(
    "suppressPackageStartupMessages(library(devtools))",
    sprintf("setwd('%s')", gsub("'", "\\\\'", pkg_path)),
    "devtools::load_all(quiet = TRUE)",
    "devtools::test()"
  )
  writeLines(lines, con = script)
  system2("Rscript", script, stdout = TRUE, stderr = TRUE)
}

extract_counts <- function(lines) {
  idx <- grep("\\[ FAIL\\s+\\d+\\s+\\|\\s+WARN\\s+\\d+\\s+\\|\\s+SKIP\\s+\\d+\\s+\\|\\s+PASS\\s+\\d+\\s*\\]", lines)
  if (!length(idx)) return(NULL)
  m <- regmatches(lines[idx[length(idx)]], regexec("\\[ FAIL\\s+(\\d+)\\s+\\|\\s+WARN\\s+(\\d+)\\s+\\|\\s+SKIP\\s+(\\d+)\\s+\\|\\s+PASS\\s+(\\d+)\\s*\\]", lines[idx[length(idx)]]))[[1]]
  if (length(m) != 5) return(NULL)
  list(fail = as.integer(m[2]), warn = as.integer(m[3]), skip = as.integer(m[4]), pass = as.integer(m[5]))
}

if (!is.null(report_path)) {
  sink_con <- file(report_path, open = "wt")
  sink(sink_con, type = "output", split = TRUE)
  sink(sink_con, type = "message")
  on.exit({
    sink(type = "message")
    sink(type = "output")
    close(sink_con)
  }, add = TRUE)
}

for (repo in repos) {
  p <- file.path(root, repo)
  repo_label <- basename(repo)
  if (!file.exists(file.path(p, "DESCRIPTION"))) {
    status <- "FAIL"
    results[[repo]] <- list(status = "FAIL", fail = NA_integer_, warn = NA_integer_, skip = NA_integer_, pass = NA_integer_, seconds = 0, note = "Missing DESCRIPTION", label = repo_label)
    message("[Tier 2] ", repo_label, " -> FAIL (missing DESCRIPTION)")
    next
  }
  message("\n[Tier 2] Testing ", repo_label)
  pkg_t0 <- Sys.time()
  out <- tryCatch(run_pkg_tests(p), error = function(e) e)
  pkg_dt <- as.numeric(difftime(Sys.time(), pkg_t0, units = "secs"))

  if (inherits(out, "error")) {
    status <- "FAIL"
    results[[repo]] <- list(status = "FAIL", fail = NA_integer_, warn = NA_integer_, skip = NA_integer_, pass = NA_integer_, seconds = pkg_dt, note = conditionMessage(out), label = repo_label)
    message("[Tier 2] ", repo_label, " -> FAIL (runner error: ", conditionMessage(out), ")")
    next
  }

  cat(paste(out, collapse = "\n"), "\n")
  counts <- extract_counts(out)
  if (is.null(counts)) {
    status <- "FAIL"
    results[[repo]] <- list(status = "FAIL", fail = NA_integer_, warn = NA_integer_, skip = NA_integer_, pass = NA_integer_, seconds = pkg_dt, note = "Could not parse test summary line", label = repo_label)
    message("[Tier 2] ", repo_label, " -> FAIL (no summary line found)")
    next
  }

  pkg_status <- if (counts$fail > 0L) "FAIL" else "PASS"
  if (identical(pkg_status, "FAIL")) status <- "FAIL"
  results[[repo]] <- c(list(status = pkg_status, seconds = pkg_dt, note = "", label = repo_label), counts)
  message(
    sprintf(
      "[Tier 2] %s -> %s [FAIL %d | WARN %d | SKIP %d | PASS %d] (%.2fs)",
      repo_label, pkg_status, counts$fail, counts$warn, counts$skip, counts$pass, pkg_dt
    )
  )
}

message("\n[Tier 2] Summary")
for (repo in repos) {
  r <- results[[repo]]
  if (is.null(r)) next
  label <- if (!is.null(r$label)) r$label else basename(repo)
  if (!is.na(r$fail)) {
    message(
      sprintf(
        "  - %-24s %4s  [FAIL %d | WARN %d | SKIP %d | PASS %d] (%.2fs)",
        label, r$status, r$fail, r$warn, r$skip, r$pass, r$seconds
      )
    )
  } else {
    message(sprintf("  - %-24s %4s  (%s)", label, r$status, r$note))
  }
}

dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
message(sprintf("\n[Tier 2] %s (%.2fs)", status, dt))
if (!is.null(report_path)) {
  prune_reports("tier2")
  message("[Tier 2] Report: ", report_path)
  message(sprintf("[Tier 2] Report retention: keeping latest %d tier2 reports", max_reports))
}
if (identical(status, "FAIL")) quit(save = "no", status = 1)
