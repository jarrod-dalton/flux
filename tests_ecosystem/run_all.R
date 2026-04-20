#!/usr/bin/env Rscript

tier_scripts <- c(
  tier1 = "run_tier1_smoke.R",
  tier2 = "run_tier2_package_tests.R",
  tier3 = "run_tier3_ascvd_demo.R"
)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0L) {
  selected_tiers <- names(tier_scripts)
} else {
  selected_tiers <- unique(args)
  bad <- setdiff(selected_tiers, names(tier_scripts))
  if (length(bad)) stop("Unknown tier(s): ", paste(bad, collapse = ", "))
}
message("[Ecosystem] Running: ", paste(selected_tiers, collapse = " -> "))
t0 <- Sys.time()

cmd_args <- commandArgs(trailingOnly = FALSE)
file_arg <- "--file="
script_path <- sub(file_arg, "", cmd_args[grep(file_arg, cmd_args)][1])
if (!is.na(script_path) && nzchar(script_path)) {
  root <- normalizePath(dirname(script_path), winslash = "/", mustWork = FALSE)
} else {
  root <- getwd()
}

reports_dir <- file.path(root, "reports")
if (!dir.exists(reports_dir)) dir.create(reports_dir, recursive = TRUE, showWarnings = FALSE)
now_stamp <- Sys.time()
stamp <- sprintf("%s_%03d", format(now_stamp, "%Y%m%d_%H%M%S"), as.integer((as.numeric(now_stamp) %% 1) * 1000))
summary_path <- file.path(reports_dir, paste0("ecosystem_", stamp, ".txt"))
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

selected_scripts <- tier_scripts[selected_tiers]

run_script <- function(tier_name, script_name) {
  path <- file.path(root, script_name)
  message("[Ecosystem] -> ", basename(path))
  t_start <- Sys.time()
  out <- tryCatch(
    system2("Rscript", path, stdout = TRUE, stderr = TRUE, env = c("FLUX_DISABLE_REPORT_FILE=1")),
    error = function(e) e
  )
  dt <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))

  if (inherits(out, "error")) {
    return(list(tier = tier_name, status = "FAIL", seconds = dt, output = paste("[Ecosystem] runner error:", conditionMessage(out)), detail = conditionMessage(out)))
  }

  exit_status <- attr(out, "status")
  cat(paste(out, collapse = "\n"), "\n")
  status <- if (!is.null(exit_status) && exit_status != 0) {
    "FAIL"
  } else if (any(grepl("\\]\\s+FAIL\\b", out))) {
    "FAIL"
  } else {
    "PASS"
  }
  list(tier = tier_name, status = status, seconds = dt, output = out, detail = "")
}

results <- lapply(names(selected_scripts), function(nm) run_script(nm, selected_scripts[[nm]]))
names(results) <- names(selected_scripts)
overall <- if (any(vapply(results, function(x) identical(x$status, "FAIL"), logical(1)))) "FAIL" else "PASS"

summary_lines <- c(
  sprintf("[Ecosystem] Summary: %s", overall),
  sprintf("[Ecosystem] Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  ""
)

for (nm in names(results)) {
  r <- results[[nm]]
  line <- sprintf("  - %s: %s (%.2fs)", r$tier, r$status, r$seconds)
  if (nzchar(r$detail)) line <- paste0(line, " detail=", r$detail)
  summary_lines <- c(summary_lines, line)
}

total_dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
summary_lines <- c(summary_lines, "", sprintf("[Ecosystem] Total duration: %.2fs", total_dt))
report_body <- summary_lines
for (nm in names(results)) {
  r <- results[[nm]]
  report_body <- c(
    report_body,
    "",
    paste0("========== ", toupper(r$tier), " OUTPUT =========="),
    if (length(r$output)) r$output else "(no output)"
  )
}
writeLines(report_body, con = summary_path)
prune_reports("ecosystem")
message(paste(summary_lines, collapse = "\n"))
message("[Ecosystem] Summary report: ", summary_path)
message(sprintf("[Ecosystem] Report retention: keeping latest %d ecosystem reports", max_reports))

if (identical(overall, "FAIL")) quit(save = "no", status = 1)
