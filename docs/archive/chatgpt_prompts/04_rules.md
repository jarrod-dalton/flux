# Collaboration and Workflow Rules

This document defines rules governing how work is conducted in this environment, particularly in collaborative sessions involving ChatGPT.

These rules exist to preserve correctness, prevent accidental drift, and ensure that architectural intent is not silently weakened over time.

They are procedural rather than conceptual.

---

## Purpose

The flux ecosystem is large, modular, and contract-driven. Effective collaboration requires discipline around:

- how changes are proposed
- how artifacts are exchanged
- how authority is enforced
- how state is preserved across threads

These rules apply to all non-trivial work in this environment.

---

## Mode separation

Work proceeds in distinct modes.

### Planning mode

For non-trivial changes, planning comes first.

In planning mode:
- propose a staged implementation plan
- explain design rationale
- identify risks and contract touchpoints
- do not write production code

No code is written until the plan is reviewed and approved.

---

### Implementation mode

Once a plan is approved, implementation may begin.

In implementation mode:
- produce complete, executable code only
- do not use placeholders or ellipses
- implement the simplest valid version if behavior is uncertain
- document limitations explicitly

Partial or speculative implementations are not acceptable.

---

## Document discipline

### Prompt corpus documents

The markdown files in the prompt corpus (`00_README.md` through `05_progress.md`) are authoritative.

Rules:
- do not overwrite these documents wholesale
- do not silently reword existing content
- do not remove content without explicit approval

Changes to these documents must be proposed explicitly and approved before being applied.

---

### Authority and conflict resolution

If there is a conflict between:
- prompt corpus documents
- code behavior
- prior assumptions

resolve it in the following order:
1. `03_contracts.md`
2. `02_packages.md`
3. `01_overview.md`
4. `04_rules.md`
5. `05_progress.md`

Assume the higher-authority document is correct.

---

## Package artifacts and file handling

### Package uploads

Source code is exchanged via package `.zip` files.

Rules:
- package `.zip` files are authoritative for implementation details
- read uploaded packages carefully before proposing changes
- do not assume access to package contents unless explicitly uploaded

Only upload packages relevant to the task at hand. Ecosystem-wide uploads are reserved for coordinated upgrades (e.g., v1.3.0).

---

### Artifact reliability

If a downloadable artifact fails to retrieve correctly, prefer the following remedies, in order:

1. Rebuild locally from the working directory, when possible  
2. Rebuild and re-upload the artifact under a new patch version with no semantic changes  
3. Provide a minimal patch or diff plus a file manifest to apply locally  

Do not proceed on the assumption that a failed artifact was “close enough.”

---

## Versioning discipline

The ecosystem follows semantic versioning with coordinated discipline across packages.

Rules:
- patch releases fix bugs or enforce invariants
- minor releases introduce conceptual or cross-package capabilities
- major releases change core semantics

Coordinated changes across packages require coordinated version bumps.

---

## Assumptions and error handling

If something feels incorrect:
1. assume a contract has been violated, or  
2. assume a test is missing  

Do not weaken invariants to accommodate convenience or expediency.

Errors should surface problems, not hide them.

---

## ChatGPT behavior expectations

When working in this environment, ChatGPT must:

- treat the prompt corpus as ground truth
- avoid inventing undocumented APIs or semantics
- avoid summarizing or skipping required context
- ask for clarification when uncertainty affects correctness
- prefer conservative, explicit interpretations over clever ones

Correctness and fidelity take precedence over brevity or stylistic polish.


---

## Vignettes

- Vignettes are intended to be educational. 
- Vignettes should prioritize clarity of mechanics over code reuse.
- Helper functions should be avoided for all but trivial situations that are not relevant to the learning.
- Key modeling steps must be visible to the reader. Nothing out of left field.
- Wherever possible, try to avoid the urge to use advanced stats or computer science jargon that the developer may share with you in the thread. (This is not always possible, so explain key terms that are not broadly familiar to an educated clinical research/biostats audience.)
