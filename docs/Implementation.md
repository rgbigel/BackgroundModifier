# Implementation.md
**Version:** 8.0.0
**Profile:** default
**Author:** Rolf Bercht

## Purpose of this Document
- Define the technical realization of the runtime flow.
- Define the state contract used across runtime phases.
- Define sequencing and guard rules for renderer and setter execution.

## Scope
- Platform: Windows 11 only.
- Installer/setup execution: PowerShell 7 (pwsh).
- Runtime model: two-phase rendering with single-source state in state.json.
- Deployment model: non-repository runtime in BTools plus cmd exposure layer.

---

## 1. Runtime Contract

The runtime is split into two technical phases:

1. Phase 1 (pre-logon, elevated/system):
- Collect machine and boot identity context.
- Produce machine-valid render artifacts.
- Update state.json with phase 1 completion metadata.
- Do not invoke phase 2 setter behavior.

2. Phase 2 (post-logon user context):
- Load and validate phase 1 output from state.json.
- Enrich state with session/user context.
- Produce final render artifacts for desktop and next logon cycle.
- Apply requested targets through setter operations.
- In scheduled post-logon autoruns, execution is normally non-interactive and not user-visible.
- In non-interactive autoruns, run the simple phase 2 path and handle errors only.
- Cleanup and corrective actions are intentionally deferred to a later manual BackgroundModifier run.

---

## 2. Single Source of Truth

All runtime state is represented in one file:

- C:\BackgroundMotives\assets\state.json

No separate pending marker file is used in the target design. Transient intent is represented inside state.json.

Parameterization rule:

1. Runtime scripts accept context-relevant path parameters.
2. Default context uses C:\BackgroundMotives roots.
3. A repository can override RuntimeRoot, LogRoot, and StateFilePath without code changes in shared modules.

---

## 3. Runtime Deployment Topology

Runtime deployment is installer-managed and separate from repository sources:

1. Deployment root (non-repository)
- D:\OneDrive\BTools

2. Per-repository runtime root
- D:\OneDrive\BTools\<RepositoryName>

3. Shared module catalog
- D:\OneDrive\BTools\SharedModules

4. Inventory root
- D:\OneDrive\BTools\Inventory

5. Deployment-only rule
- BTools stores deployable sources, modules, and fallback assets.
- BTools does not store live runtime state.
- BTools does not store runtime logs.
- Runtime logging is required and log output is written only to C:\BackgroundMotives\logs.

The duplicate folder model SharedModules\SharedModules is intentionally not required in this topology.

---

## 4. User Exposure Layer

User functionality is exposed through:

- D:\OneDrive\cmd

Installer responsibilities for exposure:

1. Create and refresh command launchers/links from cmd to BTools runtime entrypoints.
2. Keep exposure mappings aligned with Inventory records.
3. Remove stale exposure artifacts no longer present in Inventory.
4. Validate that each exposed command target resolves successfully.

---

## 5. State Structure (Target)

state.json contains logical sections:

1. meta
- schemaVersion
- solutionVersion
- lastUpdatedUtc
- runId

2. phase
- currentPhase (Phase1, Phase2, Blocked)
- phase1Status
- phase2Status
- blockedReason

3. phase1Data
- boot/machine identity values collected pre-logon
- phase1 artifact readiness markers

4. phase2Data
- user/session values collected post-logon
- phase2 artifact readiness markers

5. intents
- applyDesktop
- applyLockScreen
- captureDesktopAsBase
- promoteDesktopBaseToLogonBase

6. transient
- pendingLogon: object or null
  - sourcePath
  - requestedAtUtc
  - reason
  - requiresElevation
  - status

7. outputs
- desktopRenderedPath
- logonRenderedPath
- desktopAppliedAtUtc
- logonPolicyAppliedAtUtc

---

## 6. Inventory Contract (Deployment + Exposure)

Inventory tracks deployed runtime and command exposure mappings. Minimum fields:

1. repositoryName
2. deployedRuntimeRoot
3. deployedVersion
4. sourceCommit
5. commandName
6. commandShimOrLinkPath
7. targetEntryPath
8. enabled
9. lastUpdatedUtc

---

## 7. Sequencing and Guards

1. Pre-logon entry does not run phase 2 setter behavior.
2. Post-logon orchestrator validates state before execution.
3. If phase 1 is not ready, post-logon orchestrator must run phase 1 elevated and re-validate.
4. Setter exits with a clear reason when state indicates invalid sequence.
5. Lock/sign-in activation is applied in post-logon only and affects the next logon cycle.

---

## 8. Shared Module Contracts

Contract sources:

1. docs/contracts/RuntimeContext-Contract.md
2. docs/contracts/StateTools-Contract.md

Compatibility enforcement:

1. Install/Test-SharedModuleCompatibility.ps1 validates required exported function names.
2. Contract-breaking changes require a major version bump and consumer validation.
3. Contract-compatible additive changes require a minor version bump.

---

## 9. Orchestrator Responsibilities

A single operational entrypoint (BackgroundModifier) is responsible for:

1. Reading state.json and deciding required actions.
2. Enforcing phase order.
3. Running phase 1 elevated when required.
4. Running phase 2 post-logon operations when state is ready.
5. Persisting state transitions and results to state.json.

Post-logon scheduled autorun behavior:

1. Scheduled autoruns are treated as non-interactive by default.
2. Non-interactive autoruns do not prompt for user decisions.
3. Non-interactive autoruns execute only the simple phase 2 flow.
4. On failures, autoruns log and persist error state, then exit.
5. Recovery and cleanup are performed by an explicit manual run through BackgroundModifier.

---

## 10. Error and Recovery Rules

1. Invalid sequence transitions move state to Blocked with blockedReason.
2. Missing artifacts are represented in state and surfaced in logs.
3. Re-runs are deterministic and non-destructive.
4. State validation occurs before every phase transition.

---

## 11. Paths

1. Deployment root: D:\OneDrive\BTools
2. Per-repository runtime root: D:\OneDrive\BTools\<RepositoryName>
3. Shared module catalog: D:\OneDrive\BTools\SharedModules
4. Inventory root: D:\OneDrive\BTools\Inventory
5. User exposure root: D:\OneDrive\cmd
6. Runtime state root: C:\BackgroundMotives
7. Runtime assets root: C:\BackgroundMotives\assets
8. Runtime logs root: C:\BackgroundMotives\logs
9. State file: C:\BackgroundMotives\assets\state.json
