# Overview of the flux Ecosystem

The **flux** ecosystem is a modular, event-driven simulation framework for modeling entity-level processes over time.

It is designed to support scientifically serious simulation work where clarity of assumptions, reproducibility of results, and auditability of logic are more important than convenience or brevity.

This document describes **what flux is**, **what it is for**, and **the modeling philosophy that underlies its design**. It does not define implementation details or hard rules; those are specified elsewhere.

---

## Purpose and scope

flux exists to support simulation-based reasoning in clinical and population health research, particularly in settings where:

- entities experience events over time
- state evolves as a result of those events
- multiple stochastic realizations are required
- outcomes must be summarized, validated, and compared to observed data
- downstream analyses must be reproducible and auditable

The ecosystem is intentionally general. It is not tied to a specific disease, care setting, or statistical model. Disease-specific logic lives in model packages built on top of the core infrastructure.

flux is **not**:
- a machine learning platform
- an electronic health record (EHR) ETL system
- a real-time simulation engine
- a visualization or dashboarding tool

Its purpose is to provide a disciplined foundation for building and evaluating entity-level simulation models.

---

## Modeling ethos

The design of flux is guided by a small number of core principles.

### Patients as stateful processes

Patients are represented as **stateful stochastic processes evolving over time**.

At any point in a simulation, a entity has:
- a well-defined state
- a current simulation time
- a history of realized events

State changes occur only through events. There are no continuous trajectories or implicit interpolation between events.

This framing makes explicit the causal structure of the model and forces all changes in entity state to be justified.

---

### Event-driven simulation

Simulation advances by proposing and realizing discrete events.

Each event represents a potential future transition in entity state, proposed at a specific candidate time based on the current state and model context. At each step, one and only one event is realized, its state transition is applied, and simulation time advances to the time of that event.

Although flux is event-driven, it is not limited to a single, monolithic discrete event process. The framework supports orchestration of multiple event-generating processes operating concurrently over a shared entity-level time axis. Each process independently proposes candidate future events, which are then arbitrated deterministically.

Event times are not assumed to follow a uniform schedule or global clock. Instead, model authors define explicit stochastic mechanisms that generate candidate event times (`time_next`) conditional on entity state and context. The resulting event sequence emerges from the interaction of these processes rather than from a fixed temporal structure.

This design allows flux to represent complex entity trajectories composed of overlapping disease processes, care contexts, and interventions, while preserving deterministic resolution and reproducibility.

---

### Separation of concerns

The ecosystem is intentionally split into narrowly scoped packages.

Broadly:
- **Core** owns simulation mechanics and semantics
- **Model packages** define disease- or process-specific logic
- **Prepare** handles construction of model-ready datasets from raw data
- **Forecast** summarizes simulated outputs
- **Validation** compares simulated outputs to observed data
- **Orchestrate** coordinates multiple models over a shared timeline

Each package is conservative in what it does and explicit in what it refuses to do.

Correct behavior emerges from **composition**, not from large, monolithic components.

---

### Explicit semantics and auditability

flux favors explicitness over convenience.

Key design choices reflect this:
- simulation time is explicit and monotone
- run structure and ordering are fixed and enforced
- denominators in validation are defined by explicit masks
- dataset construction rules are recorded as metadata
- determinism is preferred to randomized tie-breaking

These choices make it possible to explain, audit, and reproduce results long after a model was built.

---

## Capabilities and workflows

At a high level, the ecosystem supports the following workflows:

1. **Model development**
   - Define entity state and events
   - Implement disease or process logic
   - Run forward simulations

2. **Dataset construction**
   - Align raw observations to model semantics
   - Reconstruct state at anchor times
   - Build one-step training, test, and validation datasets

3. **Forecasting**
   - Estimate risks and survival quantities
   - Aggregate across simulations and parameter draws
   - Condition on eligibility or follow-up status

4. **Validation**
   - Align simulated outputs to observed data
   - Define explicit denominators
   - Compute validation metrics without hidden exclusions

5. **Orchestration**
   - Coordinate multiple models over a shared entity timeline
   - Enforce eligibility and arbitration rules
   - Preserve deterministic behavior

These workflows are supported by different packages, but share common contracts and semantics.

---

## Intended audience

flux is intended for users who are comfortable reasoning about:

- stochastic processes
- event-driven systems
- longitudinal data
- simulation-based inference

It assumes a willingness to engage with explicit rules and constraints in exchange for clarity and robustness.

Users seeking a black-box simulator or a minimal-code solution will likely find the ecosystem restrictive by design.

---

## Relationship to the rest of the corpus

This overview provides orientation and context.

Detailed descriptions of individual packages are provided in **`02_packages.md`**.

Non-negotiable architectural and semantic rules are defined in **`03_contracts.md`**.

Rules governing collaboration and interaction in this environment are defined in **`04_rules.md`**.

Current status and future work are tracked in **`05_progress.md`**.
