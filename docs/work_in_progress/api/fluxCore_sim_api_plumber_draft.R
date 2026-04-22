# Draft/archived plumber API prototype originally shipped in fluxCore/inst.
# This file is intentionally kept in super-repo work-in-progress docs until
# a formal package-shipped API scaffold is designed and supported.
#
# To run from super-repo root:
#   plumber::plumb("docs/work_in_progress/api/fluxCore_sim_api_plumber_draft.R")
#   |> pr_run(port = 8000)

library(plumber)
library(fluxCore)

.store <- new.env(parent = emptyenv())

#* Create a new entity and engine
#* @post /sim/create
function(age0 = 55, miles0 = 10, time0 = 0) {
  id <- paste0("sim_", as.integer(Sys.time()))

  p <- Entity$new(
    init = list(age = as.numeric(age0), miles_to_work = as.numeric(miles0)),
    schema = default_entity_schema(),
    entity_type = "entity",
    time0 = as.numeric(time0)
  )

  eng <- Engine$new(
    provider   = PackageProvider$new(),
    model_spec = list(name = "default")
  )

  .store[[id]] <- list(entity = p, engine = eng)
  list(id = id, state = p$state(c("age","miles_to_work")), events = p$events)
}

#* Step one event
#* @post /sim/<id>/step
function(id) {
  obj <- .store[[id]]
  if (is.null(obj)) stop("Unknown sim id")

  out <- obj$engine$run(obj$entity, max_events = 1, return_observations = TRUE)

  .store[[id]] <- list(entity = out$entity, engine = obj$engine)
  list(state = out$entity$state(c("age","miles_to_work")), last_event = tail(out$events, 1))
}
