# Architecture.md
**Version:** 8.0.2
**Profile:** default
**Author:** Rolf Bercht

## Purpose Of Document
- Provide an end-user architecture view of the solution.
- Explain the solution as an ordered runtime flow.
- Clarify phase responsibilities and sequencing rules.
- Document Consistency Rules

1. Requirements.md: functional outcomes and contracts.
2. Architecture.md: user-visible runtime behavior and phase model.
3. Implementation.md: state contract, orchestration, and technical wiring.
4. ModuleDocumentation.md: module-level boundaries.

## Scope Note

- Installer/setup execution requires PowerShell 7 (pwsh).

## 1. End-User Time Flow

The solution is experienced in ordered phases:

1. Preparation before installation
2. Installation, configuration, and installation checks
3. Runtime Phase 1: pre-logon (startup/system context)
4a. Runtime Phase 2 autorun: post-logon scheduled non-interactive execution
4b. Runtime Phase 2 manual run: post-logon interactive execution via BackgroundModifier
5. Runtime tests and controlled re-runs
6. Disable and uninstall

Solution behavior (8.0.0):

1. A unified background model is produced for desktop and logon usage.
2. Runtime decisions are made from one shared state file.
3. Sequencing is enforced by an orchestrator that blocks invalid transitions.

---

## 2. Runtime Model

The runtime model is deliberately split:

1. Phase 1 (pre-logon, elevated/system)
- Collect machine and boot identity context (hostname, OS, IP, BCD, EFI, volumes).
- Write structured systemInfo to state.json.
- Compute and store systemInfo hash for change detection.
- Mark phase1Status = ready.
- **No rendering is performed in Phase 1.**

2. Phase 2 (post-logon, user context)
- Validate phase 1 systemInfo availability in state.
- Compare systemInfo.hash with render.lastSystemInfoHash.
- If changed or no prior render: render desktop and logon overlay images.
- Apply rendered images to desktop and logon/lock screen targets.
- Update render tracking in state.
- In scheduled post-logon autoruns, execution is non-interactive and not user-visible.

---

## 3. Shared Runtime State

The solution uses a single source of truth:

- C:\BackgroundMotives\assets\state.json

This state contains:

1. Phase status and transition metadata.
2. Runtime intents and transient pending information.
3. Artifact/output paths and apply timestamps.

No separate pending marker file is required in the target architecture.

State path ownership rule:

1. Each repository builds its own runtime context object.
2. Context carries the repository-private runtime roots, log root, and state.json path.
3. Shared modules consume only the provided context and do not hardcode cross-repository state paths.

---

## 4. Deployment and Exposure Planes

The runtime architecture separates source, deployment, and user exposure:

1. Source plane (repositories)
- Canonical code remains in repository roots under Git_Repositories.

2. Deployment plane (non-repository runtime)
- Installer deploys runtime content to `D:\OneDrive\BTools`.
- Each solution deploys to `D:\OneDrive\BTools\<RepositoryName>`.
- Shared modules for cross-repository reuse are deployed under `D:\OneDrive\BTools\SharedModules`.
- Inventory metadata is maintained under `D:\OneDrive\BTools\Inventory`.
- This plane is deployment-only and does not store live runtime state.

3. Runtime state plane
- Live runtime state is stored only under `C:\BackgroundMotives`.
- Install/update initializes runtime state paths from deployed BTools content when required.
- Runtime logs and `state.json` are part of this state plane.
- Runtime logging is mandatory and logs are stored only in `C:\BackgroundMotives\logs`.
- The `C:` runtime-state location is retained intentionally for multi-boot environments.

4. User exposure plane
- User-facing commands are exposed in `D:\OneDrive\cmd`.
- Install/update operations create and refresh launchers/links from `cmd` into `BTools` runtime entrypoints.
- Exposure mappings are Inventory-driven.

The duplicate folder model `SharedModules\SharedModules` is not required by this architecture and is avoided for clarity.

---

## 5. Orchestrator Behavior

The operational orchestrator (BackgroundModifier) controls execution by:

1. Reading and validating state.json.
2. Deciding whether phase 1, phase 2, or no-op is required.
3. Enforcing sequence rules before invoking renderer/setter logic.
4. Writing state transitions and terminal outcomes.
5. Handling interactive lifecycle operations (enable, disable, cleanup, uninstall) from the user exposure layer.

The orchestrator is the sequence authority for runtime execution.

Shared-module interface governance:

1. Runtime context and state helper interfaces are versioned contracts.
2. Contract docs are maintained under docs/contracts.
3. Module updates require compatibility pre-check before rollout to consuming repositories.

---

## 6. Re-Run and Recovery Model

Re-runs are supported with these rules:

1. Re-runs are deterministic for equivalent state and inputs.
2. Invalid states are blocked explicitly and logged with reason.
3. Missing prerequisites or artifacts are represented in state and logs.
4. Recovery is performed by valid next transitions, not by bypassing sequence checks.

---

## 7. Disable and Uninstall

Disable:

1. Stops automation without deleting runtime data.
2. Can be reversed by enable.

Enable:

1. Restores automation with existing runtime state.

Uninstall:

1. Removes automation/configuration.
2. Removes or preserves runtime artifacts based on selected scope.
3. Never modifies repository source.

Lifecycle actions (enable/disable/cleanup/uninstall) are exposed as interactive orchestrator operations.

---
