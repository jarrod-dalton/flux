.onAttach <- function(libname, pkgname) {
  packageStartupMessage(
    "flux meta-package attached. Core packages installed: ",
    "fluxCore, fluxPrepare, fluxForecast, fluxValidation, fluxOrchestrate."
  )
}
