Implementation.md
BackgroundModifier – Implementation Guide  
Version: 6.0.0
Profile: default
Author: Rolf Bercht

This document describes the implementation details of the BackgroundModifier solution.
It complements the `Req
<!--
This document describes how the functional requirements are implemented.
It must not redefine functional requirements.
-->
uirements.md`, which defines the architectural behavior and invariants.

Implementation ownership rule (2026-05-29):
- Concrete runtime wiring is defined here.
- This includes file/folder paths, task naming, command invocations, module loading, scheduling, and deployment/install behavior.
- Requirements-level documents may reference only atom/class contracts, not runtime wiring specifics.

Implementation.md defines coding conventions, module structure, logging behavior, JSON handling, rendering rules, wallpaper application, scheduled task configuration, symlink rules, and error‑handling patterns.

1. Module Header Format
Every .ps1 and .psm1 file must begin with the following header:

Code
<# ------------------------------------------------------------------------------------------------------------------------------
    Path: <Directory path relative to repository root>
    Module: <File name without path>

    Version: <Semantic version>
    Author: Rolf Bercht
    Synopsis: <Short description>
   Architecture: Requirements v6.0.0

    Notes:
        - <Architectural notes>

    Changelog:
        - <Version> <Date> <Summary>
   ------------------------------------------------------------------------------------------------------------------------------
#>
Rules:

Header is mandatory for all modules and scripts.

Version must follow semantic versioning.

Architecture reference must match the Requirements document version.

Changelog entries must be chronological.

2. Coding Conventions
2.1 Naming Rules
Functions use PascalCase: Get-EspIdentity, Write-StateJson.

Private helper functions begin with _.

Modules end with Tools.psm1.

Scripts use descriptive names: BootIdentity.ps1, BackgroundRenderer.ps1.

2.2 Parameter Rules
All public functions must support -Debug and -Trace.

All functions must validate parameters using ValidateNotNullOrEmpty where appropriate.

No function may rely on global variables.

2.3 Error Handling
All errors must be thrown using throw or Write-Error -ErrorAction Stop.

No silent failures.

All errors must be logged via LoggingTools.

3. Logging, Debugging, and Tracing
3.1 Logging
All modules must log to C:\BackgroundMotives\logs.

Log file naming convention:

BootIdentity_<timestamp>.log

Renderer_<timestamp>.log

Setter_<timestamp>.log

Verifier_<timestamp>.log

3.2 Debug Mode (-d)
Enables verbose output to console and log.

Does not change behavior.

3.3 Trace Mode (-t)
Implies debug mode.

Adds step‑by‑step trace entries to logs.

Used for deep debugging.

4. JSON Handling (State.json)
4.1 Schema
State.json must contain the following domains:

OS

System

ESP

UserInfo

Meta

4.### Module Header Requirements

Every `.ps1` and `.psm1` file must begin with a fixed‑layout header block.

- `Module:` — the exact file name including extension.
- `Path:` — the relative directory path **without** the file name and **without** a trailing backslash.
- `Author:` — always `Rolf Bercht` unless explicitly changed.
- `Version:` — current module version using semantic versioning (e.g., `6.0.0`).
- `Changelog:` — up to four predecessor versions, newest first, each with a short description.
- Header must be wrapped in a 100% fixed, aligned, monospaced block using `#` and `=` exactly as shown.

Example (authoritative):

    # =================================================================================================
    #  Module:      BootIdentity.ps1
    #  Path:        .\Source
    #  Author:      Rolf Bercht
   #  Version:     6.0.0
    #  Changelog:
   #      6.0.0  –  Introduced BCD‑based bootloader‑path resolution; restored Diskpart A1/Variant 1;
    #                 added full ESP correlation rules; added BootLoaderPath to State.json.
    #      4.004  –  Refined ESP label handling; removed temp‑file Diskpart capture; pipeline only.
    #      4.003  –  Corrected partition/volume correlation; enforced GUID‑based ESP detection.
    #      4.002  –  Added deterministic logging and strict error handling.
    #      4.001  –  Initial 4.x series structure and module boundary cleanup.
    # =================================================================================================


4.2 SchemaVersion
Meta.SchemaVersion must equal the version of the Requirements document (6.0.0).

4.3 Write Rules
BootIdentity writes OS/System/ESP/Meta.

Logon stage writes UserInfo and updates Meta.LastRunInfo.

Renderer updates Meta.LastRunInfo after rendering.

JSON must be written using ConfigTools with deterministic formatting.

4.4 Read Rules
All JSON reads must use ConfigTools.

Missing fields must be treated as errors unless explicitly allowed.

4.5 ### ESP Detection (BootTools Atom)

BootIdentity delegates ESP detection to `BootTools.psm1`.

1. `BootTools.Get-EspPartitions` enumerates partitions using `Get-Partition`.
2. EFI partitions are identified by GPT type:
   - `{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}`
3. Each EFI partition is correlated with `Get-Volume` metadata.
4. State payload for each EFI entry includes:
   - `DiskNumber`
   - `PartitionNumber`
   - `PartitionTypeGuid`
   - `PartitionType`
   - `IsSystem`
   - `IsBoot`
   - `VolumeLabel`
   - `DriveLetter`
   - `FileSystemType`
5. `BootTools.Get-ActiveEspPartition` selects active ESP deterministically:
   - prefers `IsSystem = true`
   - falls back to first EFI partition in sorted order

4.6 ### Bootloader Path Resolution (BCD-Based)

BootIdentity delegates BCD parsing to `BootTools.Get-BootLoaderPathFromCurrentBcd`.

1. Query the active boot entry:

   bcdedit /enum {current}

2. Extract:
   - device (must match the active ESP)
   - path (relative EFI file path, e.g. \EFI\Microsoft\Boot\bootmgfw.efi)

3. Combine `device + path` into `ESP.Active.BootLoaderPath`.

4. Write this to State.json under:
   ESP.Active.BootLoaderPath

5. If the BCD entry cannot be resolved:
   - log the error
   - continue writing all other fields


5. Module Dependency Rules
5.1 Allowed Dependencies
Orchestrator scripts may call multiple modules.

Modules may call:

LoggingTools

ConfigTools

TimeTools

5.2 Forbidden Dependencies
No circular dependencies.

No module may modify State.json except through ConfigTools.

No module may directly manipulate scheduled tasks (only SchedulerTools/TaskTools).

5.3 Architectural Dependency Matrix (verified: 2026-03-04)

This section maps architectural dependencies from Requirements.md against actual module files
in the codebase. Three categories are identified: Documented, Undocumented, and Missing.

### 5.3.1 Documented Modules (defined in Requirements.md)

These 15 modules are explicitly referenced in Requirements.md via "Uses" or "Calls" statements
and represent the intended architectural design:

| Module | Purpose | Used By | Status |
|--------|---------|---------|--------|
| BootTools.psm1 | ESP and boot identity detection (Get-Partition/Get-Volume, BCD) | BootIdentity.ps1 | ✓ Implemented |
| SystemTools.psm1 | OS and system information collection | BootIdentity.ps1 | ✓ Implemented |
| TimeTools.psm1 | UTC timestamp generation | BootIdentity.ps1, BackgroundRenderer.ps1 | ✓ Implemented |
| ConfigTools.psm1 | Deterministic JSON I/O for State.json | All phases | ✓ Implemented |
| LoggingTools.psm1 | Centralized append-only logging | BackgroundRenderer.ps1, others | ✓ Implemented |
| ValidationTools.psm1 | Parameter, path, and config validation | BackgroundRenderer.ps1 | ✓ Implemented |
| ErrorTools.psm1 | Deterministic error handling and reporting | BackgroundRenderer.ps1 | ✓ Implemented |
| RenderTools.psm1 | Image composition and text field rendering | BackgroundRenderer.ps1 | ✓ Implemented |
| ImageTools.psm1 | Image manipulation and file I/O | BackgroundRenderer.ps1 | ✓ Implemented |
| WallpaperTools.psm1 | P/Invoke wallpaper application (SystemParametersInfo) | BackgroundSetter.ps1 | ✓ Implemented |
| SchedulerTools.psm1 | Scheduled task creation and registration | Setup.ps1 | ✓ Implemented |
| TaskTools.psm1 | COM wrappers for scheduled task manipulation | Setup.ps1, Cleanup.ps1 | ✓ Implemented |
| CleanupTools.psm1 | Log rotation and temp file cleanup | Cleanup.ps1 | ✓ Implemented |
| BackgroundStateMgr.psm1 | Apply rendered images to desktop/logon screens | BackgroundSetter.ps1 | ✓ Implemented |
| BackgroundNoBlurReg.psm1 | Registry rules to disable blur on logon screen | BackgroundSetter.ps1 | ✓ Implemented |

Note: Both `BackgroundStateMgr.psm1` and `BackgroundNoBlurReg.psm1` have been added to `Source/Modules` and are present in the codebase. Please verify their behavior through the install/test workflows and update implementation details in this document if required.

### 5.3.2 Undocumented Modules (present in codebase but not in Requirements.md)

These 10 modules exist in Source/Modules but are not mentioned in Requirements.md. They may be
infrastructure/support modules, renamed modules, or consolidations. Review and categorize:

| Module | Inferred Purpose | Category | Action |
|--------|------------------|----------|--------|
| Constants.psm1 | Global path constants and well-known directories | Infrastructure | Review: add "Uses" to Requirements or document internal status |
| InstallerTools.psm1 | Setup.ps1 helper functions | Tool Module | Document purpose or consolidate into Setup.ps1 |
| Logging.psm1 | Legacy predecessor of LoggingTools.psm1 | Legacy | Archive: use LoggingTools.psm1 exclusively |
| ModeTools.psm1 | Debug (-d) and Trace (-t) mode flag handling | Bootstrap Support | Consider: add to Requirements as internal infrastructure |
| PathTools.psm1 | Path validation and directory creation utilities | Infrastructure | Review: should be documented or consolidated |
| ProfileTools.psm1 | User profile identification and manipulation | Infrastructure | Review: add "Uses" to Requirements if active |
| SetFlagsTool.psm1 | Command-line flag parsing (-t, -d, etc.) | Bootstrap Support | Consider: document scope and lifecycle |
| SummaryTools.psm1 | Summary reporting and output formatting | Infrastructure | Review: usage context and scope |
| TranscriptTools.psm1 | PowerShell transcript start/stop/rotation | Infrastructure | Review: add to Requirements if active |
| Validation.psm1 | Legacy predecessor of ValidationTools.psm1 | Legacy | Archive: use ValidationTools.psm1 exclusively |

**Recommended Next Steps:**
1. Verify whether Logging.psm1 and Validation.psm1 are duplicates or renamed variants of LoggingTools and ValidationTools.
2. Determine scope of infrastructure modules (Constants, ModeTools, SetFlagsTool, etc.):
   - If essential to bootstrap/runtime, update Requirements.md section 5 with "Uses" statements
   - If historical, move to archive/ folder with a deprecation note
3. Verify end-to-end runtime integration of BackgroundStateMgr and BackgroundNoBlurReg during install/logon workflows.

### 5.3.3 Summary

- **Documented (Requirements.md):** 15 modules specified; 15 implemented, 0 missing
- **Actual Codebase:** 23 modules total (13 documented + 10 undocumented)
- **Reconciliation Required:** Clarify status of 10 undocumented and 2 missing modules

6. Rendering Implementation
6.1 Rendering Rules
Renderer must load State.json.

Renderer must draw text fields in a deterministic layout.

Renderer must output:

DesktopScreen.jpg

LogonScreen.jpg

6.2 Fonts and Layout
Font family: Segoe UI (or fallback)

DPI: 96

Text color: white

Shadow: optional

Open Question: Should font size scale with resolution?

6.3 Required Fields
Renderer must include:

OS UpdateVersion

Host Name

User Name

Boot Time

Logon Time

Indexing (optional)

IP Address

7. Wallpaper Application
7.1 Desktop Wallpaper
Applied via SystemParametersInfo (P/Invoke).

Must apply DesktopScreen.jpg.

7.2 Logon Wallpaper
Applied via registry/policy.

Must apply LogonScreen.jpg.

BackgroundNoBlurReg ensures crisp rendering.

Open Question: Should lock screen image path be enforced via policy or user-level registry?

8. Scheduled Task Configuration
8.1 BootIdentity Task
Name: BackgroundModifier-BootIdentity

Trigger: At system startup

User: SYSTEM

Action: Run BootIdentity.ps1 via symlink

8.2 Autorun Task
Name: BackgroundModifier-Autorun

Trigger: At user logon

User: Interactive user

Action: Run BackgroundSetterStart.ps1 via symlink

9. Symlink Creation Rules
9.1 Required Symlinks
C:\BackgroundMotives\SolutionCode\ must contain:

BootIdentity.ps1

BackgroundRenderer.ps1

BackgroundSetter.ps1

BackgroundSetterStart.ps1

BackgroundInstallationVerifier.ps1

9.2 Rules
No real code may exist in SolutionCode.

Symlinks must be absolute and validated.

Installer must recreate missing symlinks.

10. Error Handling and Recovery
All errors must be logged.

Fatal errors must stop execution.

Non‑fatal errors must warn and continue where safe.

BootIdentity must never crash the system startup task.

Autorun must abort if State.json is missing or invalid.

Open Question: Should Autorun retry State.json load if file is locked?

11. Implementation Notes
All modules must be stateless.

All scripts must be idempotent where possible.

All timestamps must use UTC unless otherwise required.

Open Question: Should Renderer support high‑DPI scaling?

12. Function Reference Coverage (Docs ↔ Code)
The following function inventory is documented to establish explicit reference coverage between implementation modules and documentation.

- BootTools.psm1: `Get-EspPartitions`, `Get-ActiveEspPartition`, `Get-BootLoaderPathFromCurrentBcd`, `Get-EspIdentitySnapshot`
- BackgroundNoBlurReg.psm1: `Set-NoBlur`, `Remove-NoBlur`
- BackgroundStateMgr.psm1: `Get-BackgroundState`, `Update-BackgroundState`, `Clear-BackgroundState`
- CleanupTools.psm1: `Remove-OldLogs`, `Clear-RenderFolder`
- ConfigTools.psm1: `Load-Config`, `Save-Config`
- ErrorTools.psm1: `Throw-ToolError`, `Write-ToolError`
- ImageTools.psm1: `Test-Image`, `Get-ImageSize`
- InstallerTools.psm1: `Test-Admin`, `Require-Admin`, `Copy-Safe`
- Logging.psm1: `Write-LogInfo`, `Write-LogWarn`, `Write-LogError`
- LoggingTools.psm1: `Write-Log`, `Write-LogDebug`, `Write-LogTrace`
- ModeTools.psm1: `Show-DebugState`, `Show-TraceState`
- PathTools.psm1: `Ensure-Path`, `Join-Safe`
- ProfileTools.psm1: `Load-Profile`, `Save-Profile`, `Test-ProfileValid`
- RenderTools.psm1: `Merge-Image`
- SchedulerTools.psm1: `Register-BackgroundTask`, `Unregister-BackgroundTask`, `Test-BackgroundTask`
- SetFlagsTool.psm1: `Set-Flags`
- SummaryTools.psm1: `Show-Summary`
- SystemTools.psm1: `Get-OSInfo`, `Test-IsWindows`, `Get-UserName`, `Get-ComputerName`
- TaskTools.psm1: `Invoke-TaskStep`
- TimeTools.psm1: `Get-RunTimestamp`, `Get-ShortDate`, `Get-RunId`, `Measure-Block`
- TranscriptTools.psm1: `Get-TranscriptPath`, `Start-ToolTranscript`, `Stop-ToolTranscript`
- Validation.psm1: `Test-FileExists`, `Test-FolderExists`, `Require-File`, `Require-Folder`
- ValidationTools.psm1: `Test-PathRequired`, `Test-StringRequired`, `Test-NumberRange`
- WallpaperTools.psm1: `Set-Wallpaper`

13. Versioning Policy
- Baseline release is `6.0.0`.
- Minor, non-breaking changes increment the patch number (for example: `6.0.1`, `6.0.2`).
- Redesign-level changes increment the minor or major version as needed (for example: `6.1.0`, `7.0.0`).
- Module headers and documentation versions should be kept aligned with the active repository version.

14. Cross-Project Atom Harmonization Snapshot (2026-05-29)

Status:
- Architecture review completed.
- Documentation freeze for target structure completed.
- No implementation refactor executed yet.

14.1 Target Reuse Model
- Reusable functionality is to be published as globally useful `.psm1` modules.
- BM is the preferred default source when BM and BEM/INV provide equivalent behavior.
- BEM and INV atoms are used to close BM gaps, especially in machine-descriptive information.

14.2 Target Module Groups
- `CoreMachineInfo`
- `CoreLogging`
- `CoreValidation`
- `CoreState`
- `CoreOps`

14.3 Atom Interface Style (PowerShell)
- Use PowerShell classes for contract/data shapes and provider boundaries.
- Service classes remain part of the design and are kept.
- Class contracts define input/output/error expectations; implementation may remain function-based internally.

14.4 Compatibility Rule Update
- Canonical timestamp format is unified to `yyyyMMdd_HHmmss` for all logs, run IDs, and file name stamps.

14.5 Source Preference Rules
- For BEM-related implementation candidates, BM logic may replace BEM logic when BM is functionally better.
- BEM/INV atoms remain authoritative where BM currently lacks equivalent information extraction depth.

15. Runtime Mapping to End-User Use Cases (2026-05-29)

This section maps implementation/runtime mechanics to the top-level user use cases defined in `Requirements.md`.

15.1 Install and Verify Prerequisites
- Runtime layout creation, symlink creation, and task registration are implementation-owned.
- Asset verification and installer validation steps are implementation-owned.
- `D:\OneDrive\cmd` operational entry links are installer-owned by default.
- Testing entry links are opt-in via setup parameter `-IncludeTestLinks`.
- When `-IncludeTestLinks` is not set, setup removes existing test entry links from `D:\OneDrive\cmd`.

15.2 Collect Startup Identity Snapshot
- Startup-stage runtime trigger and execution context are implementation-owned.
- Machine/boot identity collection wiring and state write sequence are implementation-owned.

15.3 Render and Apply Backgrounds at Logon
- Logon trigger, stage orchestration, render/apply sequence, and registry integration are implementation-owned.

15.4 Diagnose and Verify
- Logging/transcript paths, verifier routines, and report generation wiring are implementation-owned.

15.5 Update/Repair Safely
- Idempotent setup/repair and cleanup mechanics are implementation-owned.

Compatibility note:
- Timestamp format remains `yyyyMMdd_HHmmss` for logs, run IDs, and file-name stamps.

16. Runtime Test Matrix and Re-Run Mechanics (2026-06-01)

This section defines the implementation-owned runtime test surface corresponding to the end-user phase model.

16.1 Test Categories

1. Installation verification tests
   - Validates setup prerequisites and configuration consistency.
   - Expected outputs: pass/fail status, remediation hints, log entries.
2. Startup-stage functional tests
   - Validates machine/boot identity collection and state persistence.
   - Expected outputs: updated/shared state fields, stage diagnostics.
3. Logon-stage functional tests
   - Validates state enrichment, render outputs, and apply behavior.
   - Expected outputs: rendered artifacts, apply status, stage diagnostics.
4. Configuration validation tests
   - Validates readable/consistent configuration and profile/state coherence.
   - Expected outputs: validation report and actionable error messages.
5. Repair/update tests
   - Validates idempotent re-run behavior for non-destructive recovery.
   - Expected outputs: stable configuration state and deterministic logs.

16.2 Context Rules

1. Tests are bound to the stage context they validate (startup or logon context).
2. Re-run operations must not corrupt shared state across stages.
3. Failed tests must produce deterministic diagnostics with remediation guidance.

17. Disable, Cleanup, and Uninstall Mechanics (2026-06-01)

17.1 Disable

1. Disable turns off startup/logon execution triggers.
2. Disable keeps runtime data by default.
3. Disable must be reversible by re-enabling execution triggers.
4. Operational entry point: `Install/Disable.ps1`.

17.1a Enable

1. Enable restores startup/logon execution triggers previously disabled.
2. Enable does not perform reinstall.
3. Enable does not imply cleanup/uninstall behavior.
4. Operational entry point: `Install/Enable.ps1`.

17.2 Cleanup

1. Cleanup is maintenance-only and does not disable solution execution.
2. Cleanup removes stale diagnostics/output artifacts according to cleanup policy.
3. Cleanup does not remove baseline configuration unless explicitly requested.

17.3 Uninstall

1. Uninstall removes execution automation and solution configuration wiring.
2. Uninstall scope supports explicit retention/removal choices for runtime data.
3. Uninstall must report final scope summary to the user (what was removed vs retained).
4. Uninstall must never remove or mutate repository source/docs/git metadata.
5. Operational entry point: `Install/Uninstall.ps1`.

17.4 Safety Rules

1. Disable, cleanup, and uninstall operations must be idempotent where feasible.
2. Each operation must emit deterministic logs and completion status.
3. Destructive scope must require explicit user confirmation parameters.

18. Known Legacy Malfunction and Remedy (2026-06-01)

Issue observed in legacy flow:

1. Desktop/logon output could appear as plain black background with no text.

Root cause chain:

1. Renderer stage copied base images but did not draw text overlays.
2. Logon orchestrator script was a placeholder and did not execute render/apply stages.
3. No-blur helper set a registry value that disabled logon background image display.
4. Desktop apply flow did not explicitly invoke wallpaper API in the execution path.

Remedy implemented:

1. Renderer now performs explicit text overlay drawing onto output images.
2. Logon orchestrator now executes render, policy, and apply stages in sequence.
3. No-blur helper now uses acrylic-blur policy (keeps background image enabled).
4. Setter now invokes wallpaper apply API after image deployment.

Validation expectations after remedy:

1. Rendered images exist and contain textual overlays.
2. Desktop wallpaper is updated during apply stage.
3. Logon image remains visible while blur is disabled.