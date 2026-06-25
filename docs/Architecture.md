# Architecture.md
**Version:** 10.0.0 (Requirements-aligned)
**Profile:** default
**Author:** Rolf Bercht
**Updated:** 2026-06-24

## Purpose Of Document
- Provide an end-user architecture view of the solution.
- Explain the solution as an ordered runtime flow.
- Clarify phase responsibilities and sequencing rules.
- Document Consistency Rules
- **Alignment:** This document realizes Requirements.md (v10.0.0) functional requirements 1-30.

1. Requirements.md: functional outcomes and contracts (v10.0.0).
2. Architecture.md: user-visible runtime behavior and phase model (this document, v10.0.0).
3. Implementation.md: state contract, orchestration, and technical wiring (v10.0.0).
4. ModuleDocumentation.md: module-level boundaries.

## Scope Note

- Installer/setup execution requires PowerShell 7 (pwsh).
- All runtime configuration is managed exclusively via state.json; script parameters are reserved for user-exposed flags only.
- Internal implementation details are never exposed as parameters; all inter-component communication uses state.json.
- Current runtime code baseline remains 9.x; this architecture describes planned v10 behavior.

## 1. End-User Time Flow

The solution is experienced in ordered phases:

1. Preparation before installation
2. Installation, configuration, and installation checks
3. Runtime Phase 1: pre-logon (startup/system context) — collects system state
4. Runtime Phase 2: post-logon background processing
   - **Phase 2a:** Automatic scheduled execution (non-interactive, always elevated, system context, hidden from user)
   - **Phase 2b:** Interactive user-initiated execution (visible menu, user context, elevation on-demand)
5. Runtime tests and controlled re-runs
6. Disable and uninstall

Implementation note:
1. Desktop visual refresh reliability uses a two-step wallpaper apply sequence (temporary unique file path, then stable final file path).
2. Logon/lock apply uses a primary API path with policy-registry fallback when the API path is unavailable.
3. These reliability patterns were adapted from the PowerBGInfo repository (EvotecIT/PowerBGInfo) and integrated into the BackgroundModifier phase/elevation model.

Solution behavior (10.0.0):

1. A unified background model is produced for desktop and logon usage, with change detection via system state hash.
2. Runtime decisions are made from one shared state file with conditional rendering based on actual changes.
3. Sequencing is enforced by an orchestrator that blocks invalid transitions.
4. Two independent Phase 2 paths serve different purposes: automatic background prep (2a) and interactive user updates (2b).

---

## 2. Runtime Model

The runtime model is deliberately split into three distinct phases, each with specific responsibilities and user visibility:

### Phase 1: Pre-Logon Collection (System Context, Always Elevated)
- **Trigger:** System startup/scheduled pre-logon task
- **User Visibility:** None
- **Scope:** Machine-level system state
- **Responsibilities:**
  - Collect machine and boot identity context: hostname, OS version, build number, IP addresses, EFI label, BCD default, volume inventory
  - Capture system boot time (`lastBootTime`) — critical for detecting reboots across sessions
  - Compute systemInfo hash using SHA256(hostname+username+osVersion+buildNumber+lastBootTime+ipAddresses+efiLabel+bcdDefault+volumeInventory)
  - Write structured systemInfo to state.json with collection timestamp
  - Mark phase1Status = ready
  - Log execution with component version identifier
- **Critical:** No rendering is performed in Phase 1. Collection only.
- **Versioning:** BackgroundRenderer.ps1 must include `$Version` variable for logging

### Phase 2a: Automatic Post-Logon Processing (Scheduled, Always Elevated, Hidden)
- **Trigger:** Scheduled task running immediately post-user-logon (system context, elevated)
- **User Visibility:** None (errors only; success is silent)
- **Scope:** System-level background preparation and application
- **Responsibilities:**
  1. Load Phase 1 systemInfo from state.json
  2. Detect current logon: obtain username, logon timestamp from system
  3. Update state.json with logon metadata: `logon.logonTime` (only set here, only once per session)
  4. [PHASE2A-CODE: Detect autorun context; mark state with execution source]
  5. Inspect state.json to determine what changed:
     - Desktop section: if systemInfo hash differs OR desktop base was modified OR force-render requested
     - Logon section: if systemInfo hash differs OR logon base was modified OR force-render requested
  6. Render only the images where state changed (desktop only, logon only, or both)
  7. Call setter only if rendering occurred OR force-apply was requested
  8. Skip rendering and setter if nothing changed and no force flags set
  9. Update render tracking in state.json with new hashes and timestamps
  10. Log execution with component version identifier
  11. Apply desktop wallpaper using cache-busting two-step refresh to avoid stale path caching
  12. Apply logon/lock image using primary API path with policy fallback for compatibility
- **User Experience:** User logs in and sees updated desktop background immediately (if rendering occurred)
- **Idempotency:** Multiple Phase 2a runs in same session are safe; logonTime is only set on first execution
- **Versioning:** BackgroundSetter.ps1 must include `$Version` variable for logging

### Phase 2b: Interactive User-Initiated Action (Manual, User Context)
- **Trigger:** User runs `BackgroundModifier.ps1` interactively from command line or cmd launcher
- **User Visibility:** Interactive menu presented; user selects actions. User sees the flags and can optionally change them.
- **Scope:** User-level immediate desktop background updates
- **Responsibilities:**
  1. [PHASE2B-CODE: Detect user-initiated context (NOT autorun)]
  2. Present interactive menu of available actions: "Update desktop background?", "Update logon screen?", "Get new background image?", "Maintenance?", "Cleanup?", etc.
  3. User confirms selection
  4. Execute selected actions: render and/or apply as requested
  5. Provide immediate visual feedback (new desktop wallpaper appears)
  6. Log execution with component version identifier
- **User Experience:** User sees new desktop immediately after running command and confirming choices
- **Critical:** Phase 2b NEVER sets `logon.logonTime` — that is exclusive to Phase 2a
- **Critical:** Phase 2b is NOT an automatic flow; user must explicitly invoke and confirm actions
- **Versioning:** BackgroundModifier.ps1 must include `$Version` variable for logging

### Phase 2 Summary: State-Driven Change Detection
Both Phase 2a and 2b follow the same conditional rendering model:
- Inspect state.json sections that affect each output
- Render only if: state changed (hash differs, base changed) OR user explicitly forces re-render
- Apply only if: rendering occurred OR user explicitly forces apply
- This ensures efficiency: no unnecessary operations if system or user state hasn't changed

---

## 2b. External Pattern Attribution

BackgroundModifier uses internally adapted versions of two reliability patterns from PowerBGInfo (EvotecIT/PowerBGInfo):

1. Desktop refresh pattern:
- Set wallpaper to a temporary unique output path first.
- Then set wallpaper to the stable final output path.
- Purpose: avoid Windows wallpaper path caching and ensure immediate visible desktop updates.

2. Logon/lock apply pattern:
- Attempt high-level API-based lock screen apply first.
- If API path is unavailable or unsupported, fall back to policy registry `HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization\LockScreenImage`.
- Purpose: maximize compatibility across host/runtime differences while preserving deterministic behavior.

These patterns are implementation inspirations only; BackgroundModifier keeps its own contracts, state model, and sequencing rules.

---

## 3. Shared Runtime State

The solution uses a single source of truth for all runtime decisions:

- C:\BackgroundMotives\assets\state.json

This state contains:

1. Phase status and transition metadata.
2. System and logon identity information collected by Phase 1.
3. Systeminfo hash and change detection data.
4. Runtime intents and transient pending information.
5. Artifact/output paths and apply timestamps.
6. Execution source markers and version identifiers.

**State-Driven Configuration Rule:**
All internal runtime configuration is persisted to state.json. Script parameters are reserved exclusively for user-exposed flags (identifiable by short aliases in help text). No component accepts internal configuration via parameters.

**Parameter Minimization Rule:**
- Orchestrator (BackgroundModifier.ps1) accepts only user-exposed flags: `-i` (interactive), `-n` (non-interactive), `-v` (verbose), etc.
- All other configuration (paths, timeouts, rendering options, internal flags) is state.json-driven.
- Modules receive only context and state.json path references; they extract all configuration from state.json.

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

## 5. Versioning and Audit Trail

Each executable component maintains its own version identifier:

- **BackgroundModifier.ps1** ($Version = "10.0.0", planned): Orchestrator/entry point
- **BackgroundRenderer.ps1** ($Version = "10.0.0", planned): Phase 1 collector
- **BackgroundSetter.ps1** ($Version = "10.0.0", planned): Phase 2 renderer/applier
- **SystemInfoTools.psm1** ($Version = "1.0.0"): Shared system collection module
- **Other modules** ($Version = "X.X.X"): Individual version per module

**Version Storage Rules:**

1. Each .ps1 and .psm1 file includes a file-level `$Version` variable aligned with its version header.
2. Main orchestrator version (BackgroundModifier.ps1) is stored immutably in state.json at installation time.
3. All log entries must include the executing component's $Version identifier.
4. Version alignment is enforced at release time: file headers, $Version variables, and state.json version must match.

**Rationale:** Versioning enables audit trails, error diagnostics, and backward-compatibility decision-making during troubleshooting.

---

## 6. Module-Caller State Update Contract

The architecture strictly separates concerns between modules (processing logic) and callers (orchestration and state management):

**Module Responsibilities (What They Do):**
- Process input data (collect, compute, render, apply)
- Return results to caller
- Do NOT modify state.json directly
- Do NOT make state-level decisions
- Include component $Version in logging

**Caller Responsibilities (What Scripts Must Do After Calling Modules):**
1. Read state.json before calling module (if state is needed)
2. Extract required fields and pass to module as parameters
3. Receive module output
4. Update state.json with results including:
   - New computed values (hashes, timestamps, metadata)
   - Audit trail fields (collectionSource, collectedAtUtc, collectionSourceVersion)
   - Phase tracking (startedAtUtc, completedAtUtc, attemptCount, status)
5. Write state atomically to prevent corruption between Phase 2a/2b concurrent runs
6. Log the state write with caller component version

**Error Contract:**
- If module fails: Caller catches error, logs it, updates phase status to "blocked", writes error to state.json with userVisibleErrorMessage, exits with error code
- If caller fails to update state after state-affecting module call: State becomes inconsistent; this is a caller bug, not a module bug

**Example (Phase 1 Collection):**
```powershell
# Caller pre-phase: Read state
$state = Get-RuntimeState -StateFilePath $stateFile

# Call module (Collect + Compute)
$systemInfo = Collect-SystemInfo
$hash = Compute-SystemInfoHash -systemInfo $systemInfo

# Caller post-phase: Update state with results + audit trail
$state.systemInfo = $systemInfo
$state.systemInfo.hash = $hash
$state.systemInfo.collectedAtUtc = (Get-Date).ToString("yyyymmdd_HHmmss")
$state.systemInfo.collectionSource = "Phase1Renderer"
$state.systemInfo.collectionSourceVersion = $ScriptVersion
Set-RuntimeState -StateFilePath $stateFile -State $state
```

**Rationale:** This contract ensures:
- Modules remain testable and reusable (no hidden state dependencies)
- Callers retain explicit control over state consistency
- Audit trail is complete and traceable
- Concurrent Phase 2a/2b runs don't corrupt state

---

## 7. Orchestrator Behavior

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

## 7. Re-Run and Recovery Model

Re-runs are supported with these rules:

1. Re-runs are deterministic for equivalent state and inputs.
2. Invalid states are blocked explicitly and logged with reason.
3. Missing prerequisites or artifacts are represented in state and logs.
4. Recovery is performed by valid next transitions, not by bypassing sequence checks.

---

## 8. Disable and Uninstall

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
