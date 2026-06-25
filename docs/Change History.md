# Change History

## 2026-06-25 - 10.0.0 Documentation Baseline for Wallpaper Reliability and Logon Compatibility

Summary:
1. Documented desktop cache-busting refresh behavior (temporary unique wallpaper path, then stable final path) to address Windows path caching.
2. Documented logon/lock two-tier apply behavior: primary API path with policy-registry fallback.
3. Added diagnostics expectations for branch and fallback reason logging.
4. Updated architecture, requirements, implementation, and smoke-test checklist to reflect these behaviors as implemented.
5. Added explicit attribution that these reliability patterns were adapted from the PowerBGInfo repository (EvotecIT/PowerBGInfo).
6. Marked this update as documentation-only for future v10 planning; runtime code remains on 9.x pending implementation and testing.

## 2026-06-18 - 8.0.0 Phase State Normalization and Smoke Test Checklist

Summary:
1. Added state-based pending logon handoff in setter using `state.json` transient state.
2. Added phase 2 state transitions in setter (`running`, `blocked`, `failed`, `completed`) with explicit blocked reasons.
3. Added phase 1 state transitions in renderer (`running`, `failed`, `completed`, `ready`) for orchestrated sequencing.
4. Added non-interactive elevation guard behavior in setter (no UAC relaunch attempt in non-interactive context).
5. Added `docs/SmokeTestChecklist.md` for end-to-end verification of phase sequencing and state transitions.

## 2026-06-18 - 8.0.0 Runtime State Placement Correction

Summary:
1. Clarified that `D:\OneDrive\BTools` is deployment-only and does not store live runtime state.
2. Clarified that runtime assets, runtime logs, and `state.json` are exclusively under `C:\BackgroundMotives`.
3. Clarified that install/update initializes `C:\BackgroundMotives` runtime state from deployed BTools content when required.
4. Clarified that logging remains required and is written only to `C:\BackgroundMotives\logs` (not in BTools), including multi-boot rationale.

## 2026-06-18 - 8.0.0 BTools Deployment and cmd Exposure Documentation Update

Summary:
1. Documented `D:\OneDrive\BTools` as the non-repository deployment runtime root.
2. Added per-repository runtime topology under `BTools\<RepositoryName>`.
3. Added `BTools\Inventory` as the deployment and exposure mapping source.
4. Documented `D:\OneDrive\cmd` as the user-facing exposure layer managed during install/update.
5. Clarified that the duplicate folder pattern `SharedModules\SharedModules` is intentionally avoided.

## 2026-06-18 - 8.0.0 Runtime Sequencing Documentation Refresh

Summary:
1. Reworked active documentation to define the two-phase runtime model (pre-logon phase 1 and post-logon phase 2).
2. Declared `C:\BackgroundMotives\assets\state.json` as the single source of runtime truth.
3. Removed architecture references to separate pending marker files in favor of transient state embedded in state.json.
4. Added explicit orchestrator sequencing and guard expectations as documentation-level contract.

## 2026-06-14 - 8.0.0 Modules Layout Normalization

Summary:
1. Promoted `Modules` to a top-level sibling of `Source` and `Install`.
2. Updated installer/runtime scripts to deploy and import modules from the normalized layout.
3. Aligned active documentation and entry-script version markers to `8.0.0`.

## 2026-06-12 - 7.0.0 Baseline Normalization

Summary:
1. Normalized active script and module header versions to `7.0.0`.
2. Updated visible script banner version output to `v7.0.0` where applicable.
3. Reworked architecture and readme pages to align with BackgroundModifier naming and current runtime model.
4. Added `Requirements.md` and `Implementation.md` as active documentation anchors for version `7.0.0`.
5. Established this entry as the historical baseline for the clean 7.0.0 release candidate.
