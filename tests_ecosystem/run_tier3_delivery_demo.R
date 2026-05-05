#!/usr/bin/env Rscript
# ==============================================================================
# Tier 3 Ecosystem Test: Urban Delivery End-to-End Demo
# ==============================================================================
#
# Full pipeline: model definition → synthetic data → TTV prep → forecast →
# validation. Verifies that all packages work together on a real(istic) workflow.
#
# Determinism: re-running with identical seed must produce identical results.
#
# Exit 0 on success; non-zero on any failure.
# ==============================================================================

library(fluxCore)
library(fluxPrepare)
library(fluxForecast)
library(fluxValidation)

cat("[Tier 3] Urban delivery end-to-end demo\n")
cat("[Tier 3] Loading model definitions...\n")

# Resolve paths relative to the ecosystem test directory
test_root <- if (nzchar(Sys.getenv("FLUX_ROOT"))) {
  Sys.getenv("FLUX_ROOT")
} else {
  # Try --file= arg (Rscript), then fallback to working directory parent
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("--file=", "", cmd_args[grep("--file=", cmd_args)][1])
  if (!is.na(file_arg) && nzchar(file_arg)) {
    normalizePath(file.path(dirname(file_arg), ".."), mustWork = FALSE)
  } else {
    normalizePath("..", mustWork = FALSE)
  }
}

source(file.path(test_root, "tutorials", "model", "urban_delivery.R"))
source(file.path(test_root, "tutorials", "model", "urban_delivery_data.R"))

# -- 1. Generate synthetic operational log (deterministic) ---------------------
cat("[Tier 3] Generating synthetic fleet data (20 agents, 5 shifts)...\n")
set.seed(42)
ops <- generate_delivery_log(n_agents = 20, n_shifts = 5)

stopifnot(nrow(ops$entities) == 20)
stopifnot(nrow(ops$events) > 0)
stopifnot(nrow(ops$observations) > 0)
stopifnot(nrow(ops$followup) == 100)  # 20 agents × 5 shifts

# -- 2. Prepare TTV -----------------------------------------------------------
cat("[Tier 3] Preparing events, observations, splits, and TTV...\n")

events_prep <- prepare_events(
  events    = ops$events,
  id_col    = "entity_id",
  time_col  = "time",
  type_col  = "event_type",
  time_spec = time_spec(unit = "hours")
)

battery_spec <- list(
  id_col   = "entity_id",
  time_col = "time",
  vars     = "battery_pct"
)

obs_prep <- prepare_observations(
  tables    = list(battery = ops$observations),
  specs     = list(battery = battery_spec),
  time_spec = time_spec(unit = "hours")
)

splits <- generate_splits(ops$entities, train_frac = 0.6, test_frac = 0.2,
                          seed = 123)
splits_prep <- prepare_splits(splits, id_col = "entity_id", split_col = "split")

delivery_ep_spec <- spec_event_process(
  event_types = "delivery_completed",
  name        = "delivery_completion",
  t0_strategy = "followup_start"
)

ttv <- build_ttv_event_process(
  events       = events_prep,
  observations = obs_prep,
  splits       = splits_prep,
  spec         = delivery_ep_spec,
  followup     = ops$followup,
  time_spec    = time_spec(unit = "hours")
)

stopifnot(is.data.frame(ttv))
stopifnot(nrow(ttv) > 0)
stopifnot("split" %in% names(ttv))

ttv_train <- ttv[ttv$split == "train", ]
ttv_test  <- ttv[ttv$split == "test", ]
stopifnot(nrow(ttv_train) > 0)
stopifnot(nrow(ttv_test) > 0)

# -- 3. Reconstruct state at t0 and build entities ----------------------------
cat("[Tier 3] Reconstructing test-set entity states...\n")

state_at_t0 <- reconstruct_state_at(
  anchors      = ttv_test[, c("entity_id", "t0")],
  observations = obs_prep,
  vars         = "battery_pct",
  id_col       = "entity_id",
  time_col     = "t0",
  time_spec    = time_spec(unit = "hours")
)

stopifnot(nrow(state_at_t0) > 0)

shared_schema <- delivery_schema()

test_entities <- lapply(seq_len(nrow(state_at_t0)), function(i) {
  row <- state_at_t0[i, ]
  battery <- if (is.na(row$battery_pct)) 80 else row$battery_pct
  Entity$new(
    id          = row$entity_id,
    init = list(
      battery_pct   = battery,
      route_zone    = "urban",
      payload_kg    = 0,
      dispatch_mode = "idle"
    ),
    schema      = shared_schema,
    entity_type = "delivery_agent",
    time0       = row$t0
  )
})
names(test_entities) <- state_at_t0$entity_id

# -- 4. Forecast from test-set agent states -----------------------------------
cat("[Tier 3] Running forecast (S=50, horizon=8h)...\n")

eng <- Engine$new(bundle = delivery_bundle())
times <- seq(1, 8, by = 1)

fc <- forecast(
  engine   = eng,
  entities = test_entities,
  times    = times,
  S        = 50,
  seed     = 42
)

ep <- event_prob(fc, event = "delivery_completed", times = times)

stopifnot(nrow(ep) > 0)
stopifnot(all(ep$prob >= 0 & ep$prob <= 1))

# -- 5. Validate --------------------------------------------------------------
cat("[Tier 3] Running validation...\n")

# build_obs_grid needs observation data to define at-risk entity set
# Subset observations to test-set entities and relevant columns
test_ids <- unique(state_at_t0$entity_id)
test_obs_df <- as.data.frame(obs_prep[obs_prep$entity_id %in% test_ids,
                                       c("entity_id", "time", "battery_pct")])

obs_grid <- build_obs_grid(
  vars           = list(battery = test_obs_df),
  events         = events_prep[events_prep$entity_id %in% test_ids, ],
  times          = times,
  t0             = 0,
  start_time     = 0,
  time_spec      = time_spec(unit = "hours"),
  id_col         = "entity_id",
  time_col       = "time",
  event_time_col = "time",
  event_type_col = "event_type"
)

vr <- validate_event_risk(
  pred  = ep,
  obs   = obs_grid,
  event = "delivery_completed",
  times = times
)

stopifnot(!is.null(vr))

# -- 6. Determinism check -----------------------------------------------------
cat("[Tier 3] Verifying determinism (same seed → same result)...\n")

fc2 <- forecast(
  engine   = eng,
  entities = test_entities,
  times    = times,
  S        = 50,
  seed     = 42
)

ep2 <- event_prob(fc2, event = "delivery_completed", times = times)

stopifnot(all.equal(ep$prob, ep2$prob, tolerance = 0))

# -- Done ----------------------------------------------------------------------
cat("[Tier 3] Urban delivery end-to-end demo: PASS\n")
