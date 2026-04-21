# flux ASCVD Tutorial – Vignette Plan (Annotated)

This document outlines the didactic structure of the ASCVD tutorial vignettes.
It is intended for internal planning and iteration, not end-user documentation.

The central unit of focus is the **flux ecosystem**.
ASCVD is used as a worked example throughout.

----------------------------------------------------------------
  VIGNETTE 0 — DONE
----------------------------------------------------------------
  Title: A Simulation Ecosystem for Complex Longitudinal Data

Status: COMPLETE

Purpose:
  - Orient new users to *why* the flux ecosystem exists.
- Motivate model-first thinking in the presence of irregular EHR data.
- Introduce the idea of multiple concurrent event processes and lenses.
- Provide a fully self-contained toy example model to make the ecosystem concrete.

Key concepts introduced:
  - Model-first vs data-first ethos
- Multiple event processes over a single entity time axis
(labs, office visits, clinical events)
- Time context (`ctx`) and time units
- Schema as the vocabulary of a model
- ModelBundle as a portable, inspectable artifact
- transition() as event-conditional state evolution
- PackageProvider as a registry for supplying bundles to the engine

What is *not* covered:
  - EHR-derived data
- Model fitting
- Validation, forecasting, or orchestration

Deliverable:
  - A runnable, readable vignette with two toy entities and transparent mechanics.

----------------------------------------------------------------
  VIGNETTE 1
----------------------------------------------------------------
  Title: Preparing Longitudinal EHR Data for Simulation (TTV Tables)

Purpose:
  - Introduce fluxPrepare.
- Show how messy, irregular EHR-style data are transformed into
model training / test / validation (TTV) tables.

Key learning objectives:
  - Understand the three canonical prepared inputs:
  - splits
- observations
- events
- Learn what a TTV table is and why it exists.
- See how time anchors and follow-up windows are made explicit.
- Understand how Prepare enforces consistency and auditability.

Concepts to emphasize:
  - “Raw-ish” EHR data vs model-ready tables
- Explicit index time and follow-up
- Alive vs under-follow-up distinctions
- No modeling yet — this is purely data preparation

Non-goals:
  - No fitting
- No lenses yet (single, simple lens only)

----------------------------------------------------------------
  VIGNETTE 2
----------------------------------------------------------------
  Title: Multiple Time Lenses and Concurrent Event Processes

Purpose:
  - Show how the *same* prepared EHR data can be viewed through
multiple time lenses for different modeling tasks.

Key learning objectives:
  - Understand why a single discretization of time is insufficient.
- Learn how to define multiple event processes:
  - labs (faster, measurement-driven)
- office visits (medium)
- clinical events (slower, outcome-driven)
- See how multiple TTV tables can coexist for one cohort.

Concepts to emphasize:
  - Lenses as explicit, reproducible choices
- Anchoring intervals on different event types
- Same raw data → different modeling representations
- Why this matters for joint simulation

Non-goals:
  - No model fitting yet
- No forecasting or validation

----------------------------------------------------------------
  VIGNETTE 3
----------------------------------------------------------------
  Title: Fitting Model Components and Building a ModelBundle

Purpose:
  - Show how trained models are inserted into the same ModelBundle
structure introduced in Vignette 0.

Key learning objectives:
  - Fit simple event-rate / hazard models from TTV tables.
- Understand how fitted components replace toy components
without changing bundle structure.
- Learn how model metadata and versioning matter.

Concepts to emphasize:
  - Separation of structure (bundle shape) from parameters (fits)
- Reusability of bundles
- Transparency of assumptions

Non-goals:
  - No evaluation yet
- No scenario comparison

----------------------------------------------------------------
  VIGNETTE 4
----------------------------------------------------------------
  Title: Forecasting Individual and Cohort Risk from Simulation

Purpose:
  - Demonstrate how simulation is used to generate *forecasts*,
not just single realizations.

Key learning objectives:
  - Run many simulation replicates for a fixed starting state.
- Estimate risk of outcomes over fixed horizons.
- Understand forecasting denominators (e.g., alive at horizon start).

Concepts to emphasize:
  - Forecasting vs simulation truth
- Monte Carlo uncertainty
- Individual vs cohort-level forecasts

This vignette is where:
  - “Risk at 1 year / 5 years” questions live
- Practical interpretation for clinicians and decision-makers begins

----------------------------------------------------------------
  VIGNETTE 5
----------------------------------------------------------------
  Title: Validation and Calibration with Explicit Masks

Purpose:
  - Show how simulated forecasts are compared to observed data.

Key learning objectives:
  - Understand why validation requires explicit denominators.
- Learn how masks define who is eligible for which comparison.
- Generate calibration plots and summary metrics.

Concepts to emphasize:
  - Validation is not an afterthought
- No silent dropping of entities
- Transparency over convenience

----------------------------------------------------------------
  VIGNETTE 6
----------------------------------------------------------------
  Title: Orchestrating Multiple Models Over a Single Entity Timeline

Purpose:
  - Demonstrate orchestration of multiple ModelBundles.

Key learning objectives:
  - Combine models operating at different resolutions
(e.g., chronic disease + hospitalization detail).
- Understand how Orchestrate coordinates bundles
without violating Core’s ownership of truth.

Concepts to emphasize:
  - Composition over monoliths
- Scenario comparison
- Scaling the ecosystem to complex use cases

----------------------------------------------------------------
  END OF PLAN
----------------------------------------------------------------
  