#!/usr/bin/env Rscript

message("[Ecosystem] Running Tier 1 -> Tier 2 -> Tier 3")
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
stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
summary_path <- file.path(reports_dir, paste0("ecosystem_", stamp, ".txt"))

tier_scripts <- c(
  tier1 = "run_tier1_smoke.R",
  tier2 = "run_tier2_package_tests.R",
  tier3 = "run_tier3_ascvd_demo.R"
)

run_script <- function(tier_name, script_name) {
  path <- file.path(root, script_name)
  log_path <- file.path(reports_dir, paste0(tier_name, "_", stamp, ".log"))
  message("[Ecosystem] -> ", basename(path))
  t_start <- Sys.time()
  out <- tryCatch(
    system2("Rscript", path, stdout = TRUE, stderr = TRUE),
    error = function(e) e
  )
  dt <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))

  if (inherits(out, "error")) {
    writeLines(c(paste("[Ecosystem] runner error:", conditionMessage(out))), con = log_path)
    return(list(tier = tier_name, status = "FAIL", seconds = dt, log = log_path, detail = conditionMessage(out)))
  }

  exit_status <- attr(out, "status")
  writeLines(out, con = log_path)
  cat(paste(out, collapse = "\n"), "\n")
  status <- if (!is.null(exit_status) && exit_status != 0) {
    "FAIL"
  } else if (any(grepl("\\]\\s+FAIL\\b", out))) {
    "FAIL"
  } else {
    "PASS"
  }
  list(tier = tier_name, status = status, seconds = dt, log = log_path, detail = "")
}

results <- lapply(names(tier_scripts), function(nm) run_script(nm, tier_scripts[[nm]]))
names(results) <- names(tier_scripts)
overall <- if (any(vapply(results, function(x) identical(x$status, "FAIL"), logical(1)))) "FAIL" else "PASS"

summary_lines <- c(
  sprintf("[Ecosystem] Summary: %s", overall),
  sprintf("[Ecosystem] Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  ""
)

for (nm in names(results)) {
  r <- results[[nm]]
  line <- sprintf("  - %s: %s (%.2fs) log=%s", r$tier, r$status, r$seconds, r$log)
  if (nzchar(r$detail)) line <- paste0(line, " detail=", r$detail)
  summary_lines <- c(summary_lines, line)
}

total_dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
summary_lines <- c(summary_lines, "", sprintf("[Ecosystem] Total duration: %.2fs", total_dt))
writeLines(summary_lines, con = summary_path)
message(paste(summary_lines, collapse = "\n"))
message("[Ecosystem] Summary report: ", summary_path)

if (identical(overall, "FAIL")) quit(save = "no", status = 1)
