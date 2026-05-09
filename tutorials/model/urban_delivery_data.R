# ==============================================================================
# Urban Food Delivery — Synthetic Operational Data Generator
# ==============================================================================
#
# Generates a realistic synthetic operational log for a delivery fleet.
# Produces the raw data that fluxPrepare ingests in Tutorial 04.
#
# Output: a list with six data frames:
#   $couriers  - courier registry (entity_id, vehicle_type, home_zone)
#   $battery   - irregular battery readings (entity_id, time, battery_pct)
#   $gps       - GPS pings (vehicle_id, ping_at, lat, lon, speed_kmh)
#                — deliberately uses different column names to showcase specs
#   $events    - fleet events (entity_id, time, event_type)
#                — includes dispatch_check and delivery_completed
#   $shifts    - shift-level follow-up windows (entity_id, shift_id,
#                shift_start, shift_end) — POSIXct timestamps
#   $weather   - fleet-wide hourly weather (time, temperature_c, precip_type)
#
# Usage:
#   source("tutorials/model/urban_delivery_data.R")
#   set.seed(42)
#   ops <- generate_delivery_log(n_couriers = 50, n_shifts = 10)
#
# No dependencies beyond base R and fluxCore (for Entity + Engine).
# ==============================================================================


#' Generate a synthetic delivery fleet operational log.
#'
#' @param n_couriers Number of delivery couriers in the fleet.
#' @param n_shifts   Number of shifts to simulate per courier.
#' @param params     Optional list of delivery model parameters (passed to
#'                   delivery_bundle). Use this to vary fleet behavior.
#' @param shift_gap  Hours between shifts (rest period). Default 16.
#' @param obs_rate   Mean battery observations per hour (Poisson process for
#'                   sensor pings). Default 2.
#' @param fleet_origin POSIXct timestamp for the fleet's first shift start.
#'                   Default is midnight UTC on 2026-01-05.
#' @param seed       Optional seed for full reproducibility. If NULL, uses
#'                   current RNG state.
#'
#' @return A list with components: couriers, battery, gps, events, shifts, weather.
generate_delivery_log <- function(n_couriers = 50,
                                  n_shifts = 10,
                                  params = list(),
                                  shift_gap = 16,
                                  obs_rate = 2,
                                  fleet_origin = as.POSIXct("2026-01-05 06:00:00", tz = "UTC"),
                                  seed = NULL) {

  if (!is.null(seed)) set.seed(seed)

  # -- Require the model definition to be already sourced --

  if (!exists("delivery_bundle", mode = "function")) {
    stop("delivery_bundle() not found. Source 'urban_delivery.R' before calling this function.",
         call. = FALSE)
  }

  # -- Courier registry --
  vehicle_types <- c("ebike", "scooter", "van")
  vehicle_probs <- c(0.50, 0.35, 0.15)
  zones         <- c("urban", "suburban", "rural")
  zone_probs    <- c(0.55, 0.30, 0.15)

  couriers <- data.frame(
    entity_id    = paste0("courier_", sprintf("%03d", seq_len(n_couriers))),
    vehicle_type = sample(vehicle_types, n_couriers, replace = TRUE, prob = vehicle_probs),
    home_zone    = sample(zones, n_couriers, replace = TRUE, prob = zone_probs),
    stringsAsFactors = FALSE
  )

  # -- Generate fleet-wide weather table --
  # Covers the full simulation window at hourly resolution.
  # Cleveland January: baseline ~2°C, daily cycle ±5°C, random-walk drift.
  # Precipitation via Markov chain (temporal correlation: stretches of rain/snow).

  max_shift_length <- 8
  total_hours <- n_shifts * (max_shift_length + shift_gap) + max_shift_length
  weather_hours <- seq(0, total_hours, by = 1)
  n_weather <- length(weather_hours)

  # Temperature: daily sinusoidal + slow random-walk drift
  daily_cycle  <- -5 * cos(2 * pi * weather_hours / 24)  # coldest at midnight
  drift        <- cumsum(stats::rnorm(n_weather, 0, 0.3))
  temperature  <- round(2 + daily_cycle + drift, 1)

  # Precipitation: Markov chain — P(stay same) = 0.85, P(switch) = 0.15
  precip <- character(n_weather)
  precip[1] <- "none"
  for (w in seq(2, n_weather)) {
    if (stats::runif(1) < 0.85) {
      precip[w] <- precip[w - 1]
    } else {
      # Switch: snow when cold, rain when warm
      if (temperature[w] < 0) {
        precip[w] <- sample(c("none", "snow"), 1, prob = c(0.4, 0.6))
      } else {
        precip[w] <- sample(c("none", "rain"), 1, prob = c(0.5, 0.5))
      }
    }
  }

  weather <- data.frame(
    time         = fleet_origin + weather_hours * 3600,
    temperature_c = temperature,
    precip_type   = precip,
    stringsAsFactors = FALSE
  )

  # -- Simulate shifts using the delivery model --
  bundle <- delivery_bundle(params)
  eng    <- fluxCore::Engine$new(bundle = bundle)
  schema <- delivery_schema()

  # Variable shift durations: mix of 4, 6, and 8 hour shifts
  shift_durations <- c(4, 6, 8)
  shift_duration_probs <- c(0.3, 0.3, 0.4)

  all_obs    <- vector("list", n_couriers * n_shifts)
  all_gps    <- vector("list", n_couriers * n_shifts)
  all_events <- vector("list", n_couriers * n_shifts)
  all_fu     <- vector("list", n_couriers * n_shifts)
  idx        <- 0L

  for (i in seq_len(n_couriers)) {
    courier_id <- couriers$entity_id[i]
    zone       <- couriers$home_zone[i]

    for (s in seq_len(n_shifts)) {
      idx <- idx + 1L

      # Variable shift duration
      shift_length <- sample(shift_durations, 1, prob = shift_duration_probs)

      # Shift start in continuous hours; first shift starts at hour 0
      shift_start_hours <- (s - 1) * (shift_length + shift_gap)

      # -- Look up weather at shift start --
      wx_idx <- findInterval(shift_start_hours, weather_hours)
      if (wx_idx < 1L) wx_idx <- 1L
      shift_temp   <- temperature[wx_idx]
      shift_precip <- precip[wx_idx]

      # Weather-adjusted delivery rate: slower in rain/snow
      delivery_rate_adj <- 1.0
      if (shift_precip == "rain")  delivery_rate_adj <- 1.0 / 1.4
      if (shift_precip == "snow")  delivery_rate_adj <- 1.0 / 3.0

      # Weather-adjusted battery drain: faster in cold
      cold_mult <- 1.0
      if (shift_temp < 0)      cold_mult <- 1.5
      else if (shift_temp < 5) cold_mult <- 1.2

      shift_params <- utils::modifyList(params, list(
        shift_length_hours         = shift_length,
        delivery_rate_base         = 1.0 * delivery_rate_adj,
        dispatch_battery_drop_mean = 2.5 * cold_mult,
        delivery_battery_drop_mean = 4.0 * cold_mult
      ))

      # Rebuild bundle with weather-adjusted params for this shift
      shift_bundle <- delivery_bundle(shift_params)
      shift_eng    <- fluxCore::Engine$new(bundle = shift_bundle)

      # Starting battery: not always 100 (varies by vehicle wear)
      start_battery <- min(100, max(60, stats::rnorm(1, mean = 95, sd = 8)))

      entity <- fluxCore::Entity$new(
        init = list(
          route_zone    = zone,
          battery_pct   = start_battery,
          payload_kg    = 0,
          dispatch_mode = "idle"
        ),
        schema      = schema,
        entity_type = "courier",
        time0       = shift_start_hours
      )

      # Run the shift
      out <- shift_eng$run(entity, max_events = 500, return_observations = TRUE)

      # -- Extract events (dispatch_check + delivery_completed) --
      ev <- out$events
      if (!is.null(ev) && nrow(ev) > 0L) {
        keep_types <- c("dispatch_check", "delivery_completed")
        event_rows <- ev[ev$event_type %in% keep_types, , drop = FALSE]
        if (nrow(event_rows) > 0L) {
          all_events[[idx]] <- data.frame(
            entity_id  = courier_id,
            time       = fleet_origin + event_rows$time * 3600,
            event_type = event_rows$event_type,
            stringsAsFactors = FALSE
          )
        }
      }

      # -- Generate battery observations (sensor pings at irregular intervals) --
      obs_df <- out$observations
      if (!is.null(obs_df) && nrow(obs_df) > 0L) {
        # Subsample: simulate sensor pings as a thinned version of the full log
        shift_end <- max(obs_df$time)
        shift_dur <- shift_end - shift_start_hours
        n_pings   <- max(1L, stats::rpois(1, lambda = obs_rate * shift_dur))

        # Draw ping times uniformly within the shift
        ping_times <- sort(stats::runif(n_pings, min = shift_start_hours, max = shift_end))

        # For each ping time, interpolate battery from the nearest prior observation
        battery_values <- vapply(ping_times, function(tp) {
          prior <- obs_df[obs_df$time <= tp, , drop = FALSE]
          if (nrow(prior) == 0L) return(start_battery)
          as.numeric(prior$battery_pct[nrow(prior)])
        }, numeric(1))

        # Add small sensor noise
        battery_values <- pmax(0, pmin(100, battery_values + stats::rnorm(n_pings, 0, 0.5)))

        all_obs[[idx]] <- data.frame(
          entity_id   = courier_id,
          time        = fleet_origin + ping_times * 3600,
          battery_pct = round(battery_values, 1),
          stringsAsFactors = FALSE
        )
      }

      # -- GPS pings (irregular, ~3 per hour) --
      # Uses different column names (vehicle_id, ping_at) to demonstrate
      # how specs handle heterogeneous source schemas.
      gps_dur   <- shift_length
      n_gps     <- max(1L, stats::rpois(1, lambda = 3 * gps_dur))
      gps_times <- sort(stats::runif(n_gps, min = shift_start_hours,
                                      max = shift_start_hours + gps_dur))

      base_lat <- switch(zone, urban = 41.50, suburban = 41.44, rural = 41.35)
      base_lon <- switch(zone, urban = -81.69, suburban = -81.54, rural = -81.39)

      all_gps[[idx]] <- data.frame(
        vehicle_id = courier_id,
        ping_at    = fleet_origin + gps_times * 3600,
        lat        = round(base_lat + cumsum(stats::rnorm(n_gps, 0, 0.01)), 5),
        lon        = round(base_lon + cumsum(stats::rnorm(n_gps, 0, 0.01)), 5),
        speed_kmh  = round(pmax(0, stats::rnorm(n_gps, mean = 18, sd = 8)), 1),
        stringsAsFactors = FALSE
      )

      # -- Follow-up window for this shift --
      shift_end_actual <- if (!is.null(ev) && nrow(ev) > 0L) {
        max(ev$time)
      } else {
        shift_start_hours + shift_length
      }

      # Convert to POSIXct timestamps
      shift_start_posix <- fleet_origin + shift_start_hours * 3600
      shift_end_posix   <- fleet_origin + shift_end_actual * 3600

      all_fu[[idx]] <- data.frame(
        entity_id   = courier_id,
        shift_id    = paste0(courier_id, "_shift_", s),
        shift_start = shift_start_posix,
        shift_end   = shift_end_posix,
        stringsAsFactors = FALSE
      )
    }
  }

  # -- Combine --
  battery  <- do.call(rbind, Filter(Negate(is.null), all_obs))
  gps      <- do.call(rbind, Filter(Negate(is.null), all_gps))
  events   <- do.call(rbind, Filter(Negate(is.null), all_events))
  shifts   <- do.call(rbind, Filter(Negate(is.null), all_fu))

  rownames(battery) <- NULL
  rownames(gps)     <- NULL
  rownames(events)  <- NULL
  rownames(shifts)  <- NULL

  list(
    couriers = couriers,
    battery  = battery,
    gps      = gps,
    events   = events,
    shifts   = shifts,
    weather  = weather
  )
}


#' Create train/test/validation splits for a set of couriers.
#'
#' Splits couriers (not shifts) into groups. All shifts for a given courier
#' belong to the same split — no data leakage across couriers.
#'
#' @param couriers   Data frame with an entity_id column.
#' @param train_frac Fraction of couriers in training set. Default 0.6.
#' @param test_frac  Fraction in test set. Default 0.2. Remainder is validation.
#' @param seed       Optional seed for split assignment.
#'
#' @return Data frame with entity_id and split columns.
generate_splits <- function(couriers,
                            train_frac = 0.6,
                            test_frac = 0.2,
                            seed = NULL) {
  if (!is.null(seed)) set.seed(seed)

  n <- nrow(couriers)
  ids <- couriers$entity_id

  # Shuffle

  perm <- sample(n)
  n_train <- floor(n * train_frac)
  n_test  <- floor(n * test_frac)

  splits <- character(n)
  splits[perm[seq_len(n_train)]] <- "train"
  splits[perm[n_train + seq_len(n_test)]] <- "test"
  splits[perm[(n_train + n_test + 1):n]] <- "validation"

  data.frame(
    entity_id = ids,
    split     = splits,
    stringsAsFactors = FALSE
  )
}
