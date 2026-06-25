# BackgroundModifier Requirements

Version: 10.0.0

## Scope
BackgroundModifier must deterministically generate and apply background images that include machine-relevant metadata for operational visibility.
This solution targets Windows 11 only.
The installer and runtime entry points require PowerShell 7 (`pwsh`).
Runtime configuration and state are managed exclusively through state.json; internal implementation details are never exposed as script parameters.
This requirement set defines the planned v10 behavior; runtime code remains on 9.x until implementation starts.

## Functional Requirements

### Core Responsibilities
1. Provide a repeatable phase 1 identity capture stage (pre-logon, system context) that collects machine boot and system identity context and computes a state change hash.
2. Collect and preserve system boot time (`lastBootTime`) to detect reboots across sessions.
3. Provide deterministic phase 2 rendering (post-logon) that converts collected metadata into background images only when system state has changed or user explicitly requests re-render.
4. Provide conditional apply stage (post-logon) that sets generated backgrounds to active Windows targets only when rendering occurred or user explicitly requests apply.
5. Provide installation verification to validate required folders, scripts, and modules.
6. Provide diagnostic logging for every operator-facing execution path.

### Phase 2 Split: Automatic vs. Interactive
7. Provide Phase 2a (automatic post-logon, scheduled, non-interactive, always elevated, hidden from user): automatically detect system state change via hash comparison; render and apply conditionally; set `logon.logonTime` once on first execution only; never set logonTime again in same session.
8. Provide Phase 2b (interactive user-initiated, manual, user-selectable actions, elevation on-demand): present menu with user actions ("Update desktop background?", "Update logon screen?", "Get new background image?", "Maintenance?", "Cleanup?", etc.); allow user to select and confirm actions; never set or modify `logon.logonTime`; provide immediate visual feedback after action execution.

### State Management and Interprocess Contract
9. Maintain one shared immutable runtime state contract in `C:\BackgroundMotives\assets\state.json` as the single source of truth for all runtime decisions.
10. Persist all internal runtime configuration, metadata, and operational state exclusively to state.json; all modules must consume internal configuration from state.json only (not from script parameters).
11. Reserve command-line parameters exclusively for user-exposed flags (identifiable by short aliases in help text). All other options must be state.json-driven.
12. Define and maintain systemInfo hash computation: SHA256(hostname+username+osVersion+buildNumber+lastBootTime+ipAddresses+efiLabel+bcdDefault+volumeInventory). The `lastBootTime` field (from Win32_OperatingSystem.LastBootUpTime) detects kernel restarts: cold boot, warm restart, installation reboot, crash recovery. It does NOT change on sleep resume or hibernate resume (kernel remains resident). Equivalent `lastBootTime` across collections indicates same session; changed `lastBootTime` indicates kernel restart.

### Module-Caller State Update Contract
12.5. **Module Responsibility Boundary**: Modules are responsible only for processing logic (collect data, compute hashes, render images, apply settings); they do NOT directly modify state.json.
12.6. **Caller Responsibility Boundary**: Callers (scripts that invoke modules) are responsible for: (a) reading state.json before calling module, (b) extracting and passing required data as parameters, (c) receiving module output, (d) updating state.json with results including timestamps, hashes, versions, audit trail fields (collectionSource, collectedAtUtc, etc.), (e) writing state atomically to prevent corruption. Failure to update state.json after a state-affecting module call is a caller bug, not a module bug.
12.7. Each module header must document which state.json fields are affected (if any) and the caller's post-execution responsibilities.

### Versioning and Logging
13. Each source file (.ps1) and module (.psm1) must define an individual `$Version` variable (as text string) aligned with the file's version header.
14. Main orchestrator version must be stored immutably in state.json at installation time and updated only during explicit install/update operations.
15. All log entries must include the executing component's version for audit trail and diagnostics.
16. Maintain consistent timestamp format across state.json: `yyyymmdd_hhmmss` (local time, no dashes, no timezone offset). Example: `20260624_093015` for June 24, 2026 at 9:30:15 AM.
17. Store last critical error in state.json with phase, component, timestamp, full error details, and a human-readable user-visible error message for display to end user.

### Deployment Topology
18. Maintain source code in repository roots under `Git_Repositories`.
19. Deploy runtime content to non-repository deployment plane: `D:\OneDrive\BTools\<RepositoryName>`.
20. Deploy shared modules to `D:\OneDrive\BTools\SharedModules`.
21. Maintain Inventory metadata under `D:\OneDrive\BTools\Inventory`.
22. Store live runtime state exclusively under `C:\BackgroundMotives` (state.json, logs, assets).
23. Expose user-facing commands in `D:\OneDrive\cmd` as launchers/links managed by Installer (Inventory-driven).

### Execution and Sequencing
24. Enforce sequencing rules through orchestrator logic to block invalid phase transitions.
25. Invalid transitions must be logged with explicit state and reason.
26. Re-runs must be deterministic for equivalent state and inputs.

### Wallpaper Apply Reliability
27. Desktop apply must use a cache-busting refresh sequence (temporary unique path followed by final stable path) to avoid Windows wallpaper path caching and ensure visible desktop refresh.
28. Logon/lock apply must support a two-tier compatibility strategy: primary API-based apply, with policy-registry fallback when the API path is unavailable.
29. Fallback branch selection and reason must be logged for diagnostics.

### External Pattern Attribution
30. The desktop cache-busting refresh approach and logon API-plus-fallback strategy are adopted from the PowerBGInfo repository (EvotecIT/PowerBGInfo) and adapted to BackgroundModifier contracts.

## Non-Functional Requirements
1. Deterministic behavior for equivalent inputs.
2. Script/module version headers aligned to the active solution version.
3. No hidden runtime dependencies outside documented paths.
4. Documentation and code remain version-consistent at release points.
5. Invalid phase transitions are blocked with explicit state and log reasoning.
6. Conditional rendering and apply logic must avoid redundant disk I/O and registry operations.

## Runtime Paths
1. C:\BackgroundMotives\assets
2. C:\BackgroundMotives\logs
3. C:\BackgroundMotives\assets\state.json

Generated output images are stored in C:\BackgroundMotives\assets and distinguished from base input images by filename.
