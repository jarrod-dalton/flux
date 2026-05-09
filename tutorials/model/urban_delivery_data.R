# ==============================================================================
# Urban Food Delivery — Synthetic Operational Data Generator
# ==============================================================================
#
# Generates a realistic synthetic operational log for a delivery fleet.
# Produces the raw data that fluxPrepare ingests in Tutorial 04.
#
# Output: a list with five data frames:
#   $couriers  - courier registry (entity_id, vehicle_type, home_zone)
#   $battery   - irregular battery readings (entity_id, time, battery_pct)
#   $weather   - hourly weather readings (station_id, recorded_at, temp_c,
#                wind_kph, humidity_pct) — station_id maps to courier home_zone
#   $events    - delivery completion events (entity_id, time, event_type)
#   $shifts    - shift-level follow-up windows (entity_id, shift_id,
#                shift_start, shift_end) — POSIXct timestamps
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
#' @return A list with components: couriers, battery, weather, events, shifts.
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

  # -- Simulate shifts using the delivery model --
  bundle <- delivery_bundle(params)
  eng    <- fluxCore::Engine$new(bundle = bundle)
  schema <- delivery_schema()

  shift_length <- if (!is.null(params$shift_length_hours)) {
    as.numeric(params$shift_length_hours)
  } else {
    8
  }

  all_obs    <- vector("list", n_couriers * n_shifts)
  all_events <- vector("list", n_couriers * n_shifts)
  all_fu     <- vector("list", n_couriers * n_shifts)
  idx        <- 0L

  for (i in seq_len(n_couriers)) {
    courier_id <- couriers$entity_id[i]
    zone       <- couriers$home_zone[i]

    for (s in seq_len(n_shifts)) {
      idx <- idx + 1L

      # Shift start in continuous hours; first shift starts at hour 0
      shift_start_hours <- (s - 1) * (shift_length + shift_gap)

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
      out <- eng$run(entity, max_events = 500, return_observations = TRUE)

      # -- Extract events (delivery completions only, for the event process) --
      ev <- out$events
      if (!is.null(ev) && nrow(ev) > 0L) {
        delivery_rows <- ev[ev$event_type == "delivery_completed", , drop = FALSE]
        if (nrow(delivery_rows) > 0L) {
          all_events[[idx]] <- data.frame(
            entity_id  = courier_id,
            time       = fleet_origin + delivery_rows$time * 3600,
            event_type = "delivery_completed",
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
  events   <- do.call(rbind, Filter(Negate(is.null), all_events))
  shifts   <- do.call(rbind, Filter(Negate(is.null), all_fu))

  rownames(battery) <- NULL
  rownames(events)  <- NULL
  rownames(shifts)  <- NULL

  # -- Weather observations (hourly, one station per zone) --
  # Deliberately uses different column names (station_id, recorded_at)
  # to demonstrate how specs map heterogeneous tables.
  total_hours <- n_shifts * (shift_length + shift_gap)
  weather_times <- seq(0, total_hours, by = 1)   # hourly readings
  zone_stations <- c(urban = "WX_urban", suburban = "WX_suburban",
                     rural = "WX_rural")

  weather <- do.call(rbind, lapply(names(zone_stations), function(z) {
    n <- length(weather_times)
    # Base temperature varies by zone; add smooth diurnal cycle + noise
    base_temp <- switch(z, urban = 22, suburban = 19, rural = 16)
    diurnal   <- 5 * sin((weather_times - 6) * pi / 12)
    temp      <- round(base_temp + diurnal + stats::rnorm(n, 0, 1.5), 1)

    data.frame(
      station_id  = zone_stations[[z]],
      recorded_at = fleet_origin + weather_times * 3600,
      temp_c      = temp,
      wind_kph    = round(pmax(0, stats::rnorm(n, mean = 15, sd = 6)), 1),
      humidity_pct = round(pmin(100, pmax(20, stats::rnorm(n, mean = 60, sd = 12))), 1),
      stringsAsFactors = FALSE
    )
  }))
  rownames(weather) <- NULL

  list(
    couriers = couriers,
    battery  = battery,
    weather  = weather,
    events   = events,
    shifts   = shifts
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
