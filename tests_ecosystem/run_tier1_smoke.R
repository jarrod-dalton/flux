#!/usr/bin/env Rscript

log_line <- function(...) cat(paste0(...), "\n", sep = "")
log_line("[Tier 1] Ecosystem smoke test")
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
report_path <- file.path(reports_dir, paste0("tier1_", stamp, ".txt"))
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

step <- function(msg) log_line("[Tier 1] STEP: ", msg)
pass <- function(msg) log_line("[Tier 1]   PASS: ", msg)

if (!is.null(report_path)) {
  sink_con <- file(report_path, open = "wt")
  sink(sink_con, type = "output", split = TRUE)
  on.exit({
    sink(type = "output")
    close(sink_con)
  }, add = TRUE)
}

tryCatch({
  step("Loading required packages (fluxCore, fluxPrepare, fluxForecast, fluxValidation)")
  suppressPackageStartupMessages({
    library(fluxCore)
    library(fluxPrepare)
    library(fluxForecast)
    library(fluxValidation)
  })
  pass("Packages loaded")

  step("Prepare smoke: build splits/events/observations")
  spl <- prepare_splits(data.frame(entity_id = c("e1", "e2"), split = c("train", "test")))
  ev <- prepare_events(data.frame(entity_id = c("e1", "e2"), time = c(1, 2), event_type = c("visit", "visit")))
  obs <- prepare_observations(
    list(vitals = data.frame(entity_id = c("e1", "e1", "e2"), time = c(0, 1, 0), sbp = c(120, 122, 130))),
    specs = list(vitals = list(id_col = "entity_id", time_col = "time", vars = c("sbp"), group = "vitals"))
  )
  stopifnot(nrow(spl) == 2, nrow(ev) == 2, nrow(obs) >= 2)
  pass(sprintf("Prepared splits=%d, events=%d, observations=%d", nrow(spl), nrow(ev), nrow(obs)))

  step("Core smoke: construct schema, engine, and entities")
  schema <- list(
    route_zone = list(
      type = "categorical",
      levels = c("urban", "suburban", "rural"),
      default = "urban",
      coerce = as.character
    ),
    workload = list(type = "numeric", default = 0, coerce = as.numeric)
  )

  bundle <- list(
    time_spec = time_spec(unit = "hours"),
    event_catalog = c("VISIT", "RUN_END"),
    terminal_events = "RUN_END",
    propose_events = function(entity, process_ids = NULL, current_proposals = NULL) {
      list(
        visit = list(time_next = entity$last_time + 1, event_type = "VISIT"),
        end = list(time_next = 3, event_type = "RUN_END")
      )
    },
    transition = function(entity, event) {
      if (!identical(event$event_type, "VISIT")) return(list())
      list(workload = as.numeric(entity$as_list("workload")$workload) + 1)
    },
    stop = function(entity, event) identical(event$event_type, "RUN_END")
  )
  eng <- Engine$new(bundle = bundle)
  ents <- list(
    e1 = Entity$new(init = list(route_zone = "urban", workload = 0), schema = schema),
    e2 = Entity$new(init = list(route_zone = "suburban", workload = 1), schema = schema)
  )
  pass(sprintf("Engine + %d entities created", length(ents)))

  step("Forecast smoke: run forecast object generation")
  fx <- forecast(
    engine = eng,
    entities = ents,
    times = c(0, 1, 2),
    S = 2,
    vars = c("workload"),
    return = "object",
    backend = "none"
  )
  pass(sprintf("Forecast object created (class=%s)", paste(class(fx), collapse = ",")))

  step("Forecast summary smoke: derive event probability")
  ep <- event_prob(fx, event = "VISIT", start_time = 0)
  pass(sprintf("Event-prob rows=%d", nrow(ep$result)))

  step("Validation smoke: build observation grid and compare predicted risk")
  obs_grid <- build_obs_grid(
    vars = list(data.frame(entity_id = c("e1", "e1", "e2"), time = c(0, 1, 0), workload = c(0, 1, 1))),
    events = data.frame(entity_id = c("e1"), event_time = c(1), event_type = c("VISIT")),
    times = c(0, 1, 2),
    t0 = 0
  )

  val <- validate_event_risk(ep, obs_grid, event = "VISIT", start_time = 0, obs_mode = "fixed_cohort")
  stopifnot(inherits(ep, "flux_event_prob"), is.list(val), nrow(ep$result) > 0, nrow(val$comparison) > 0)
  pass(sprintf("Validation comparison rows=%d", nrow(val$comparison)))
}, error = function(e) {
  status <<- "FAIL"
  err <<- conditionMessage(e)
})

dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
log_line(sprintf("[Tier 1] %s (%.2fs)", status, dt))
if (!is.null(err)) log_line("[Tier 1] Error: ", err)
if (!is.null(report_path)) {
  prune_reports("tier1")
  log_line("[Tier 1] Report: ", report_path)
  log_line(sprintf("[Tier 1] Report retention: keeping latest %d tier1 reports", max_reports))
}
if (identical(status, "FAIL")) quit(save = "no", status = 1)
