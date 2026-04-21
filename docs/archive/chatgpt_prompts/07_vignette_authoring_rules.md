## Vignette Authoring Rules

The vignettes in this package are teaching tools first, and runnable code second.  
They are designed to help new users understand the **flux ecosystem**, its design philosophy, and how its components fit together.

The following rules govern how vignettes should be written.

---

### 1. The ecosystem is the central unit of focus
- Vignettes should emphasize the **ecosystem** (model-first design, multiple event processes, lenses, explicit time handling).
- Disease-specific models (e.g., ASCVD) are **examples**, not the main subject.
- Never assume the reader already understands the ecosystem or its motivation.

---

### 2. Model-first, not data-first
- Vignettes must introduce **model structure and assumptions before data**.
- Core components (schema, event processes, transition logic, ModelBundle structure) should be defined explicitly and visibly.
- Data are used to *inform or fit* models later, not to define what the model is.

---

### 3. No hidden helper magic
- Avoid helper functions that obscure important steps.
- If a helper is used, it must:
  - do only one obvious thing, and
  - immediately show what it returns.
- Prefer writing core objects (schemas, ModelBundles, transition functions) **directly in the vignette**, even if verbose.

---

### 4. Build objects in public, step by step
- Introduce complex objects (e.g., `ModelBundle`) conceptually first.
- Then construct them incrementally:
  - define subcomponents one-by-one,
  - explain their role,
  - assemble them into the final object at the end.
- A final tidy `bundle <- list(...)` should feel like a reveal, not a surprise.

---

### 5. Keep examples intentionally small and boring
- Use very small numbers of entities (often 1–2).
- Avoid distracting edge cases unless they are the explicit teaching goal.
- Toy hazard rates and parameters should produce *plausible but uneventful* trajectories.
- The goal is clarity, not realism.

---

### 6. Separate events from state
- Clinical events (MI, stroke, death, hospitalizations) are **events**, not state variables.
- Do not encode event history as state unless explicitly teaching derived variables.
- State variables represent entity attributes that evolve over time; events happen at times.

---

### 7. Multiple event processes must be explicit
- Distinguish conceptually between:
  - faster processes (e.g., labs),
  - medium processes (e.g., office visits),
  - slower processes (e.g., hospitalizations, death).
- Make clear that multiple processes operate simultaneously on the same entity time axis.

---

### 8. Code blocks must be readable and scoped
- Prefer multiple short code chunks over one long block.
- As a rule of thumb, keep chunks under ~30 lines.
- Immediately inspect or summarize important objects after creating them (`str(x, 2)`, selected fields, small tables).

---

### 9. Avoid jargon unless it is defined
- Do not rely on computer-science or internal ecosystem jargon.
- If a technical term is necessary, define it the first time it appears.
- Prefer plain language explanations of “what is happening” and “why it matters”.

---

### 10. Forecasting, validation, and orchestration are distinct
- Forecasting focuses on **estimating risk at fixed horizons** via repeated simulation.
- Validation focuses on **forecast accuracy**, with explicit denominators and masks.
- Orchestration focuses on **combining and comparing models** over a shared entity timeline.
- Do not collapse these concepts into a single vignette.

---

### 11. Each vignette has one primary learning objective
- State (implicitly or explicitly) what the reader should understand by the end.
- If a section does not advance that objective, remove it.
- Vignettes should feel like guided lessons, not reference manuals.

---

### 12. If something feels magical, it is a bug
- Readers should never wonder:
  - “Where did this object come from?”
  - “Why did this happen?”
  - “What assumptions were made here?”
- If they might, add narrative, reduce abstraction, or show the step explicitly.
