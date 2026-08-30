# ==============================================================================
# Controlled urban-delivery scenarios for Tutorial 03
# ==============================================================================
#
# These helpers keep dispatch timing and offer state predictable so Tutorial 03
# can isolate fluxCore's decision and action behavior. They reuse the courier
# schema and ModelBundle vocabulary defined in urban_delivery.R.
#

controlled_delivery_bundle <- function(offer_times = 1,
                                       offer_open = TRUE,
                                       offered_payload_kg = 4,
                                       shift_end = 8) {
  bundle <- delivery_bundle(params = list(shift_length_hours = shift_end))
  offer_times <- sort(as.numeric(offer_times))

  bundle$propose_events <- function(entity, param_ctx = NULL,
                                    process_ids = NULL,
                                    current_proposals = NULL) {
    n_seen <- sum(entity$events$event_type == "dispatch_check", na.rm = TRUE)
    next_offer <- n_seen + 1L
    out <- list()

    if (next_offer <= length(offer_times) &&
        offer_times[[next_offer]] > entity$last_time) {
      out$dispatch <- list(
        time_next = offer_times[[next_offer]],
        event_type = "dispatch_check"
      )
    }

    out$end_shift <- list(
      time_next = shift_end,
      event_type = "end_shift"
    )

    if (is.null(process_ids)) return(out)
    out[intersect(as.character(process_ids), names(out))]
  }

  bundle$transition <- function(entity, event, param_ctx = NULL) {
    if (identical(event$event_type, "dispatch_check")) {
      if (isTRUE(offer_open)) {
        return(list(
          dispatch_mode = "assigned",
          payload_kg = offered_payload_kg
        ))
      }
      return(list(dispatch_mode = "idle", payload_kg = 0))
    }

    if (identical(event$event_type, "end_shift")) {
      return(list(dispatch_mode = "idle"))
    }

    NULL
  }

  bundle$stop <- function(entity, event, param_ctx = NULL) {
    identical(event$event_type, "end_shift")
  }

  bundle
}

fresh_courier <- function(id = "courier_A", battery_pct = 80) {
  Entity$new(
    id = id,
    init = list(
      battery_pct = battery_pct,
      route_zone = "urban",
      payload_kg = 0,
      dispatch_mode = "idle"
    ),
    schema = delivery_schema(),
    entity_type = "courier",
    time0 = 0
  )
}
