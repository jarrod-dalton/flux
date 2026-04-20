#!/usr/bin/env Rscript

log_line <- function(...) cat(paste0(...), "\n", sep = "")
log_line("[Tier 3] ASCVD-driven ecosystem integration")
t0 <- Sys.time()
status <- "PASS"
err <- NULL

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
report_path <- file.path(reports_dir, paste0("tier3_", stamp, ".txt"))
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

step <- function(msg) log_line("[Tier 3] STEP: ", msg)
pass <- function(msg) log_line("[Tier 3]   PASS: ", msg)

if (!is.null(report_path)) {
  sink_con <- file(report_path, open = "wt")
  sink(sink_con, type = "output", split = TRUE)
  on.exit({
    sink(type = "output")
    close(sink_con)
  }, add = TRUE)
}

tryCatch({
  step("Loading required packages (fluxCore, fluxPrepare, fluxASCVD)")
  suppressPackageStartupMessages({
    library(fluxCore)
    library(fluxPrepare)
    library(fluxASCVD)
  })
  pass("Packages loaded")

  step("Checking ASCVD example-data helper availability")
  if (!exists("ascvd_make_example_ehr", where = asNamespace("fluxASCVD"), inherits = FALSE)) {
    log_line("[Tier 3] SKIP: fluxASCVD::ascvd_make_example_ehr not available")
    quit(save = "no", status = 0)
  }
  pass("ascvd_make_example_ehr is available")

  step("Generating example EHR data")
  make_ehr <- getFromNamespace("ascvd_make_example_ehr", ns = "fluxASCVD")
  ehr <- make_ehr(n_entities = 25, seed = 123)
  pass(sprintf("Generated entities=%d, events=%d", nrow(ehr$entities), nrow(ehr$events)))

  step("Preparing split assignments from example entities")
  splits <- prepare_splits(data.frame(
    entity_id = ehr$entities$entity_id,
    split = ifelse(ehr$entities$entity_id %% 5 == 0, "validation", ifelse(ehr$entities$entity_id %% 4 == 0, "test", "train")),
    stringsAsFactors = FALSE
  ))
  pass(sprintf("Prepared splits rows=%d", nrow(splits)))

  step("Preparing canonical event table from ASCVD events")
  events <- prepare_events(
    data.frame(
      entity_id = ehr$events$entity_id,
      time = as.numeric(ehr$events$event_date - ehr$entities$index_date[match(ehr$events$entity_id, ehr$entities$entity_id)]),
      event_type = ehr$events$event,
      stringsAsFactors = FALSE
    )
  )
  pass(sprintf("Prepared events rows=%d", nrow(events)))

  step("Validating integration invariants")
  stopifnot(nrow(splits) == nrow(ehr$entities), nrow(events) > 0)
  pass("Split/entity alignment and non-empty events confirmed")
}, error = function(e) {
  status <<- "FAIL"
  err <<- conditionMessage(e)
})

dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
log_line(sprintf("[Tier 3] %s (%.2fs)", status, dt))
if (!is.null(err)) log_line("[Tier 3] Error: ", err)
if (!is.null(report_path)) {
  prune_reports("tier3")
  log_line("[Tier 3] Report: ", report_path)
  log_line(sprintf("[Tier 3] Report retention: keeping latest %d tier3 reports", max_reports))
}
if (identical(status, "FAIL")) quit(save = "no", status = 1)
