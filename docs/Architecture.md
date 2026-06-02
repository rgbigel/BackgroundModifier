# Architecture.md

6.0.0
Profile: default
Author: Rolf Bercht

Purpose:

- End-user architecture view of the solution.
- Explains the solution as a time-flow across phases.
- Shows what the user must prepare, what happens during runtime stages, what can be re-run, and how to disable/uninstall.

Scope note:

- This document is user-centric and phase-centric.
- Requirements define functional intent.
- Implementation defines runtime wiring and technical mechanics.

## 1. End-User Time Flow

The solution is experienced in ordered phases:

1. Preparation before installation
2. Installation, configuration, and installation checks
3. Runtime Stage A: pre-logon (startup/system context)
4. Runtime Stage B: logon and post-logon (interactive user context)
5. Runtime tests and re-runnable operations after logon
6. Disable and uninstall

## 2. Phase 1: Preparation Before Installation

What the user must provide/check:

1. Required base assets are available.
2. Required permissions are available for installation and startup/logon automation.
3. The user understands there are two runtime stages:
   - Pre-logon stage
   - Logon stage

What the user is informed about:

1. Which stage collects machine/boot identity.
2. Which stage renders/applies backgrounds.
3. Which outputs and logs are expected after each stage.

## 3. Phase 2: Installation, Configuration, and Checks

What happens:

1. The solution is installed and runtime structure is configured.
2. Runtime orchestration is configured for startup and logon behavior.
3. Installation checks verify prerequisites and setup consistency.
4. Operational entry points are provisioned in `D:\OneDrive\cmd` by default.
5. The operational UX is menu-driven through a single elevated admin shell.

What the user sees/does:

1. Receives status of setup and validation checks.
2. Resolves reported prerequisite gaps.
3. Can re-run installation checks after corrections.

## 4. What Is Created and Provided on the User PC

After installation/configuration, the user can expect these solution artifacts and capabilities on the PC:

1. Runtime data area for solution operation.
2. Shared state file used across startup and logon stages.
3. Rendered output images produced by runtime stages.
4. Runtime diagnostics/log files for troubleshooting.
5. Startup/logon automation configuration used to run the stage flow.
6. Verification and maintenance routines that can be executed post-install.

User-facing interpretation:

1. The solution adds operational artifacts for data, logs, outputs, and automation.
2. These artifacts exist to support deterministic behavior, diagnostics, and controlled re-runs.
3. Disable/uninstall behavior controls whether these artifacts remain or are removed.

Detailed names/paths/mechanics are defined in `Implementation.md`.

## 5. Phase 3: Runtime Stage A (Pre-Logon)

What happens under the hood (user-level explanation):

1. Machine and boot identity data is collected.
2. Shared state is created or updated with startup-stage data.
3. Stage-level diagnostics/logging are recorded.
4. Partition identity metadata and EFI partition details are gathered from partition APIs with DiskPart/fsutil enrichment, while bootloader path identity is resolved from BCD.

What the user should know:

1. This stage is non-interactive.
2. This stage does not apply desktop/logon backgrounds directly.

## 6. Phase 4: Runtime Stage B (Logon and Post-Logon)

What happens under the hood (user-level explanation):

1. Shared state is loaded and enriched with user/session context.
2. Background images are rendered.
3. Desktop/logon application behavior is executed.
4. Runtime diagnostics/logging are recorded.

What the user can do after logon:

1. Inspect logs and validation output.
2. Run checks/verification tools.
3. Re-run supported configuration or test operations.

## 7. Phase 5: Runtime Tests and Re-Run Model

Provided runtime test scope includes:

1. Installation/setup verification checks.
2. Stage-level functional verification checks.
3. Safe re-run of selected operations after logon:
   - verification routines
   - configuration checks
   - non-destructive repair/update routines

Runtime test catalog (end-user view):

1. Installation verification:
   - Confirms setup/configuration prerequisites are still valid.
   - Typical use: after changing assets, permissions, or setup options.
2. Startup-stage verification:
   - Confirms machine/boot identity data can be collected and persisted.
   - Typical use: after boot configuration or disk layout changes.
3. Logon-stage verification:
   - Confirms rendering/apply flow can execute and produce expected outputs.
   - Typical use: after changing templates, text fields, or rendering options.
4. Configuration verification:
   - Confirms active configuration is readable, valid, and internally consistent.
   - Typical use: after manual edits or profile/config updates.
5. Repair/update re-run:
   - Re-executes non-destructive setup/repair logic.
   - Typical use: recover from partial setup drift without full reinstall.

Execution context note:

1. Some checks run in startup context, some in interactive logon context.
2. The implementation defines exact command entry points and context rules.

Rules:

1. Re-runs should be deterministic.
2. Re-runs must avoid destructive side effects.
3. Re-runs must preserve shared-state integrity across stages.

## 8. Phase 6: Disable and Uninstall

Disable behavior:

1. Runtime automation can be disabled without deleting user data immediately.
2. Disable should stop startup/logon execution flow.
3. Disable state should be reversible without a full reinstall.

Enable behavior:

1. Re-enables previously disabled startup/logon execution flow.
2. Does not require reinstall.
3. Does not imply cleanup or uninstall actions.

Uninstall behavior:

1. Removes solution automation/configuration.
2. Removes installed solution artifacts according to uninstall scope.
3. Preserves or removes runtime data according to explicit user choice.
4. Never removes or modifies repository source on `D:`.

Cleanup relationship:

1. Cleanup is a maintenance operation and is distinct from uninstall.
2. Cleanup can remove stale logs/outputs while keeping the solution active.
3. Uninstall removes solution execution capabilities; cleanup alone does not.
4. Disable/enable controls automation state only and does not remove artifacts.

User choice model for uninstall scope:

1. Keep diagnostics and state for later analysis.
2. Remove diagnostics and state for a full removal.
3. Keep base assets when the user plans later re-installation.

Operational entry-point model:

1. Canonical source remains in repository paths on `D:`.
2. Runtime data defaults to `C:\BootOpsHub`.
3. User operational entry points in `D:\OneDrive\cmd` are `BackgroundModifier_Install.cmd` and `BackgroundModifier.cmd`.
4. `BackgroundModifier.cmd` launches a menu-only elevated admin shell for setup, verify, enable/disable, uninstall, cleanup, and source-level actions.
5. Source actions include BootIdentity, Renderer, Setter, and Apply.
6. Apply is UX-gated: it runs automatically after successful Setter and is only shown directly after Setter problems.
7. `Setup.ps1` may self-relaunch through UAC when started from a non-elevated shell.

## 9. Cross-Document Consistency Rules

1. Requirements.md: functional outcomes and atom/class contracts.
2. Architecture.md: end-user time-flow and stage behavior.
3. Implementation.md: concrete runtime wiring and technical realization.
4. ModuleDocumentation.md: module-level contracts and boundaries.
