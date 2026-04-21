# Package-Level Architecture and Responsibilities

This document describes the role, scope, and intended use of each package in the **flux** ecosystem.

Each package is intentionally narrow in responsibility. No single package is meant to be “the system.” Correct behavior emerges from **composition**, guided by shared contracts and explicit ownership boundaries.

This document explains **what each package does**, **how it is typically used**, and **what it deliberately does not do**. Non-negotiable rules governing how packages interact are defined in `03_contracts.md`.

---

## fluxCore

### Role

`fluxCore` is the canonical simulation engine.

It defines the fundamental semantics of entity-level simulation, including how state evolves, how time advances, and how simulation runs are structured and ordered.

All other packages in the ecosystem either depend on Core directly or assume its guarantees implicitly.

### Responsibilities

Core is responsible for:

- defining the `Entity` object and entity state lifecycle
- managing simulation time
- executing event-driven simulation loops
- enforcing deterministic event resolution
- constructing and enforcing the canonical run index
- validating and managing entity schemas
- providing utilities that support other packages while preserving core semantics

### How users interact with Core

Users do not modify Core directly.

Instead, users build **new model packages** that depend on Core and implement disease- or process-specific logic on top of its interfaces. This pattern is demonstrated by `fluxASCVD` and `fluxModelTemplate`.

Core is intended to be stable, conservative, and shared across models. Model-specific behavior belongs in separate packages, not in Core itself.

### What Core does not do

Core deliberately does **not**:

- compute risks, hazards, or summaries
- define observational or validation semantics
- infer eligibility, censoring, or follow-up
- embed disease-specific logic
- coordinate multiple disease models

Core is conservative by design. Errors thrown by Core indicate contract violations rather than recoverable conditions.

---

## fluxForecast

### Role

`fluxForecast` provides a user-facing API for running simulations **via Core** and producing summaries of scientific interest.

It supports both execution of forward simulations and read-only post-processing of simulation outputs to compute quantities such as risks, survival curves, and aggregated outcomes across simulations and parameter draws.

### Responsibilities

Forecast is responsible for:

- invoking Core to run forward simulations when required
- computing time-indexed quantities of interest
- aggregating results across simulation replicates
- aggregating results across parameter draws
- supporting conditional summaries based on model-defined eligibility or follow-up

Forecast operates strictly on numeric model time.

### Design intent

Forecast does not mutate entity state, reinterpret Core semantics, or influence event generation.

Its role is to provide a stable, user-facing interface for answering questions about *what happened in the simulation*, not for deciding *what should happen next*.

---

## fluxValidation

### Role

`fluxValidation` provides a framework for comparing simulated outputs to observed data.

Validation is treated as a first-class modeling activity, not as an afterthought or ad hoc analysis.

### Responsibilities

Validation is responsible for:

- constructing observed-data grids aligned to simulation structure
- defining explicit validation denominators using boolean masks
- computing validation metrics without hidden exclusions
- adapting simulated outputs to observed data schemas
- supporting transparent, auditable comparisons

### Design intent

Validation follows a **mask-first philosophy**.

No individual enters or leaves a denominator implicitly. All inclusion and exclusion criteria are explicit and inspectable.

Detailed discussion of denominator construction, masking strategies, and common pitfalls is provided in the Validation package vignette.

Calendar time alignment is permitted where required to interface with observed data.

---

## fluxPrepare

### Role

`fluxPrepare` supports construction of **training, test, and validation (TTV)** datasets for model development.

It bridges the gap between raw, irregular observational data and the structured inputs required for simulation models.

### Responsibilities

Prepare is responsible for:

- canonicalizing entity-level split tables
- unifying heterogeneous event tables into a single event stream
- canonicalizing observation tables into a consistent format
- reconstructing entity state at anchor times under explicit rules
- constructing one-step, interval-based TTV datasets
- recording metadata and provenance for auditability
- supporting batch-mode, disk-backed dataset construction

Prepare explicitly distinguishes between:

- **observations**: raw, sparse, irregular data
- **state**: schema-aligned variables reconstructed at specific times

### Design intent

Prepare is **model-first**, not data-first.

It does not discretize time, infer multi-step trajectories, or perform ad hoc feature engineering. Its purpose is to ensure that datasets used for model training and validation are aligned with the semantics of the simulation engine.

---

## fluxOrchestrate

### Role

`fluxOrchestrate` coordinates multiple simulation bundles over a shared entity-level timeline.

It enables complex entity trajectories composed of multiple disease models, care contexts, or interventions.

### Responsibilities

Orchestrate is responsible for:

- managing which model bundles are active at a given time
- applying eligibility gating before event proposal
- collecting candidate events from active bundles
- resolving competing proposals deterministically
- passing approved events to Core for execution

### Design intent

Orchestration is intentionally thin and **optional**.

It is intended for advanced use cases that require coordination of multiple event-generating processes over a shared entity timeline. Users whose modeling needs are satisfied by a single model may never need to use Orchestrate.

Orchestrate does not:
- mutate entity state directly
- advance simulation time
- reinterpret model semantics

Its job is arbitration and coordination, not simulation.

---

## fluxASCVD

### Role

`fluxASCVD` is a concrete disease model implemented on top of the flux ecosystem.

It serves both as a scientifically meaningful model and as a reference implementation for model authors.

### Responsibilities

ASCVD is responsible for:

- defining disease-specific state variables
- implementing clinically meaningful event processes
- proposing events consistent with Core contracts
- demonstrating correct usage of Prepare, Forecast, and Validation

### Design intent

ASCVD is not privileged.

It obeys the same contracts as any other model and exists to demonstrate how the ecosystem is intended to be used in practice.

---

## fluxModelTemplate

### Role

`fluxModelTemplate` provides a scaffold for building new flux-compatible models.

It encodes the minimum structure required to interact correctly with the rest of the ecosystem.

### Responsibilities

The template is responsible for:

- illustrating correct schema definition
- demonstrating event proposal patterns
- showing how to integrate with Core utilities
- documenting expected interfaces and assumptions

### Design intent

The template exists to prevent accidental contract violations.

Code scaffolds are ordered and numbered, and the code is generously documented with comment blocks to guide teams through the model development process. The template is intentionally conservative and incomplete, serving as a starting point rather than a full-featured model.

---

## Relationship to other documents

This document describes **what each package does** and **how it is intended to be used**.

Hard rules governing time semantics, schema ownership, determinism, and interaction between packages are defined in **`03_contracts.md`**.

Collaboration rules and workflow discipline are defined in **`04_rules.md`**.

Current status and future work are tracked in **`05_progress.md`**.
