# Implementation.md
**Version:** 9.0.0
**Profile:** default
**Author:** Rolf Bercht

## Purpose of this Document
- Define the technical realization of the runtime flow.
- Define the state contract used across runtime phases.
- Define sequencing and guard rules for renderer and setter execution.
- **Alignment:** This document realizes Architecture.md (v9.0.0) and Requirements.md (v9.0.0) technical contracts.

## Scope
- Platform: Windows 11 only.
- Installer/setup execution: PowerShell 7 (pwsh).
- Runtime model: Phase 1 collects system info and computes hash; Phase 2a automatically detects changes and conditionally renders/applies; Phase 2b provides interactive user actions.
- Deployment model: non-repository runtime in BTools plus cmd exposure layer.
- State contract: Comprehensive audit trail with versioning, source tracking, and transition management.

---

## 1. Runtime Contract

The runtime is split into three technical phases:

1. Phase 1 (pre-logon, elevated/system):
- Collect machine and boot identity context (hostname, OS, IP, BCD, EFI, volumes, lastBootTime).
- Compute SHA256 hash of collected systemInfo fields (including lastBootTime for reboot detection).
- Write systemInfo object + hash to state.json.systemInfo with collection source and version.
- Mark phase1Status = ready.
- **No rendering is performed in Phase 1.**

2. Phase 2a (automatic post-logon, scheduled/system context, elevated):
- Detect autorun context (scheduled task vs. manual invocation).
- Load Phase 1 systemInfo from state.json.
- Compare state.systemInfo.hash with state.render.lastSystemInfoHash.
- If hash differs or no prior render: conditionally render desktop and logon overlay images from systemInfo.
- Detect logon context; set logon.logonTime once on first execution only.
- Apply rendered images to desktop (via SystemParametersInfo) and logon/lock screen (via registry policy) only if rendering occurred.
- Update state.render section with hashes, timestamps, version identifiers, and audit trail.
- On failures, log error and exit; do not retry.

3. Phase 2b (interactive user-initiated, manual/user context):
- Detect user-initiated context (manual invocation, not scheduled).
- Present interactive menu with user-selectable actions.
- User confirms selections.
- Render and/or apply only for user-selected actions.
- **Never** set or modify logon.logonTime (exclusive to Phase 2a).
- Update state with audit trail of user actions.
- Provide immediate visual feedback.

**Coding Reminder (Maintenance Actions — v9+ Deferred):**
The Phase 2b interactive menu is designed to include the following diagnostic/maintenance actions in a future version:
- "Show runtime state (JSON)" — Display state.json contents for inspection and troubleshooting
- "Show log directory" — Open `C:\BackgroundMotives\logs` in file explorer for log review

These items are conceptually reserved and documented here for implementation in v9+. They do not require code changes to existing logic.

Post-logon scheduled autorun (Phase 2a) behavior:
- Execution is non-interactive and not user-visible.
- Non-interactive autoruns do not prompt for user decisions.
- Non-interactive autoruns execute only the simple phase 2a conditional render/apply flow.
- On failures, autoruns log and persist error state, then exit.
- Recovery and cleanup are performed by an explicit manual Phase 2b run through BackgroundModifier.

---

## 1b. System Info State Contract

Phase 1 writes the following to state.json:

```json
{
  "meta": {
    "schemaVersion": "...",
    "solutionVersion": "...",
    "solutionVersionSetAtInstall": "...",
    "lastUpdatedUtc": "...",
    "runId": "..."
  },
  "systemInfo": {
    "hostname": "...",
    "username": "...",
    "osVersion": "...",
    "buildNumber": "...",
    "lastBootTime": "...",
    "ipAddresses": "...",
    "efiLabel": "...",
    "bcdDefault": "...",
    "volumeInventory": "...",
    "hash": "...",
    "collectedAtUtc": "...",
    "collectionSource": "...",
    "collectionSourceVersion": "..."
  }
}
```

**Timestamp Format (All state.json timestamps):** `yyyymmdd_hhmmss` (local time, no dashes, no timezone offset)
- Example: `20260624_093015` (June 24, 2026, 9:30:15 AM local)
- Rationale: Human-readable in logs, filesystem-safe, unambiguous ordering

**Meta Section Usage:**
- `schemaVersion`: State contract version; allows orchestrator to validate structure
- `solutionVersion`: Current running version (immutable at install, updated only on explicit install/update)
- `solutionVersionSetAtInstall`: Timestamp when solution version was locked (audit trail)
- `lastUpdatedUtc`: Last time any section of state was modified (for change tracking)
- `runId`: Unique identifier per execution run (format: run-yyyymmdd-hhmmss-phaseX; uses dashes for readability)

**systemInfo Collection Source Tracking:**
- `collectionSource`: Which component collected this data (Phase1Renderer, etc.)
- `collectionSourceVersion`: Version of collecting component for audit trail

**State Transition Variables** (for orchestration decision-making):

```json
{
  "transitions": {
    "phase1": {
      "startedAtUtc": "...",
      "completedAtUtc": "...",
      "status": "...",
      "attemptCount": "...",
      "lastError": "...",
      "canProceedToPhase2": "..."
    },
    "phase2a": {
      "startedAtUtc": "...",
      "completedAtUtc": "...",
      "status": "...",
      "attemptCount": "...",
      "lastError": "...",
      "executionSource": "...",
      "logonTimeSet": "..."
    },
    "phase2b": {
      "startedAtUtc": "...",
      "completedAtUtc": "...",
      "status": "...",
      "attemptCount": "...",
      "lastError": "...",
      "executionSource": "...",
      "userConfirmedActions": "..."
    }
  },
  "diagnostics": {
    "lastCriticalError": "...",
    "lastCriticalErrorAtUtc": "...",
    "lastCriticalErrorPhase": "...",
    "lastCriticalErrorComponent": "...",
    "userVisibleErrorMessage": "..."
  }
}
```

**Transition Variables Usage:**
- `status`: completed|pending|in-progress|failed (Orchestrator uses this to decide if phase can be retried)
- `attemptCount`: Numeric; gate excessive retries (e.g., fail after 3 attempts)
- `lastError`: Detailed error log entry for diagnostics
- `canProceedToPhase2`: Boolean gate; Phase 1 readiness check
- `executionSource`: "ScheduledTask" (Phase 2a) or "UserInitiated" (Phase 2b); determines logonTime gating
- `logonTimeSet`: Timestamp when Phase 2a first ran (prevents re-setting in same session)
- `userConfirmedActions`: Array of user selections in Phase 2b

**Diagnostics Section (User-Visible Error Display):**
- `lastCriticalError`: Full error message/stack trace for logging and troubleshooting
- `lastCriticalErrorAtUtc`: When error occurred (format: yyyymmdd_hhmmss)
- `lastCriticalErrorPhase`: Which phase encountered the error (Phase1, Phase2a, Phase2b)
- `lastCriticalErrorComponent`: Which component logged the error (BackgroundRenderer, BackgroundSetter, etc.)
- `userVisibleErrorMessage`: **Human-readable, non-technical summary** for display to end user (e.g., "Failed to apply desktop background: permission denied")

**Logon State Section** (written by Phase 2a only, never by Phase 2b):

```json
{
  "logon": {
    "username": "...",
    "logonTime": "...",
    "logonTimeSetByPhase2a": "...",
    "sessionId": "..."
  }
}
```

**Logon Variables Usage:**
- `logonTime`: Set by Phase 2a on first execution only (format: yyyymmdd_hhmmss); never changed or set by Phase 2b
- `logonTimeSetByPhase2a`: Boolean flag to prevent re-setting in same session
- `username`: Current user at logon; may differ from systemInfo.username if collected pre-logon
- `sessionId`: Session identifier for audit trail and multi-session scenarios

**Display Rendering State** (metadata for what is rendered to background images):

```json
{
  "display": {
    "tableRowOrder": [
      "host", "os", "efi", "bcd", "lastBoot", "user", "logonTime", "ip", "volumeInventory", "rendered"
    ],
    "rowValues": {
      "host": "...",
      "os": "...",
      "efi": "...",
      "bcd": "...",
      "lastBoot": "...",
      "user": "...",
      "logonTime": "...",
      "ip": "...",
      "volumeInventory": "...",
      "rendered": "..."
    },
    "lastDisplayedAtUtc": "..."
  }
}
```

**Display Variables Usage:**
- `tableRowOrder`: Defines sequence of information rows on rendered background image (locked order)
- `rowValues`: Current values to display for each row; updated on every render
- `rendered`: Render timestamp (format: yyyymmdd_hhmmss); omitted from display if equals `logonTime` in non-user-action scenarios (Phase 2a automatic runs)
- `lastDisplayedAtUtc`: When this display was last rendered to disk (format: yyyymmdd_hhmmss)

Phase 2 writes the following to state.json after rendering:

```json
{
  "render": {
    "lastSystemInfoHash": "...",
    "lastRenderedAtUtc": "...",
    "renderedByPhase": "...",
    "renderedBySource": "...",
    "renderedBySourceVersion": "...",
    "renderedByOrchestrator": "...",
    "renderedByOrchestratorVersion": "...",
    "scriptVersion": "...",
    "desktopImageHash": "...",
    "logonImageHash": "...",
    "renderMetadata": {
      "screenResolution": "...",
      "stretchFactor": "...",
      "fontSizePixels": "...",
      "dpiAwareness": "...",
      "renderContext": "..."
    },
    "appliedAtUtc": {
      "desktop": "...",
      "logon": "..."
    },
    "appliedByPhase": "...",
    "appliedBySource": "...",
    "appliedBySourceVersion": "..."
  }
}
```

**Render Section Versioning & Audit Trail:**
- `renderedByPhase`: "Phase2a" or "Phase2b" identifier
- `renderedBySource`: "ScheduledTask" (Phase 2a) or "UserInitiated" (Phase 2b)
- `renderedBySourceVersion`: Version of rendering component
- `renderedByOrchestrator`: Component that initiated render
- `renderedByOrchestratorVersion`: Version of orchestrator
- `scriptVersion`: Immutable version from installer (same as meta.solutionVersion)
- `desktopImageHash`, `logonImageHash`: SHA256 of rendered JPG files for integrity and change detection
- `appliedAtUtc`: Separate timestamps per target (desktop, logon) for audit (format: yyyymmdd_hhmmss)
- `appliedByPhase`, `appliedBySource`, `appliedBySourceVersion`: Audit trail for apply operation

**Hash rule for systemInfo:** SHA256 of hostname+username+osVersion+buildNumber+lastBootTime+ipAddresses+efiLabel+bcdDefault+volumeInventory (JSON-serialized, excludes collectedAtUtc and render timestamp).

**Image hashes:** SHA256 of each rendered JPG file (desktop_rendered.jpg and logon_rendered.jpg) enables change detection and integrity verification without comparing full image buffers.

**[NOTE FOR IMPLEMENTATION]** render section captures rendered artifact integrity (image hashes), rendering environment context (screen resolution, DPI, font metrics), and stretch/layout factors that affect rendering output. These enable re-render decisions when display properties change without requiring full systemInfo hash change. systemInfo section may require additional internal tracking data (e.g., source markers, validation flags, audit fields). Details to be determined during code implementation.

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

### Parameters to Migrate to state.json

The following internal parameters are currently in .ps1 files and must be moved to state.json (per Requirement #10):

**BackgroundModifier.ps1:**
- `$Phase1Only` → `state.phase.forcePhase1Only`
- `$Phase2Only` → `state.phase.forcePhase2Only`

**BackgroundRenderer.ps1:**
- `$CaptureDesktopAsBase` → `state.intents.captureDesktopAsBase`
- `$PromoteDesktopBaseToLogonBase` → `state.intents.promoteDesktopBaseToLogonBase`
- `$RenderDesktop` → `state.render.forceRenderDesktop`
- `$RenderLogon` → `state.render.forceRenderLogon`
- `$SkipRender` → `state.render.skipRender`

**BackgroundSetter.ps1:**
- `$ApplyDesktop` → `state.intents.applyDesktop`
- `$ApplyLockScreen` → `state.intents.applyLockScreen`
- `$CaptureDesktopAsBase` → `state.intents.captureDesktopAsBase`
- `$PromoteDesktopBaseToLogonBase` → `state.intents.promoteDesktopBaseToLogonBase`

**User-exposed parameters retained:**
- `-t` / `--TraceMode` (logging control)
- `-h`, `-?` / `--HelpMode` (help)
- `-i` / `--Interactive` (user-initiated execution)
- `-n` / `--NonInteractive` (autorun execution)

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

Contract and install/setup support fields:

1. inventorySchemaVersion
2. contracts.runtimeContext.contractName
3. contracts.runtimeContext.contractVersion
4. contracts.stateTools.contractName
5. contracts.stateTools.contractVersion
6. installSupport.installStatus
7. installSupport.setupStatus
8. installSupport.setupScriptPath
9. installSupport.verifierScriptPath
10. installSupport.compatibilityScriptPath
11. setupSupport.setupStatus
12. setupSupport.verifierExitCode
13. setupSupport.taskNames
14. setupSupport.stateFilePath

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
2. Installer and Setup invoke the compatibility script as a hard gate before proceeding.
3. Minimum contract versions are enforced (module contract version must be >= required minimum).
4. Contract-breaking changes require a major version bump and consumer validation.
5. Contract-compatible additive changes require a minor version bump.

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
