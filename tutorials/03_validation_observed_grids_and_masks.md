---
title: "Observed grids and mask-driven denominators"
maturity: "validated"
output:
  rmarkdown::html_document:
    toc: true
    toc_depth: 3
    theme: null
    highlight: tango
vignette: >
  %\VignetteIndexEntry{Observed grids and mask-driven denominators}
  %\VignetteEngine{knitr::rmarkdown}
  %\VignetteEncoding{UTF-8}
---

<style>
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;line-height:1.55;margin:0 auto;max-width:980px;padding:24px;color:#111;}
pre,code{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace;}
pre{padding:12px;border-radius:8px;background:#f6f8fa;overflow-x:auto;}
</style>

## Goal

`fluxValidation` exists to compare *observed/test-set* entity data against simulation outputs on an **explicit forecast grid**.

The key idea is that *denominators are never inferred from NA values*. Instead, denominators are computed from explicit masks:

- `alive_mask[k,i]` in `{TRUE, FALSE, NA}`
- `followup_defined[k,i]` in `{TRUE, FALSE}`
- `model_defined[v,k,i]` in `{TRUE, FALSE}`
- `measured[v,k,i]` in `{TRUE, FALSE}` (optional for "measured-only" comparisons)

If you remember only one thing: **NA values are data; masks decide who is scored.**

## Observed input syntax

Observed state variables are provided as a list of wide-ish tables.

- *Static tables* must include `entity_id` and **no** `time` column.
- *Longitudinal tables* must include `entity_id`, `time`, and one or more measured variables.

This lets users naturally group variables that are measured together (e.g., SBP and DBP).


``` r
library(fluxValidation)
```


``` r
vars <- list(
  # Static variables
  data.frame(entity_id = c("p1","p2"), sex = c("F","M"), stringsAsFactors = FALSE),

  # A measurement panel ("bp")
  data.frame(
    entity_id = c("p1","p1","p2"),
    time = c(0, 1, 0),
    sbp = c(120, 130, 110),
    dbp = c(80,  85,  70),
    stringsAsFactors = FALSE
  )
)

# Forecast grid offsets (typically taken from a forecast object)
times <- c(0, 1, 2)

obs <- build_obs_grid(
  vars = vars,
  times = times,
  t0 = 0,
  default_window = 1
)
```

## LOCF-within-window gridding

By default, longitudinal variables are gridded using **LOCF within a lookback window**.

At grid time `t_k`, we look back `w` time units into `(t_k - w, t_k]` and carry forward the most recent observation.

- This affects **values** on the grid and the `measured` mask.
- It does **not** affect denominators unless you explicitly request `measured_only=TRUE`.


``` r
obs$measured$sbp
```

```
##       0    1     2
## p1 TRUE TRUE  TRUE
## p2 TRUE TRUE FALSE
```

``` r
obs$state$sbp
```

```
##      0   1   2
## p1 120 130 130
## p2 110 110  NA
```

## Variable-group windows via schema blocks

Window widths can be set globally and overridden using a named vector. Names may refer to:

- individual variables (e.g., `sbp = 2`)
- schema blocks/groups (e.g., `bp = 3` to apply to `sbp` and `dbp`)


``` r
schema <- list(
  sbp = list(type = "numeric", blocks = c("bp")),
  dbp = list(type = "numeric", blocks = c("bp"))
)

obs2 <- build_obs_grid(
  vars = vars,
  times = times,
  t0 = 0,
  schema = schema,
  default_window = 0,
  window = c(bp = 1)
)

obs2$state$sbp
```

```
##      0   1   2
## p1 120 130 130
## p2 110 110  NA
```

``` r
obs2$state$dbp
```

```
##     0  1  2
## p1 80 85 85
## p2 70 70 NA
```

## Denominators are masks

Downstream validators compute denominators from masks. For example, the default denominator at time `k` for variable `v` is:

- `alive_mask[k,i] == TRUE`
- AND `followup_defined[k,i] == TRUE`
- AND `model_defined[v,k,i] == TRUE`

Optionally, you can add measured-only logic with `measured[v,k,i] == TRUE`.

See the event vignette for a worked example that highlights how denominators must match the estimand used in forecasting.

### Variable-group windows (schema blocks)

You can set a global default lookback and override it for *groups* of variables.

For example, you might want a shorter window for blood pressure (measured frequently) and a longer window for HbA1c.

The `window=` argument accepts a named numeric vector. Names may be:

- individual variables (`sbp = 3`), or
- schema blocks/groups (`bp = 3`, `bmp = 12`, ...), where a block name expands to the variables in that block.

Precedence is:

1. per-variable override
2. per-block override
3. global `default_window`


``` r
# A minimal schema fragment: "bp" block includes sbp and dbp
schema <- list(
  sbp = list(type = "numeric", blocks = c("bp")),
  dbp = list(type = "numeric", blocks = c("bp"))
)

obs2 <- build_obs_grid(
  vars = vars,
  times = times,
  t0 = 0,
  schema = schema,
  default_window = 0,
  window = c(bp = 1)
)

obs2$state$sbp
```

```
##      0   1   2
## p1 120 130 130
## p2 110 110  NA
```

``` r
obs2$state$dbp
```

```
##     0  1  2
## p1 80 85 85
## p2 70 70 NA
```

## Mask-driven denominators

The package never uses `is.na(value)` to decide who enters a denominator. Instead, validators build a denominator mask like:

- `alive_mask == TRUE`
- AND `followup_defined == TRUE`
- AND (if supplied) `model_defined[v] == TRUE`
- AND (optional) `measured[v] == TRUE` when `measured_only=TRUE`

This is why downstream scoring remains stable even when observation cadence changes.

## Next

- For event risks and the meaning of "apples-to-apples" estimands, see **Event risk: apples-to-apples**.
