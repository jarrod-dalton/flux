# flux Architectural and Semantic Contracts

This document defines the **non-negotiable contracts** of the flux ecosystem.

Everything in this file is binding.  
Nothing in this file is advisory.

If behavior contradicts this document, the behavior is wrong.

If documentation or examples contradict this document, they are wrong.

If code contradicts this document, the code must change.

---

## 1. Core ownership and authority

### 1.1 Core as the single source of truth

`fluxCore` is the sole authority for:

- entity state semantics
- simulation time semantics
- event execution
- run structure and ordering
- determinism guarantees
- schema definition and validation

No other package may redefine, reinterpret, or bypass these concepts.

All packages must treat Core-owned concepts as **ground truth**.

---

### 1.2 Schema ownership

Entity schemas are owned by Core.

Rules:
- schema structure, validation, and derived-variable machinery live in Core
- other packages must call Core schema helpers
- no package may implement forked schema validation logic
- schema assumptions must not be embedded implicitly in downstream code

If schema-related logic diverges across packages, that is a contract violation.

---

## 2. Entity semantics

### 2.1 Entity as a stateful process

A entity is a **stateful stochastic process evolving over time**.

At any point in a simulation, a entity has:
- a schema-defined state
- a current simulation time
- a history of realized events

State changes occur only through realized events.

There is no continuous-time interpolation between events.

---

### 2.2 State vs engine metadata

Entity **state** consists exclusively of schema-defined variables.

Engine metadata includes:
- simulation time
- run identifiers
- execution bookkeeping

Rules:
- simulation time is not a state variable
- engine metadata must not be inferred from state
- state variables must not encode engine behavior

---

## 3. Time semantics (LOCKED)

### 3.1 Authoritative simulation time

Simulation time is represented by a single authoritative value:

```
entity$last_time
```

Rules:
- `entity$last_time` is owned by Core
- it is updated only when an event is realized
- all proposed events must satisfy `time_next >= entity$last_time`
- time must never move backward

Violations are engine errors, not recoverable conditions.

---

### 3.2 Numeric model time

Model time is numeric and calendar-agnostic.

Rules:
- Core, Forecast, Orchestrate, and model packages operate on numeric model time
- calendar time (Date/POSIXct) is permitted only in data-facing contexts
- translation between calendar time and model time must use Core utilities
- time-only inputs (without a date) are explicitly out of scope

Model authors define the interpretation of model time units via the schema.

---

## 4. Event semantics

### 4.1 Event-driven execution

Simulation advances by iterating:

1. propose candidate future events
2. select exactly one next event
3. apply its state transition
4. advance simulation time to the event time

Only one event is realized at a time.

---

### 4.2 Deterministic resolution

When multiple candidate events are proposed, resolution is deterministic.

Tie-breaking policy (engine-level):

1. smallest `time_next`
2. lexicographic ordering of `process_id`

Rules:
- no randomized tie-breaking
- ordering logic must be reproducible
- if priority matters, encode it explicitly in `process_id`

This property is required for reproducibility and parallel execution.

---

## 5. Run structure and ordering (LOCKED)

### 5.1 Definition of a run

A run is defined by:
- a entity
- a parameter draw
- a simulation replicate

Runs are independent and embarrassingly parallel.

---

### 5.2 Run index invariant

All simulation outputs are ordered:

```
entity_id → draw_id → sim_id
```

Rules:
- `run_id` is the canonical join key
- ordering must not be repaired downstream
- downstream packages may assume this ordering

This invariant enables sparse storage, modular processing, and deterministic reproducibility.

---

## 6. Death and follow-up semantics

### 6.1 Death

Rules:
- `alive == FALSE` indicates death
- death is absorbing

---

### 6.2 Follow-up cessation

Recommended ecosystem convention:
- `alive == NA` with `active_followup == FALSE` indicates follow-up ended
- vital status is unknown beyond this point

Rules:
- Core treats these as ordinary state variables
- Core does not automatically halt simulation
- Core does not infer censoring or eligibility

Interpretation of follow-up cessation is the responsibility of downstream packages.

---

## 7. Forecasting contracts

### 7.1 Read-only semantics

Forecast:
- does not mutate entity state
- does not reinterpret Core semantics
- does not generate events

It may invoke Core to run simulations, but it does not influence event generation.

---

### 7.2 Eligibility and conditioning

Rules:
- eligibility is explicit and model-defined
- Forecast does not infer eligibility from missing values
- conditioning logic must be inspectable

---

## 8. Validation contracts

### 8.1 Mask-first denominators

Validation follows a mask-first philosophy.

Rules:
- no individual enters or leaves a denominator implicitly
- all inclusion/exclusion criteria are explicit boolean masks
- denominators must be auditable

---

### 8.2 Alignment responsibility

Validation:
- aligns simulated outputs to observed data
- does not reinterpret simulation semantics
- does not repair upstream inconsistencies

---

## 9. Dataset preparation contracts

### 9.1 One-step, interval-based datasets

Prepare constructs datasets representing transitions from `t0` to `t1`.

Rules:
- datasets are one-step only
- `deltat = t1 - t0` is explicit
- predictors are evaluated at `t0`
- responses are evaluated at `t1`

---

### 9.2 No time grids

Rules:
- dataset construction is anchor-time native
- no discretization is imposed by default
- time grids are not inferred implicitly

---

### 9.3 Reconstruction guardrails

As-of reconstruction must obey:

- explicit lookback windows
- staleness constraints
- strict pre-anchor history
- surfaced provenance

Leakage from post-anchor data is forbidden.

---

## 10. Orchestration contracts

### 10.1 Coordination only

Orchestration:
- does not mutate entity state
- does not advance time
- does not infer time from state

All state changes and time advancement occur through Core.

---

### 10.2 Optionality

Orchestration is optional.

Users whose needs are satisfied by a single model are not required to use it.

---

## 11. Error handling philosophy

If something feels incorrect, assume:
1. a contract has been violated, or
2. a test is missing

Do not weaken invariants to accommodate convenience.

Errors are signals, not inconveniences.
