#!/usr/bin/env Rscript

message("[Tier 1] Ecosystem smoke test")
t0 <- Sys.time()
status <- "PASS"
err <- NULL

tryCatch({
  suppressPackageStartupMessages({
    library(fluxCore)
    library(fluxPrepare)
    library(fluxForecast)
    library(fluxValidation)
  })

  # Prepare smoke
  spl <- prepare_splits(data.frame(entity_id = c("e1", "e2"), split = c("train", "test")))
  ev <- prepare_events(data.frame(entity_id = c("e1", "e2"), time = c(1, 2), event_type = c("visit", "visit")))
  obs <- prepare_observations(
    list(vitals = data.frame(entity_id = c("e1", "e1", "e2"), time = c(0, 1, 0), sbp = c(120, 122, 130))),
    specs = list(vitals = list(id_col = "entity_id", time_col = "time", vars = c("sbp"), group = "vitals"))
  )
  stopifnot(nrow(spl) == 2, nrow(ev) == 2, nrow(obs) >= 2)

  # Core + Forecast smoke
  schema <- default_entity_schema()
  schema$age <- list(type = "continuous", default = 50, coerce = as.numeric)
  schema$miles_to_work <- list(type = "continuous", default = 8, coerce = as.numeric)

  eng <- Engine$new(provider = PackageProvider$new(), model_spec = list(name = "default"))
  ents <- list(
    e1 = new_entity(init = list(alive = TRUE, age = 50, miles_to_work = 8), schema = schema),
    e2 = new_entity(init = list(alive = TRUE, age = 55, miles_to_work = 5), schema = schema)
  )

  fx <- forecast(
    engine = eng,
    entities = ents,
    times = c(0, 1, 2),
    S = 2,
    vars = c("alive", "age"),
    return = "object",
    backend = "none"
  )

  ep <- event_prob(fx, event = "VISIT", start_time = 0)

  # Validation smoke
  obs_grid <- build_obs_grid(
    vars = list(data.frame(entity_id = c("e1", "e1", "e2"), time = c(0, 1, 0), alive = c(TRUE, TRUE, TRUE))),
    events = data.frame(entity_id = c("e1"), event_time = c(1), event_type = c("VISIT")),
    times = c(0, 1, 2),
    t0 = 0
  )

  val <- validate_event_risk(ep, obs_grid, event = "VISIT", start_time = 0, obs_mode = "policy")
  stopifnot(inherits(ep, "flux_event_prob"), is.list(val), nrow(ep$result) > 0, nrow(val$comparison) > 0)
}, error = function(e) {
  status <<- "FAIL"
  err <<- conditionMessage(e)
})

dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
message(sprintf("[Tier 1] %s (%.2fs)", status, dt))
if (!is.null(err)) message("[Tier 1] Error: ", err)
if (identical(status, "FAIL")) quit(save = "no", status = 1)
