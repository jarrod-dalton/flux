# flux Prompt Corpus — Read Me First

This directory contains the authoritative prompt corpus for the **flux** ecosystem.

These files exist to establish shared understanding, enforce architectural contracts, and enable future work to resume without re-deriving intent, semantics, or rules.

They are not tutorials. They are not marketing material. They are not exploratory notes.

They are ground truth.

---

## How to use this corpus

You must read **every file in this directory in full**, in numeric order, before responding to any task related to the flux ecosystem.

Do not:
- skip files
- skim sections
- read only parts that appear relevant
- summarize instead of internalizing

Partial reading will lead to incorrect assumptions.

---

## Reading order

Read the files in the following order:

1. **00_README.md** — how to read and interpret this corpus  
2. **01_overview.md** — what flux is, and why it exists  
3. **02_packages.md** — package-level responsibilities and workflows  
4. **03_contracts.md** — non-negotiable architectural and semantic rules  
5. **04_rules.md** — collaboration and interaction rules  
6. **05_progress.md** — current status and next steps  

Packages are presented before contracts to establish orientation.  
Contracts remain the highest authority for resolving conflicts.

---

## Authority hierarchy

If there is any conflict between files, resolve it using the following hierarchy (highest authority first):

1. **03_contracts.md**  
2. **02_packages.md**  
3. **01_overview.md**  
4. **04_rules.md**  
5. **05_progress.md**  

If there is any conflict between your prior knowledge and these files, **these files take precedence**.

---

## Required posture

When working with this corpus:

- Treat all stated contracts as binding.
- Do not weaken invariants to make code or examples “work.”
- If something appears inconsistent, assume either:
  - a contract has been violated, or
  - a test or rule is missing.

Do not invent new semantics or reinterpret existing ones without explicit approval.

---

## Scope

This corpus defines:
- architectural intent
- semantic contracts
- ownership boundaries
- collaboration discipline

It does not define:
- implementation details of every function
- the full contents of every package
- future features not explicitly listed

Concrete implementation details live in package source code.

During a working session, relevant package `.zip` files will be uploaded explicitly as needed, depending on the task at hand. When package artifacts are provided, they must be read carefully and treated as authoritative with respect to implementation details, provided they do not contradict the contracts defined in this corpus.

Do not invent APIs, behaviors, or semantics that are not supported by the provided documents and package artifacts.
