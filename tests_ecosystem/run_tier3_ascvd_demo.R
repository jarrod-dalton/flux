#!/usr/bin/env Rscript

message("[Tier 3] ASCVD-driven ecosystem integration")
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
stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
report_path <- file.path(reports_dir, paste0("tier3_", stamp, ".txt"))

sink_con <- file(report_path, open = "wt")
sink(sink_con, type = "output", split = TRUE)
sink(sink_con, type = "message")
on.exit({
  sink(type = "message")
  sink(type = "output")
  close(sink_con)
}, add = TRUE)

tryCatch({
  suppressPackageStartupMessages({
    library(fluxCore)
    library(fluxPrepare)
    library(fluxASCVD)
  })

  if (!exists("ascvd_make_example_ehr", where = asNamespace("fluxASCVD"), inherits = FALSE)) {
    message("[Tier 3] SKIP: fluxASCVD::ascvd_make_example_ehr not available")
    quit(save = "no", status = 0)
  }

  make_ehr <- getFromNamespace("ascvd_make_example_ehr", ns = "fluxASCVD")
  ehr <- make_ehr(n_entities = 25, seed = 123)

  # Build simple splits for demo entities
  splits <- prepare_splits(data.frame(
    entity_id = ehr$entities$entity_id,
    split = ifelse(ehr$entities$entity_id %% 5 == 0, "validation", ifelse(ehr$entities$entity_id %% 4 == 0, "test", "train")),
    stringsAsFactors = FALSE
  ))

  # Minimal canonical event prep using ASCVD example events
  events <- prepare_events(
    data.frame(
      entity_id = ehr$events$entity_id,
      time = as.numeric(ehr$events$event_date - ehr$entities$index_date[match(ehr$events$entity_id, ehr$entities$entity_id)]),
      event_type = ehr$events$event,
      stringsAsFactors = FALSE
    )
  )

  stopifnot(nrow(splits) == nrow(ehr$entities), nrow(events) > 0)
}, error = function(e) {
  status <<- "FAIL"
  err <<- conditionMessage(e)
})

dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
message(sprintf("[Tier 3] %s (%.2fs)", status, dt))
if (!is.null(err)) message("[Tier 3] Error: ", err)
message("[Tier 3] Report: ", report_path)
if (identical(status, "FAIL")) quit(save = "no", status = 1)
