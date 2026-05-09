# flux: Process-Explicit Simulation for Scientists

Maturity: stable

---

## What is flux?

flux is an ecosystem for building, running, and validating **process-explicit simulations** of entities that evolve over time under multiple, interacting mechanisms.

The motivating domain is health — patients whose lab values drift, whose blood pressure spikes at office visits, who experience acute events like heart attacks or strokes at unpredictable times, and who may be subject to treatment decisions that alter their future trajectory. But the architecture is deliberately general. Any system where an entity carries state, experiences discrete events from multiple concurrent processes, and evolves according to explicit rules is a flux model: delivery vehicles, supply chains, financial portfolios, ecological populations.

The core bet is this: **if you make processes, state, and decisions explicit, the rest of the analytical stack — preparation, forecasting, validation, orchestration, optimization — can be built on shared, auditable contracts rather than ad-hoc conventions.**

---

## The modeling approach

### Model-first, not data-first

Most applied work begins with a dataset and asks: "What patterns can I fit?" flux inverts this. You begin by asking: **"What processes must exist to generate data like this?"** — and then you build a simulation that embodies those processes. Data enters the picture when you train the probabilistic components of that simulation and when you validate its outputs against observed reality.

This is not anti-empirical. It is a commitment to making modeling assumptions visible. When a model fails, you can inspect which process was wrong, not just which coefficient was off.

### Entities and state

An **entity** is the fundamental unit of simulation. It has:

- **State**: a set of typed variables (blood pressure, location, battery level — whatever the domain requires) governed by a validated schema.
- **History**: a sparse log of every state change, indexed by time.
- **An event log**: the authoritative record of what happened and when.

An entity knows nothing about *dynamics*. It is pure state with a clock.

### Events and processes

Dynamics come from **processes** — named sources of events that propose "something could happen next at time *t*." A patient simulation might have three concurrent processes:

```
Process             Typical tempo        Example events
─────────────────── ──────────────────── ─────────────────────
Laboratory testing   every few months    LDL measurement, HDL measurement
Office visits        yearly              blood pressure reading, medication review
Clinical events      rare, state-driven  myocardial infarction, stroke, death
```

Each process proposes a candidate next event with a time. The simulation engine collects all proposals, selects the earliest (with deterministic tie-breaking), applies the corresponding state transition, and then asks processes to re-propose. This loop — **propose → select → transition → observe → repeat** — is the heartbeat of every flux simulation.

Events are not restricted to a shared clock. Processes run on their own tempos, and the engine interleaves them on a single timeline. This is what makes flux "process-explicit": you model each mechanism separately and let the engine weave them together, rather than forcing everything onto a fixed time grid.

### State transitions and partial updates

When an event fires, a **transition function** returns a set of state changes — and only those changes. If a lab event updates LDL and HDL but not blood pressure, the transition returns `{ldl: 118, hdl: 52}` and nothing else. The engine applies the patch, validates it against the schema, and records it.

State variables can be organized into **blocks** (e.g., a "blood pressure" block containing SBP and DBP) that are updated atomically. This enforces the invariant that related variables always change together — you cannot accidentally update SBP without DBP if the model says they are coupled.

### The engine

The **Engine** is the runtime that executes the propose-select-transition loop. It enforces:

- **Schema validation** on every state update.
- **Deterministic event selection**: earliest time wins; ties broken by lexicographic process ID.
- **Reproducibility**: given the same seed and inputs, the same trajectory results.

The engine does not know anything about a specific domain. It only knows how to run the loop on any conforming model.

### ModelBundle: portable dynamics

A **ModelBundle** packages the dynamics — propose, transition, stop, observe — into a single artifact. It is the answer to "what does this model do?" separated from "what entity is it running on?" and "how is the run configured?"

Bundles are plain collections of functions. They are authored in the host language (R today; Python planned), unit-tested independently, and composed with other bundles when needed.

---

## Decisions, policies, and actions

Many real systems involve **decisions** — moments where an external agent (a clinician, a dispatcher, an algorithm) chooses an action that alters the entity's future. flux makes these first-class:

- A **DecisionPoint** declares *where* in the simulation a decision can occur (e.g., "at every office visit, a statin prescription decision is available").
- A **Policy** is a function that proposes an action at a decision point, given the entity's current state and context.
- An **ActionEvent** is the resulting intervention injected into the timeline.
- A **TrajectoryRecord** captures the full decision trace: what was observed, what actions were considered, which was selected, and what happened next.

Decision points are declared in the model schema. If the schema has no decision points, the model runs as a pure generative process — no policy needed. This keeps the simplest use case (Level 1: just run the simulation) completely free of policy machinery.

When decision points are present, a policy function is invoked at each one. The policy sees the entity's state and returns an action (or `NULL` for "no intervention"). This separation means you can swap policies without changing the model: run the same patient under "standard of care" and "aggressive treatment" and compare trajectories.

---

## From single-entity to multi-entity: the simulation spectrum

flux is designed around a deliberate spectrum of simulation complexity:

```
                       Single model              Multiple models
                  ┌───────────────────────┬───────────────────────────┐
  Single entity   │  fluxCore             │  fluxOrchestrate          │
                  │  One entity, one       │  One entity, multiple     │
                  │  bundle, one engine    │  bundles sharing a        │
                  │  loop.                 │  timeline (e.g., chronic  │
                  │                        │  disease + hospital       │
                  │                        │  episodes).               │
                  ├───────────────────────┼───────────────────────────┤
  Multiple        │  fluxSim         │  fluxSim +           │
  entities        │  Many entities         │  fluxOrchestrate          │
                  │  sharing an            │  Multi-model agents in a  │
                  │  environment.          │  shared world.            │
                  │  ABM, policy eval,     │                           │
                  │  RL.                   │                           │
                  └───────────────────────┴───────────────────────────┘
```

### Single-entity simulation (fluxCore)

The base case. One entity, one model bundle, one engine. This is where you start, and for many analytical tasks — individual-level forecasting, scenario analysis, parameter sensitivity — it is all you need.

Even in the single-entity case, the simulation can be rich: multiple concurrent processes, stochastic transitions, decision points with policy callbacks, and full trajectory logging.

A **cohort run** (`run_cohort()`) scales this to many entities run independently with matched seeds, parameter draws, and stochastic replicates. Entities do not interact — each sees its own timeline.

### Multi-model orchestration (fluxOrchestrate)

Sometimes a single entity needs multiple models on the same timeline. A patient might have a chronic disease model (outpatient risk factors evolving over years) and a hospital episode model (acute care dynamics over days). These models share the entity's state and compete for the next event, but they are authored and tested separately.

**Orchestration** wraps multiple bundles into a single composite bundle that the engine runs as usual. It adds:

- **Eligibility gating**: only the hospital model proposes events while the patient is inpatient.
- **Priority encoding**: deterministic precedence when models propose simultaneous events.
- **Cross-model hooks**: state updates triggered by one model that affect another (e.g., discharge resets outpatient scheduling).

This is still single-entity — the entity just has a richer dynamics specification.

### Multi-entity ABM (fluxSim — future)

When entities interact — patients in a shared healthcare system competing for resources, delivery vehicles coordinating routes, agents in a market — you need **agent-based modeling (ABM)**.

In ABM, each entity (now called an **agent**) runs its own engine, but a shared **environment** mediates interactions:

- The environment carries world state visible to all agents (resource availability, weather, market prices).
- A **scheduler** aligns the time axes of multiple agents, selecting the globally next event across all of them.
- An **interaction function** propagates cross-agent effects (infection transmission, resource depletion, competitive displacement).

flux's approach to ABM is compositional: each agent is a standard fluxCore entity with a standard engine. The ABM layer orchestrates *when* each agent's engine steps forward and *what shared state* it sees. The agent's dynamics (propose, transition, stop) are unchanged — they simply receive environment signals through a standardized context.

---

## What are the modeling goals?

Different users come to process-explicit simulation with different objectives. flux supports several, and the tooling is organized around them:

### 1. Mechanistic representation

> "I want to explicitly represent how interacting processes generate the data I observe."

This is the foundational use case. You build a simulation that embodies your understanding of the system — which processes exist, how they interact, what drives event timing. The simulation becomes a testable scientific artifact: you can inspect it, challenge it, and improve it.

**Tools**: `fluxCore` (schema, bundle, engine), `fluxModelTemplate` (scaffolding for new models).

### 2. Prediction and forecasting

> "Given this entity's current state, what is the distribution of future trajectories?"

Run the simulation forward many times with different stochastic draws and parameter realizations. Summarize the resulting distributions. Compare against held-out observed data to validate calibration.

**Tools**: `fluxCore` (cohort runs), `fluxForecast` (streaming summaries, trajectory quantiles), `fluxValidation` (observed-vs-predicted comparisons with explicit masks and denominators).

### 3. Data preparation for probabilistic models

> "I need training datasets whose semantics match what the simulation will assume at runtime."

Real-world data is irregular and messy. flux provides disciplined tools for constructing train/test/validation datasets with explicit time semantics, as-of-time state reconstruction, and no implicit denominators or leaked future information.

**Tools**: `fluxPrepare` (observations, events, splits, intervals, state reconstruction).

### 4. Policy evaluation and counterfactual analysis

> "What would happen if we changed the treatment policy? How do outcomes compare?"

Run the same cohort of entities through alternative policies with matched seeds. The only difference between runs is the policy — stochastic paths are identical. Compare trajectory records to quantify the effect of policy changes.

**Tools**: `fluxCore` (decision points, policies, trajectory records), `fluxSim` (campaign runner, scenario comparison, counterfactual rollouts — future).

### 5. Decision optimization and reinforcement learning

> "Can we learn an optimal policy from simulated experience?"

Use the simulation as a training environment. Collect (state, action, reward, next-state) transitions across many episodes. Feed these to offline RL algorithms or policy gradient methods. The simulation provides the substrate; the optimization is external.

**Tools**: `fluxCore` (decision points, trajectory records), `fluxSim` (episodes, rollouts, reward utilities, policy wrappers — future).

### 6. Agent-based modeling

> "I need multiple interacting entities in a shared environment."

Scale from cohort-level (independent entities) to population-level (interacting agents). Model resource competition, transmission dynamics, market behavior, or any setting where one entity's actions affect another's future.

**Tools**: `fluxCore` (entity, engine), `fluxSim` (environment, ABM scheduler, interaction functions — future).

---

## The ecosystem at a glance

| Package | Role |
|---|---|
| **fluxCore** | Entity, schema, engine, event loop, decision points, trajectory records, cohort runs. The foundation everything else builds on. |
| **fluxPrepare** | Turn irregular longitudinal data into model-ready train/test/validation datasets with explicit time semantics. |
| **fluxValidation** | Compare observed data against simulation outputs using explicit masks, denominators, and matching estimands. |
| **fluxForecast** | Streaming summaries, trajectory quantiles, and event probability surfaces from simulation outputs. |
| **fluxOrchestrate** | Compose multiple model bundles on a single entity timeline with eligibility gating and priority control. |
| **fluxModelTemplate** | Skeleton for authoring new model packages that follow ecosystem conventions. |
| **fluxSim** | *(Future)* Multi-entity ABM, policy campaigns, counterfactual comparison, RL data collection. |

---

## Tutorial roadmap

The tutorials that follow this introduction move from concepts to working code. Each builds on the previous, but they can also be read independently if you already have the prerequisite context.

| # | Tutorial | What you learn |
|---|---|---|
| 01 | [Core engine scaffold](01_core_engine_scaffold.md) | Entity, schema, ModelBundle, Engine. Build and run a simulation from scratch. Variable blocks, batch cohort runs, policy/intervention layering. |
| 02 | [Cohort simulation and forecasting](02_cohort_forecast.md) | Scale to many entities with `run_cohort()`. Use fluxForecast to compute event-probability curves and trajectory quantiles. |
| 03 | [Decisions and policy](03_decisions_policy.md) | Add DecisionPoints to a model. Author and compare policies. Capture trajectory records for downstream analysis. |
| 04 | [Data preparation and model training](04_data_preparation_and_model_training.md) | Use fluxPrepare to turn irregular longitudinal records into model-ready TTV datasets, then fit and wire models into a ModelBundle. |
| 05 | [Validation](05_validation.md) | Build observation grids, define at-risk denominators, and compare predicted vs. observed event risk using fluxValidation. |

**Recommended order for newcomers**: Read this page first, then work through 01 → 02 → 03 → 04 → 05 in sequence.
