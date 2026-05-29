## Requirements.md (review stage)

Version: 5.000 (Consolidated)  
Runtime Profile: `default`  
Author: Rolf Bercht  

> “BackgroundModifier is a PowerShell‑based solution that generates background images for both the Windows logon screen and the desktop.”  
> 

> “The solution follows the implementation methods, styles, and rules defined in the Implementation document, where these support fulfilling the functional requirements.”


---

## 1. Requirements and Scope

**Primary goal of the Requirements of the Solution:**  
Generate a unified, information‑rich background for **Windows logon** and **Desktop** background screens, encoding:

- OS version and update level  
- System identity and boot/logon times  
- Synthetic ESP/BCD/uEFI identity  
- Runtime metadata (script versions, timestamps, PowerShell version)

**Key Properties:**

- Deterministic, reproducible behavior  
- Clear separation of **source** vs. **runtime**  
- Git‑friendly, no runtime artifacts in the repo  
- Minimal, modular, tool‑based implementation 
- supports installation, debugging and logging 
- Explicit, documented entry points via symlinks for simplified user access to exposed functionality.

### Cross-Project Reuse Policy (2026-05-29)

- Reusable capabilities are to be structured as globally usable `.psm1` modules.
- BM is the preferred implementation source where overlap exists with BEM/INV.
- BEM/INV atoms are integrated for gaps in BM, especially for machine-descriptive inventory depth.
- Service-class contracts are retained and defined with PowerShell class-based interface style.

### Requirements Boundary Rule (2026-05-29)

- Requirements may reference implementation details only at atom/class-contract level.
- A class contract may define purpose, methods, input/output records, and error behavior.
- No inheritance is part of the class contract model.
- Composition is the preferred relation between classes/atoms.
- File names, folder paths, task names, command invocations, and module import wiring belong to `Implementation.md`.

Transitional note:
- Runtime wiring detail has been moved to `Implementation.md`.
- Any remaining concrete wiring statement in this file should be treated as legacy and migrated in future cleanup passes.

## 2. Functional Flow Model

The solution is defined as a two-stage functional pipeline:

1. Startup stage: collects machine/boot identity and updates shared state.
2. Logon stage: enriches user/session context, renders backgrounds, and applies them.

Functional constraints:

- Stage outputs are deterministic for equal inputs.
- Shared state may be updated by both stages without cross-stage data corruption.
- Startup stage must not require interactive user context.
- Logon stage must not recompute startup-only machine identity.

Implementation wiring, scheduling, paths, and script/module entry points are defined in `Implementation.md`.

## 3. Atom/Class Contract Groups

Required contract groups:

1. `CoreMachineInfo`
2. `CoreLogging`
3. `CoreValidation`
4. `CoreState`
5. `CoreOps`

Contract rules:

- Contracts are expressed via PowerShell class-based interface style.
- Service classes are kept.
- No inheritance is used.
- Composition is the standard interaction model.

## 4. End-User Top-Level Use Cases

The user-visible flow is defined at use-case level:

1. Install and verify prerequisites.
2. Collect startup identity snapshot automatically.
3. Render and apply desktop/logon backgrounds at user logon.
4. Diagnose issues using logs and verification tooling.
5. Re-run update/repair routines safely without destructive side effects.

Detailed procedural flow (task names, triggers, symlink strategy, runtime folder design) is implementation-owned and maintained in `Implementation.md`.

## 5. Versioning Policy

- Baseline release is `5.000`.
- Minor, non-breaking changes increment by `.001` (for example: `5.001`, `5.002`).
- Redesign-level changes increment by `.100` (for example: `5.100`, `5.200`).
- Module headers and documentation versions must be updated together with the repository version.
