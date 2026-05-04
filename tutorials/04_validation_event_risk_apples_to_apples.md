---
title: "Event risk: apples-to-apples"
maturity: "validated"
output:
  rmarkdown::html_document:
    toc: true
    toc_depth: 3
    theme: null
    highlight: tango
vignette: >
  %\VignetteIndexEntry{Event risk: apples-to-apples}
  %\VignetteEngine{knitr::rmarkdown}
  %\VignetteEncoding{UTF-8}
---

<style>
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;line-height:1.55;margin:0 auto;max-width:980px;padding:24px;color:#111;}
pre,code{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace;}
pre{padding:12px;border-radius:8px;background:#f6f8fa;overflow-x:auto;}
</style>

## Goal

For events, an "apples-to-apples" comparison requires that *simulated* and *observed* risks use the same estimand.

`fluxForecast::event_prob()` is designed around a **fixed denominator (fixed cohort)** evaluated at a reference time:

- `t_ref = start_time` (default 0)
- Eligibility is evaluated once at `t_ref`.
- Runs that later stop follow-up remain in the denominator (a policy-style estimand).

To match that behavior on observed/test-set data, `fluxValidation` provides `compute_obs_risk(mode="policy")`.

## Two observed estimands

### 1) Policy / fixed-cohort (Forecast-compatible)

- Denominator: eligible at `t_ref`
- Numerator at time `t_k`: had the event by `t_k` (as observed)

### 2) Interval risk-set (KM-ish)

- Denominator: eligible within each interval `(t_{k-1}, t_k]`
- Numerator: event occurrence within the interval

Both are useful, but only the first is *directly comparable* to `fluxForecast::event_prob()`.

## Minimal worked example


``` r
library(fluxValidation)
```


``` r
vars <- list(data.frame(entity_id=c("p1","p2"), sex=c("F","M")))

events <- data.frame(
  entity_id=c("p1","p2"),
  event_time=c(0.5, 1.2),
  event_type=c("E","E"),
  stringsAsFactors = FALSE
)

obs <- build_obs_grid(vars, events=events, times=c(0,1,2), t0=0)

policy <- compute_obs_risk(obs, event="E", times=c(0,1,2), start_time=0, mode="policy")
interval <- compute_obs_risk(obs, event="E", times=c(0,1,2), start_time=0, mode="interval")

policy
```

```
##   time n_eligible n_events risk
## 1    0          2        0  0.0
## 2    1          2        1  0.5
## 3    2          2        2  1.0
```

``` r
interval
```

```
##   time n_eligible n_events risk
## 1    0          0        0   NA
## 2    1          2        1  0.5
## 3    2          2        1  0.5
```

Interpretation:

- In `policy` mode, the cumulative risk at `t=2` is 1.0 because both entities have experienced the event by time 2 (as observed), and the denominator is fixed at the eligible cohort at `t_ref`.
- In `interval` mode, the per-interval risks are 0.5 in both intervals because one event occurs in each interval.

## Validation wrapper

If you have simulated predictions as a `flux_event_prob` object (preferred), you can validate as:


``` r
res <- validate_event_risk(pred_flux_event_prob, obs, event="E", obs_mode="policy")
```

If you only have a `flux_forecast`, `validate_event_risk()` will adapt it internally:


``` r
res <- validate_event_risk(flux_forecast, obs, event="E", obs_mode="policy")
```

## When to use which mode

- Use `obs_mode="policy"` when you want **apples-to-apples** with `fluxForecast::event_prob()`.
- Use `obs_mode="interval"` when you want interval-specific risk-set comparisons (often useful for episode-scoped events when paired with `at_risk_e[k,i]`).
