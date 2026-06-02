# ModuleDocumentation

6.0.0
Profile: default
Author: Rolf Bercht

This document defines the module-level documentation contract for the BackgroundModifier solution.

## Scope

`ModuleDocumentation.md` describes how individual scripts and modules are documented, including:

- Module purpose and responsibilities
- Inputs, outputs, and side effects
- Dependencies on other modules
- Cross-Reference graph of modules, sections giving calling/calls and uses/includes
- internal call tree within each module
- Logging behavior and error handling expectations
- Versioning and changelog expectations at module level

## Position in Documentation Hierarchy

The repository documentation hierarchy is:

1. `Requirements.md` â€” expected functionality the solution must provide.
2. `Implementation.md` â€” how requirements are implemented or are to be implemented.
3. `ModuleDocumentation.md` â€” module-level documentation and module boundaries.

`ModuleDocumentation.md` must remain aligned with both `Requirements.md` and `Implementation.md`.

<!--
This document defines module-level responsibilities and internal behavior.
-->


## Relationship to Other Documents

- `Requirements.md` has priority for functional intent.
- `Implementation.md` has priority for implementation rules and execution model.
- `ModuleDocumentation.md` details the per-module documentation structure and practical module responsibilities.

## Module Documentation Minimum Template

Each `.ps1` and `.psm1` module should document at least:

- Module name and version
- Short synopsis
- Responsibilities
- Inputs and parameters
- Outputs and generated artifacts
- Dependencies (used/included modules and external commands)
- Error behavior
- Logging behavior
- Changelog (newest first)
- elevated mode required (when this is the case only)
- exposed to user (via symlink in PowerShell

## Change Management

When requirements or implementation principles change:

1. Update `Requirements.md` for functional impact.
2. Update `Implementation.md` for implementation impact.
3. Update `ModuleDocumentation.md` for module contract impact.

## Cross-Project Atom Contract Addendum (2026-05-29)

This addendum captures the currently approved contract direction for extracting and reusing functional atoms from BM, BEM, and INV.

### Approved Service-Class Direction

- Service classes are kept as contract boundaries.
- PowerShell classes are used to express interface-like contracts and typed data records.
- Implementations may remain in functions/modules as long as they satisfy class contract behavior.
- No inheritance is used in this contract model.
- Class collaboration is defined through composition and explicit method calls.

### Approved Reuse Groups

- `CoreMachineInfo`: machine identity, volume topology, boot configuration atoms.
- `CoreLogging`: BM-style logging/debug/trace/transcript including BM target-path handling.
- `CoreValidation`: validation, guards, error tools.
- `CoreState`: config/profile/state persistence.
- `CoreOps`: admin/task/time/path/cleanup operations.

### Source Selection Policy

- Prefer BM atoms when BM and BEM/INV overlap functionally.
- Use BEM/INV atoms where BM has information gaps, especially in boot and volume descriptive data.

### Compatibility Baseline

- Timestamp format for all module contracts is `yyyyMMdd_HHmmss`.

