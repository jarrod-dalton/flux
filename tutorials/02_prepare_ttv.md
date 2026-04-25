# fluxPrepare vignette

Maturity: validated

## Building train/test/validation datasets from irregular longitudinal tables

fluxPrepare exists for one job: to turn irregular, entity-level tables into **train/test/validation (TTV)** datasets whose columns have the *same meanings* the simulation ecosystem will later assume.

If you have ever watched an EHR-derived model fail quietly, it is usually not because the optimizer was bad. It is because the training data carried a hidden semantic mismatch: an outcome sneaked into predictors, an interval was defined inconsistently, a “baseline” meant two different things in two different steps, or eligibility rules were implemented as side effects instead of explicit logic.

This vignette is written for readers who are comfortable with longitudinal data and who need a disciplined mental model for dataset construction. It is not a tutorial. Code blocks are illustrative only and are marked `eval = FALSE`.

---

## Where Prepare fits in the flux ecosystem

The flux ecosystem distinguishes three layers that are easy to confuse when you live inside raw tables:

**Observations** are what you actually have: sparse, irregular measurements with timestamps, missingness, and shifting measurement cadence.

**State** is what the simulation engine evolves: schema-aligned variables defined “as-of” a particular time, with explicit rules for how those values are reconstructed.

**Derived variables** are context variables computed from state and history under strict temporal constraints, so that the same feature definition can be used during training and during simulation.

fluxPrepare lives at the boundary between the first layer and the second. It does not “clean data” in the generic sense; it creates model-ready datasets that respect the ecosystem’s contracts: one-step intervals, explicit time deltas, no implicit denominators, and no leakage.

---

## Core concepts and vocabulary

The words below are used precisely throughout fluxPrepare. If any of these terms feel slippery, pause here. Dataset construction gets people in trouble precisely because everyday meanings drift.

An **anchor time** is a time at which a row of a dataset is defined. In one-step datasets, anchors occur in pairs: a start anchor `t0` and an end anchor `t1`.

An **interval** is the open-ended story between anchors. In Prepare, an interval is always the transition from `t0` to `t1` and nothing more.

The **time delta** `deltat` is the explicit duration of the interval, defined as `t1 - t0` on the model time axis.

An **observation** is a recorded measurement at a time: a lab, vital sign, survey item, diagnosis code, procedure, or any other EHR artifact. Observations are not state.

**State** is a set of schema-defined variables interpreted “as-of” a particular time. State values are reconstructed from observations under explicit rules.

**As-of reconstruction** is the act of producing state at an anchor time using only information available strictly before (or, when explicitly allowed, at) that anchor time. Prepare’s tests enforce these constraints.

An **event** is a discrete occurrence that matters for modeling or censoring (for example, MI hospitalization, stroke, death, end of follow-up).

**Eligibility** is a model-defined condition for inclusion in a denominator or for being at risk during an interval. Prepare does not infer eligibility from missingness.

**Censoring** is a declaration that an outcome is not observable beyond a time. In Prepare, censoring is represented explicitly in tables and metadata; it is never inferred as a side effect.

**Provenance** is the record of how a reconstructed value was obtained: which observation source contributed, how stale it was, and whether it was absent. Prepare surfaces provenance so analysts can audit reconstruction decisions.

---

## Time in Prepare: numeric model time, calendar-friendly boundaries

The simulation ecosystem runs on a **numeric model time axis**. A model’s schema chooses a unit such as days, weeks, months (fixed-length), or years (fixed-length). Prepare speaks that numeric language internally.

Raw datasets, however, are usually timestamped in calendar time (`Date` or `POSIXct`). Prepare supports calendar inputs only at the dataset boundary. When you provide calendar times, you must supply a context object (`ctx`) describing how calendar time maps onto numeric model time.

```r
# eval = FALSE
ctx <- list(time = list(
  unit   = "days",
  origin = as.Date("1970-01-01"),
  zone   = "UTC"
))
```

This mapping is enforced via Core-owned utilities. The intent is narrow: allow you to align raw tables to the model’s time axis without embedding calendar semantics throughout the ecosystem.

Time-only inputs (for example `difftime` objects without dates) are intentionally out of scope.

---

## Input tables: required structure and contracts

Prepare expects a small number of table families. The package does not require a specific database schema, but it does require that each table family be expressed with the columns that make the semantics explicit.

### Splits

The splits table assigns each entity to exactly one of train/test/validation. This assignment is entity-level, not row-level. If an entity leaks across splits, you do not have a validation set.

```r
# eval = FALSE
raw_splits <- data.frame(
  pid   = c("a", "b", "c"),
  split = c("train", "test", "validation")
)

splits <- prepare_splits(
  raw_splits,
  id_col    = "pid",
  split_col = "split"
)
```

### Events

Events are discrete occurrences with a time and a type. Prepare can accept one table or multiple sources that are unified into a canonical event stream. The event stream is used both for outcomes and for censoring signals.

```r
# eval = FALSE
raw_events <- data.frame(
  pid  = c("a", "a", "b"),
  when = as.Date(c("1970-01-02", "1970-01-06", "1970-01-03")),
  type = c("visit", "mi", "visit")
)

events <- prepare_events(
  raw_events,
  id_col   = "pid",
  time_col = "when",
  type_col = "type",
  ctx      = ctx
)
```

### Observations

Observations are irregular measurements. Prepare accepts either a single data frame or a named list of data frames. Each observation row has an entity id, a time, a group label, and one or more measurement columns.

The group label exists because many modeling tasks are naturally group-anchored: “blood pressure visits” anchor intervals for BP transition models; “lab panels” anchor intervals for lab-driven transitions.

```r
# eval = FALSE
raw_labs <- data.frame(
  pid   = c("a", "a", "b", "b"),
  when  = as.Date(c("1970-01-02", "1970-01-06", "1970-01-03", "1970-01-07")),
  group = c("bp", "bp", "bp", "bp"),
  sbp   = c(120, 130, 110, 115)
)

observations <- prepare_observations(
  list(labs = raw_labs),
  id_col    = "pid",
  time_col  = "when",
  group_col = "group",
  ctx       = ctx
)
```

### Follow-up

Follow-up describes the time range over which an entity is under observation. It is used to construct censoring-aware intervals. Follow-up should not be treated as a polite suggestion. If an entity is not under follow-up, the absence of an event is not evidence of non-occurrence.

```r
# eval = FALSE
followup <- data.frame(
  entity_id     = c("a", "b"),
  followup_start = as.Date(c("1970-01-01", "1970-01-01")),
  followup_end   = as.Date(c("1970-01-11", "1970-01-11"))
)
```

---

## From observations to state: as-of reconstruction

As-of reconstruction is where most leakage happens in practice. It is tempting to treat a measurement “near” an anchor time as if it were observed at the anchor, or to peek into the future when a predictor is missing. Prepare is designed to prevent these habits.

When reconstructing state at `t0`, Prepare uses last-observation-carried-forward (LOCF) within explicit guardrails:

The **lookback window** limits how far into the past an observation may be used.

The **staleness constraint** marks values as unavailable if the most recent observation is too old.

The result is not only a reconstructed value but also provenance: did a value come from a recent observation, an old observation, or not at all?

This is where derived variables must be handled with care. Derived variables are computed from prior history only. Anchor-time leakage is an engine-level error in this ecosystem, and Prepare’s tests enforce it.

---

## One-step datasets: the only unit Prepare builds

Prepare builds one-step datasets because they match how simulation models in this ecosystem behave: at a time `t0`, the model proposes what happens next; at `t1`, the consequence is realized.

This contract is reflected mechanically in every dataset row:

Predictors are evaluated at `t0`.

Outcomes/labels are evaluated at `t1`.

`deltat` is explicit.

### Event-model datasets

An event-model dataset expresses the interval from a start policy (often baseline or current state) to either the first occurrence of an event type or censoring.

```r
# eval = FALSE
ttv_event <- build_ttv_event(
  events     = events,
  splits     = splits,
  ctx        = ctx,
  event_type = "mi",
  followup   = followup
)
```

### State-transition datasets

A state-transition dataset expresses consecutive within-entity intervals anchored by observation times in a chosen outcome group. Predictors are reconstructed at `t0` under the as-of rules described above; outcomes are taken from the next anchor at `t1`.

```r
# eval = FALSE
ttv_state <- build_ttv_state(
  observations   = observations,
  splits         = splits,
  ctx            = ctx,
  outcome_group  = "bp",
  outcome_vars   = c("sbp"),
  predictor_vars = c("sbp"),
  followup       = followup
)
```

Multi-step sequence construction is intentionally out of scope. If you want sequence models, Prepare’s outputs are meant to be the clean one-step building blocks from which sequences can be constructed in a controlled, explicit way.

---

## Derived variables and schema alignment

Prepare is not a feature factory. If a model requires a context feature such as “time since last visit” or “rolling mean SBP”, the recommended pattern is to define it as a schema-derived variable using Core machinery.

The reason is operational, not philosophical: a derived variable definition must be usable during training and during simulation. If you compute a feature ad hoc inside dataset construction, you have created two inconsistent definitions of the model’s inputs: one in training code and another (often implicit) in runtime simulation.

Prepare therefore integrates with schema-derived variable machinery and enforces strict temporal constraints so that derived variables are evaluated only from pre-anchor history.

---

## Specs, batch mode, and auditability

At small scale, it is possible to build a dataset “by hand.” At any real scale, that is a recipe for inconsistency. Prepare therefore asks you to declare your intent through specs and then build deterministically from those specs.

Specs are validated against the model schema at construction time. This prevents subtle mismatches from becoming silent errors later.

```r
# eval = FALSE
schema <- list(
  route_zone = list(
    type = "categorical",
    levels = c("urban", "suburban", "rural"),
    default = "urban",
    coerce = as.character
  ),
  sbp = list(type = "continuous", default = NA_real_, coerce = as.numeric),
  battery_pct = list(type = "continuous", default = NA_real_, coerce = as.numeric)
)

spec_bp <- spec_state(
  schema         = schema,
  outcome_group  = "bp",
  outcome_vars   = "sbp",
  predictor_vars = c("sbp"),
  name           = "Blood pressure (SBP)"
)

batch <- build_ttv_batch(
  observations = observations,
  events       = events,
  splits       = splits,
  specs        = list(spec_bp),
  followup     = followup,
  ctx          = ctx
)
```

Batch outputs are disk-backed and include metadata describing the spec and the reconstruction and censoring rules used. Filenames are derived from spec hashes to keep outputs deterministic and auditable.

---

## How Prepare connects to the rest of the ecosystem

Prepare is deliberately upstream of modeling and validation. Its outputs are meant to be used to train transition mechanisms that ultimately live inside model bundles, and to construct observed datasets that Validation can compare to simulated outputs.

Prepare does not define validation denominators. Instead, it produces datasets and metadata that make denominator decisions possible to audit. fluxValidation then expresses inclusion and exclusion logic explicitly as masks. The intent is that no one is “quietly” removed from a denominator because a join dropped rows or a missing value was interpreted as ineligibility.

This separation also keeps the simulation engine small. Core remains responsible for state, events, and time. Prepare is responsible for constructing training and observed datasets under strict temporal constraints. Validation is responsible for comparing like-with-like, with denominators made explicit.

---

## Common failure modes

Most user errors are not “bugs” so much as mismatched expectations. The patterns below are common.

Some users expect Prepare to discretize time into a grid. Prepare does not. If you need a grid, you must define it explicitly and own the consequences.

Some users expect missing outcomes to imply ineligibility. Prepare does not infer eligibility from missingness; eligibility must be stated explicitly.

Some users treat the absence of an event as evidence of non-occurrence without reference to follow-up. Prepare assumes follow-up defines what is observable.

Some users compute features using anchor-time or post-anchor information “just to get a model running.” This is leakage, and the ecosystem treats it as a contract violation.

---

## Closing note

Prepare is intentionally strict because it sits at the boundary where most modeling errors are born. If dataset construction feels inconvenient, it is usually because a hidden assumption is being forced into the workflow. The right response is almost never to weaken guardrails; it is to make the assumption explicit.
