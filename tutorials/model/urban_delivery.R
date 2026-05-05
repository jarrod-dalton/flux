# ==============================================================================
# Urban Food Delivery Model
# ==============================================================================
#
# A complete flux model for simulating urban food delivery shifts.
#
# Domain: A fleet of delivery drivers (or drones) work shifts. During a shift,
# each agent receives dispatch assignments and completes deliveries. Battery
# depletes with each dispatch/delivery. The shift ends at a fixed time horizon
# or when explicitly triggered.
#
# This file defines:
#   - delivery_schema()    : state variable contract
#   - delivery_derived()   : computed views of state/history
#   - delivery_bundle()    : full ModelBundle for Engine$new(bundle = ...)
#
# Usage:
#   source("tutorials/model/urban_delivery.R")
#   library(fluxCore)
#   eng <- Engine$new(bundle = delivery_bundle())
#   out <- eng$run(entity, max_events = 500)
#
# No package installation required. No external dependencies beyond fluxCore.
# ==============================================================================


# --- Schema -------------------------------------------------------------------

#' State schema for an urban delivery agent.
#'
#' Variables:
#'   route_zone    - categorical: urban / suburban / rural
#'   battery_pct   - numeric [0, 100]: remaining battery percentage
#'   payload_kg    - numeric >= 0: current cargo weight
#'   dispatch_mode - categorical: idle / assigned / in_transit / completed
delivery_schema <- function() {
  list(
    route_zone = list(
      type     = "categorical",
      levels   = c("urban", "suburban", "rural"),
      default  = "urban",
      coerce   = as.character,
      validate = function(x) length(x) == 1L && x %in% c("urban", "suburban", "rural")
    ),
    battery_pct = list(
      type     = "numeric",
      default  = 100,
      coerce   = as.numeric,
      validate = function(x) length(x) == 1L && is.finite(x) && x >= 0 && x <= 100,
      blocks   = "vehicle_status"
    ),
    payload_kg = list(
      type     = "numeric",
      default  = 0,
      coerce   = as.numeric,
      validate = function(x) length(x) == 1L && is.finite(x) && x >= 0,
      blocks   = "vehicle_status"
    ),
    dispatch_mode = list(
      type     = "categorical",
      levels   = c("idle", "assigned", "in_transit", "completed"),
      default  = "idle",
      coerce   = as.character,
      validate = function(x) length(x) == 1L && x %in% c("idle", "assigned", "in_transit", "completed")
    )
  )
}


# --- Derived variables --------------------------------------------------------

#' Derived (computed) variables for the delivery model.
#'
#' These are snapshot-time computations — they do NOT mutate state.
#'
#' @param params Optional parameter list (uses low_battery_cutoff).
#' @return Named list of functions with signature f(entity, j, t).
delivery_derived <- function(params = list()) {
  cutoff <- if (!is.null(params$low_battery_cutoff)) {
    as.numeric(params$low_battery_cutoff)
  } else {
    20
  }

  list(
    # TRUE when battery is below the cutoff threshold
    low_battery = function(entity, j, t) {
      b <- tryCatch(as.numeric(entity$state("battery_pct")), error = function(e) NA_real_)
      if (!is.finite(b)) return(NA)
      b < cutoff
    },

    # Total deliveries completed up to event index j
    deliveries_completed = function(entity, j, t) {
      ev <- entity$events
      if (is.null(ev) || nrow(ev) == 0L) return(0L)
      if (!all(c("j", "time", "event_type") %in% names(ev))) return(0L)
      as.integer(sum(
        ev$event_type == "delivery_completed" & ev$j <= j & ev$time <= t,
        na.rm = TRUE
      ))
    },

    # Deliveries completed in the last 4 hours (rolling window)
    deliveries_last_4h = function(entity, j, t) {
      ev <- entity$events
      if (is.null(ev) || nrow(ev) == 0L) return(0L)
      if (!all(c("j", "time", "event_type") %in% names(ev))) return(0L)
      in_window <- ev$event_type == "delivery_completed" &
        ev$j <= j & ev$time > (t - 4) & ev$time <= t
      as.integer(sum(in_window, na.rm = TRUE))
    },

    # Most recent route zone (by event index)
    last_route_zone = function(entity, j, t) {
      h <- entity$hist$route_zone
      if (is.null(h) || length(h$j) == 0L) return(NA_character_)
      idx <- findInterval(j, h$j)
      if (idx <= 0L) return(NA_character_)
      as.character(h$v[[idx]])
    }
  )
}


# --- Propose events -----------------------------------------------------------

#' Propose candidate next events based on current state.
#'
#' Three concurrent processes:
#'   dispatch  - new dispatch assignment (exponential inter-arrival)
#'   delivery  - delivery completion (exponential, payload/battery-modulated)
#'   end_shift - deterministic shift-end time
delivery_propose <- function(entity, param_ctx = NULL, process_ids = NULL,
                             current_proposals = NULL) {
  params <- if (is.list(param_ctx) && is.list(param_ctx$params)) param_ctx$params else list()

  pnum <- function(name, default) {
    x <- params[[name]]
    if (is.null(x) || length(x) != 1L) return(default)
    x <- suppressWarnings(as.numeric(x))
    if (!is.finite(x)) default else x
  }

  t_now   <- entity$last_time
  s       <- entity$as_list(c("dispatch_mode", "payload_kg", "battery_pct"))
  mode    <- as.character(s$dispatch_mode)
  payload <- as.numeric(s$payload_kg);  if (!is.finite(payload)) payload <- 0

  battery <- as.numeric(s$battery_pct); if (!is.finite(battery)) battery <- 100

  # --- Rates (state-modulated) ---
  dispatch_base           <- pnum("dispatch_rate_base", 0.7)
  delivery_base           <- pnum("delivery_rate_base", 1.0)
  dispatch_idle_mult      <- pnum("dispatch_idle_multiplier", 1.2)
  delivery_payload_scale  <- pnum("delivery_payload_scale", 0.15)
  battery_multiplier      <- max(0.1, min(1.5, battery / 100))

  dispatch_rate <- dispatch_base *
    if (mode %in% c("idle", "completed")) dispatch_idle_mult else 0.7
  delivery_rate <- delivery_base * (1 + delivery_payload_scale * payload) * battery_multiplier
  if (payload <= 0 && mode %in% c("idle", "completed")) {
    delivery_rate <- delivery_base * 0.1
  }

  dispatch_rate <- max(1e-6, dispatch_rate)
  delivery_rate <- max(1e-6, delivery_rate)

  # --- Shift end (deterministic) ---
  shift_start        <- entity$events$time[[1]]
  shift_length_hours <- pnum("shift_length_hours", 8)
  shift_end_time     <- pnum("shift_end_time", shift_start + shift_length_hours)
  if (shift_end_time <= t_now) shift_end_time <- t_now + 1e-6

  out <- list(
    dispatch = list(
      time_next  = t_now + stats::rexp(1, rate = dispatch_rate),
      event_type = "dispatch_check"
    ),
    delivery = list(
      time_next  = t_now + stats::rexp(1, rate = delivery_rate),
      event_type = "delivery_completed"
    ),
    end_shift = list(
      time_next  = shift_end_time,
      event_type = "end_shift"
    )
  )

  if (is.null(process_ids)) return(out)
  process_ids <- unique(as.character(process_ids))
  out[intersect(process_ids, names(out))]
}


# --- Transition ---------------------------------------------------------------

#' Apply state updates for a realized event.
#'
#' dispatch_check      -> assigns new route, payload, drops battery
#' delivery_completed  -> reduces payload, drops battery, updates mode
#' end_shift           -> sets mode to idle (terminal)
delivery_transition <- function(entity, event, param_ctx = NULL) {
  params <- if (is.list(param_ctx) && is.list(param_ctx$params)) param_ctx$params else list()

  pnum <- function(name, default) {
    x <- params[[name]]
    if (is.null(x) || length(x) != 1L) return(default)
    x <- suppressWarnings(as.numeric(x))
    if (!is.finite(x)) default else x
  }

  if (identical(event$event_type, "dispatch_check")) {
    route_levels <- c("urban", "suburban", "rural")
    route_probs  <- params$route_zone_probs
    if (is.null(route_probs) || !is.numeric(route_probs) ||
        length(route_probs) != length(route_levels)) {
      route_probs <- c(0.55, 0.30, 0.15)
    }
    route_probs <- pmax(route_probs, 0)
    if (sum(route_probs) <= 0) route_probs <- c(0.55, 0.30, 0.15)
    route_probs <- route_probs / sum(route_probs)

    payload_mean     <- max(0.1, pnum("dispatch_payload_mean_kg", 3.0))
    payload_sdlog    <- max(0.05, pnum("dispatch_payload_sdlog", 0.35))
    battery_drop_mean <- max(0.1, pnum("dispatch_battery_drop_mean", 2.5))

    battery_now <- as.numeric(entity$as_list("battery_pct")$battery_pct)
    if (!is.finite(battery_now)) battery_now <- 100

    new_payload  <- as.numeric(stats::rlnorm(1, meanlog = log(payload_mean), sdlog = payload_sdlog))
    battery_drop <- as.numeric(stats::rexp(1, rate = 1 / battery_drop_mean))
    battery_next <- max(0, min(100, battery_now - battery_drop))

    return(list(
      route_zone    = sample(route_levels, size = 1, prob = route_probs),
      dispatch_mode = "assigned",
      payload_kg    = new_payload,
      battery_pct   = battery_next
    ))
  }

  if (identical(event$event_type, "delivery_completed")) {
    payload_sdlog     <- max(0.05, pnum("delivery_payload_sdlog", 0.45))
    delivery_mean     <- max(0.1, pnum("delivery_payload_mean_kg", 1.2))
    battery_drop_mean <- max(0.1, pnum("delivery_battery_drop_mean", 4.0))

    s <- entity$as_list(c("payload_kg", "battery_pct"))
    payload_now <- as.numeric(s$payload_kg);  if (!is.finite(payload_now)) payload_now <- 0
    battery_now <- as.numeric(s$battery_pct); if (!is.finite(battery_now)) battery_now <- 100

    delivered_kg <- min(payload_now, as.numeric(
      stats::rlnorm(1, meanlog = log(delivery_mean), sdlog = payload_sdlog)
    ))
    payload_next <- max(0, payload_now - delivered_kg)
    battery_drop <- as.numeric(stats::rexp(1, rate = 1 / battery_drop_mean))
    battery_next <- max(0, battery_now - battery_drop)
    mode_next    <- if (payload_next > 0) "in_transit" else "completed"

    return(list(
      dispatch_mode = mode_next,
      payload_kg    = payload_next,
      battery_pct   = battery_next
    ))
  }

  if (identical(event$event_type, "end_shift")) {
    return(list(dispatch_mode = "idle"))
  }

  NULL
}


# --- Stop ---------------------------------------------------------------------

#' Stop rule: end on terminal event or time horizon.
delivery_stop <- function(entity, event, param_ctx = NULL) {
  if (identical(event$event_type, "end_shift")) return(TRUE)

  if (is.list(param_ctx) && !is.null(param_ctx$params$time_horizon)) {
    horizon <- suppressWarnings(as.numeric(param_ctx$params$time_horizon))
    if (length(horizon) == 1L && is.finite(horizon) && entity$last_time >= horizon) {
      return(TRUE)
    }
  }

  FALSE
}


# --- Observe ------------------------------------------------------------------

#' Emit one observation row per realized event.
delivery_observe <- function(entity, event) {
  snap <- entity$snapshot(vars = c("route_zone", "battery_pct", "payload_kg", "dispatch_mode"))
  data.frame(
    time          = entity$last_time,
    event_type    = as.character(event$event_type),
    process_id    = if (!is.null(event$process_id)) as.character(event$process_id) else NA_character_,
    route_zone    = as.character(snap$route_zone),
    battery_pct   = as.numeric(snap$battery_pct),
    payload_kg    = as.numeric(snap$payload_kg),
    dispatch_mode = as.character(snap$dispatch_mode),
    stringsAsFactors = FALSE
  )
}


# --- Bundle assembly ----------------------------------------------------------

#' Assemble a complete ModelBundle for the urban delivery model.
#'
#' @param params Named list of model parameters. Merged with defaults.
#' @return A ModelBundle list suitable for Engine$new(bundle = ...).
#'
#' Default parameters:
#'   dispatch_rate_base        = 0.7   (dispatches per hour, base rate)
#'   delivery_rate_base        = 1.0   (deliveries per hour, base rate)
#'   dispatch_idle_multiplier  = 1.2   (rate multiplier when idle)
#'   delivery_payload_scale    = 0.15  (rate increase per kg payload)
#'   shift_length_hours        = 8     (shift duration in hours)
#'   dispatch_payload_mean_kg  = 3.0   (mean new-dispatch payload)
#'   dispatch_payload_sdlog    = 0.35  (lognormal sd for dispatch payload)
#'   dispatch_battery_drop_mean = 2.5  (mean battery % drop per dispatch)
#'   delivery_payload_mean_kg  = 1.2   (mean kg delivered per completion)
#'   delivery_payload_sdlog    = 0.45  (lognormal sd for delivery amount)
#'   delivery_battery_drop_mean = 4.0  (mean battery % drop per delivery)
#'   low_battery_cutoff        = 20    (threshold for low_battery derived var)
#'   route_zone_probs          = c(0.55, 0.30, 0.15) (urban/suburban/rural)
delivery_bundle <- function(params = list()) {
  default_params <- list(
    dispatch_rate_base         = 0.7,
    delivery_rate_base         = 1.0,
    dispatch_idle_multiplier   = 1.2,
    delivery_payload_scale     = 0.15,
    shift_length_hours         = 8,
    dispatch_payload_mean_kg   = 3.0,
    dispatch_payload_sdlog     = 0.35,
    dispatch_battery_drop_mean = 2.5,
    delivery_payload_mean_kg   = 1.2,
    delivery_payload_sdlog     = 0.45,
    delivery_battery_drop_mean = 4.0,
    low_battery_cutoff         = 20,
    route_zone_probs           = c(0.55, 0.30, 0.15)
  )

  params <- utils::modifyList(default_params, params)

  init_entity <- function(entity) {
    dv <- delivery_derived(params)
    if (length(dv) > 0L) {
      fluxCore::check_derived(entity, dv, replace = FALSE)
    }
    invisible(NULL)
  }

  list(
    params          = params,
    time_spec       = fluxCore::time_spec(unit = "hours"),
    schema          = delivery_schema(),
    event_catalog   = c("dispatch_check", "delivery_completed", "end_shift"),
    terminal_events = "end_shift",
    init_entity     = init_entity,
    propose_events  = delivery_propose,
    transition      = delivery_transition,
    stop            = delivery_stop,
    observe         = delivery_observe
  )
}
