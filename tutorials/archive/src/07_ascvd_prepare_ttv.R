## Maturity: draft

## ----setup, include=FALSE-----------------------------------------------------
library(dplyr)
library(tidyr)
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  fig.width = 7,
  fig.height = 4
)
set.seed(1)


## ----figure-anchors-intervals, echo=FALSE-------------------------------------
op <- par(mar = c(4.1, 0.5, 2.6, 0.5))
on.exit(par(op), add = TRUE)

t_max <- 10

# Toy timeline for one entity (illustrative only)
anchors <- c(0, 3, 7, 9)
followup_end <- 9
death_time <- 10

labs_t <- c(0.8, 2.2, 4.6, 6.0, 8.4)
bp_t   <- c(1.0, 5.2, 8.9)
evt_mi <- 7.3

plot(
  x = c(0, t_max), y = c(0, 10), type = "n",
  xaxt = "n", yaxt = "n", xlab = "Model time (illustrative)", ylab = "",
  main = "Anchors, intervals, and follow-up (schematic)"
)
axis(1, at = seq(0, t_max, by = 1), labels = seq(0, t_max, by = 1))

# Lanes
y_interval <- 8.5
y_labs     <- 5.5
y_bp       <- 3.5
y_events   <- 1.6

# Interval backbone
segments(0, y_interval, t_max, y_interval, lwd = 1)

# Intervals between anchors
for (i in seq_len(length(anchors) - 1)) {
  segments(anchors[i], y_interval, anchors[i + 1], y_interval, lwd = 6)
}

# Anchors
points(anchors, rep(y_interval, length(anchors)), pch = 21, bg = "white", cex = 1.3)
text(anchors, rep(y_interval + 0.6, length(anchors)), labels = paste0("A", seq_along(anchors) - 1), cex = 0.9)

# Measurements (irregular)
segments(0, y_labs, t_max, y_labs)
points(labs_t, rep(y_labs, length(labs_t)), pch = 16, cex = 0.9)
text(0, y_labs + 0.55, "Labs (LDL/HDL)", pos = 4)

segments(0, y_bp, t_max, y_bp)
points(bp_t, rep(y_bp, length(bp_t)), pch = 15, cex = 0.9)
text(0, y_bp + 0.55, "Vitals (SBP/DBP)", pos = 4)

# Events
segments(0, y_events, t_max, y_events)
points(evt_mi, y_events, pch = 4, cex = 1.4, lwd = 2)
text(0, y_events + 0.55, "Clinical events", pos = 4)
text(evt_mi, y_events + 0.55, "MI", pos = 4)

# Follow-up end vs death
abline(v = followup_end, lty = 2)
text(followup_end + 0.15, 0.30, "follow-up ends", srt = 90, adj = 0, cex = 0.85)

abline(v = death_time, lty = 3)
text(death_time + 0.15, 0.30, "death", srt = 90, adj = 0)


## ----ehr_load-----------------------------------------------------------------
ehr <- fluxASCVD:::ascvd_make_example_ehr(n_entities = 50, seed = 123)


## ----ehr_tables, echo=FALSE, results='asis'-----------------------------------
# For display, show two example entities across each longitudinal table
example_ids <- as.character(sort(unique(ehr$entities$entity_id))[1:2])

entities_2 <- ehr$entities[ehr$entities$entity_id %in% example_ids, , drop = FALSE]
labs_2     <- ehr$labs[ehr$labs$entity_id %in% example_ids, , drop = FALSE]
vitals_2   <- ehr$vitals[ehr$vitals$entity_id %in% example_ids, , drop = FALSE]
events_2   <- ehr$events[ehr$events$entity_id %in% example_ids, , drop = FALSE]
meds_2     <- ehr$meds[ehr$meds$entity_id %in% example_ids, , drop = FALSE]

knitr::kable(entities_2, caption = "Patients (one row per entity)")
knitr::kable(labs_2,     caption = "Labs (LDL/HDL) for two example entities")
knitr::kable(vitals_2,   caption = "Vitals (SBP/DBP) for two example entities")
knitr::kable(events_2,   caption = "Clinical events for two example entities")
knitr::kable(meds_2,     caption = "Medications for two example entities")


## ----time_mapping-------------------------------------------------------------
ts <- fluxCore::time_spec(unit = "weeks")

example_ids <- head(ehr$entities$entity_id, 2)


## ----prepare_library----------------------------------------------------------
library(fluxPrepare)


## ----prepare_observations-----------------------------------------------------
obs <- prepare_observations(
  tables = list(
    labs   = ehr$labs,
    vitals = ehr$vitals
  ),
  specs = list(
    labs = list(
      id_col   = "entity_id",
      time_col = "obs_date",
      vars     = c("ldl", "hdl"),
      group    = "labs"
    ),
    vitals = list(
      id_col   = "entity_id",
      time_col = "obs_date",
      vars     = c("sbp", "dbp"),
      group    = "vitals"
    )
  ),
  time_spec = ts
)

obs |>
  dplyr::filter(entity_id %in% example_ids) |>
  head(10) |>
  knitr::kable()


## ----prepare_events-----------------------------------------------------------
events <- prepare_events(
  events    = ehr$events,
  id_col    = "entity_id",
  time_col  = "event_date",
  type_col  = "event",
  time_spec = ts
)

events |>
  dplyr::filter(entity_id %in% example_ids) |>
  head(10) |>
  knitr::kable()


## ----prepare_splits-----------------------------------------------------------
set.seed(1)

splits_raw <- data.frame(
  entity_id = ehr$entities$entity_id,
  split = sample(
    c("train", "test", "validation"),
    size = nrow(ehr$entities),
    replace = TRUE,
    prob = c(0.70, 0.15, 0.15)
  ),
  stringsAsFactors = FALSE
)

splits <- prepare_splits(splits_raw)

splits |>
  head(6) |>
  knitr::kable()


## ----followup-----------------------------------------------------------------
fu_obs <- obs |>
  dplyr::group_by(entity_id) |>
  dplyr::summarize(t_obs_min = min(time), .groups = "drop")

fu_evt <- events |>
  dplyr::group_by(entity_id) |>
  dplyr::summarize(t_evt_min = min(time), .groups = "drop")

fu_death <- events |>
  dplyr::filter(event_type == "death") |>
  dplyr::group_by(entity_id) |>
  dplyr::summarize(death_time = min(time), .groups = "drop")

followup <- splits |>
  dplyr::select(entity_id) |>
  dplyr::left_join(fu_obs, by = "entity_id") |>
  dplyr::left_join(fu_evt, by = "entity_id") |>
  dplyr::mutate(
    followup_start = pmin(t_obs_min, t_evt_min, na.rm = TRUE),
    followup_end   = followup_start + (9 * 52)
  ) |>
  dplyr::left_join(fu_death, by = "entity_id") |>
  dplyr::select(entity_id, followup_start, followup_end, death_time)

followup |>
  dplyr::filter(entity_id %in% example_ids) |>
  knitr::kable()


## ----event_process_settings---------------------------------------------------
event_settings <- spec_event_process(
  event_types     = c("MI", "stroke", "death"),
  split_on_groups = "vitals",
  segment_on_vars = "sbp",
  segment_rules   = segment_bins(sbp = c(-Inf, 120, 140, Inf)),
  candidate_times = "groups_or_vars",
  t0_strategy     = "followup_start",
  death_col       = "death_time"
)

event_settings


## ----build_ttv_event_process--------------------------------------------------
ttv_major <- build_ttv_event_process(
  events       = events,
  observations = obs,
  splits       = splits,
  spec         = event_settings,
  followup     = followup,
  time_spec    = ts
)

ttv_major |>
  dplyr::filter(entity_id %in% example_ids) |>
  head(12) |>
  knitr::kable()


## ----state_at_t0--------------------------------------------------------------
anchors <- ttv_major |>
  dplyr::select(entity_id, t0)

state_t0 <- reconstruct_state_at(
  anchors      = anchors,
  observations = obs,
  vars         = c("sbp", "dbp", "ldl", "hdl"),
  lookback     = 52,
  staleness    = 52
)

ttv_major_cov <- ttv_major |>
  dplyr::left_join(
    state_t0 |>
      dplyr::select(entity_id, t0, sbp, dbp, ldl, hdl),
    by = c("entity_id", "t0")
  )

ttv_major_cov |>
  dplyr::filter(entity_id %in% example_ids) |>
  head(8) |>
  knitr::kable()


## ----build_ttv_state----------------------------------------------------------
ttv_bp <- build_ttv_state(
  observations   = obs,
  splits         = splits,
  outcome_group  = "vitals",
  outcome_vars   = c("sbp", "dbp"),
  predictor_vars = c("sbp", "dbp", "ldl", "hdl"),
  followup       = followup,
  death_col      = "death_time",
  lookback       = 52,    ### these are defined in the 
  staleness      = 52,    ### model's time_unit (weeks)
  row_policy     = "drop_incomplete"
)

ttv_bp |>
  dplyr::filter(entity_id %in% example_ids) |>
  head(10) |>
  knitr::kable()
