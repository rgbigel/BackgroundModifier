# BackgroundModifier Architecture

Module: Architecture.md
Purpose: Architectural design and dynamic Rainmeter skin overlay layout for BackgroundModifier.
Path: docs/Architecture.md
Authors: Rolf, Workspace_AI Engine
Version: 2.0.0
Changelog:
- 2026-08-26: Modernize to Dynamic Rainmeter Telemetry Skin Engine (CR-2026-019).
- 2026-08-16: Initial architecture scaffolding.

---
title: BackgroundModifier Architecture
updated: 2026-08-26
created: 2026-08-16
---

## 1. System Context & Responsibilities
`BackgroundModifier` provides real-time desktop telemetry, identity visualization, and multi-boot drive status using a high-performance, dynamic Rainmeter skin engine.

### Architectural Advantages:
1. **Zero GDI+ Bitmap Baking**: Eliminates wallpaper generation latency, disk thrashing, and Windows wallpaper path caching issues.
2. **Dynamic Multi-Drive Scaling**: Automatically generates `.ini` meter blocks from `state.json` to monitor 13+ drives with real-time usage gauges and alerts.
3. **Event-Driven Signaling**: Notifies Rainmeter via `!Refresh` bangs only when system state or volume metrics change.
4. **DPI & Layout Safety**: Cleanly positioned in screen corner zones without interfering with desktop icons or taskbars.

## 2. Component Design
- **State Capture Engine**: `Source/BackgroundModifier.ps1` extracts machine identity, EFI labels, BCD default, and volume metrics into `C:\BackgroundMotives\assets\state.json`.
- **Dynamic Skin Generator**: Generates `Rainmeter/Skins/BackgroundModifier/Telemetry.ini` dynamically from active `state.json`.
- **Harness & Dispatchers**:
  - `BackgroundPhase2aHarness.ps1`: Automated post-logon scheduled refresh.
  - `BackgroundPhase2bHarness.ps1`: Interactive manual action dashboard.
- **Governance & Quality Gates**: Governed by canonical rules in `.agents/rules/` and verified via `tools/Test-RepoReadiness.ps1`.




---

## App Subsystems & Sliced Specifications
The following modular App slices are documented in dedicated subdirectories per RULE-DOC-007:

| App ID | Title | Directory | Sliced Specifications |
|:---|:---|:---|:---|
| App: 1 | System Identity & State Capture Engine | [`docs/App#1-SystemIdentityStateCaptureEngine/`](file:///docs/App#1-SystemIdentityStateCaptureEngine) | [Arch](file:///docs/App#1-SystemIdentityStateCaptureEngine/Architecture.md) · [Req](file:///docs/App#1-SystemIdentityStateCaptureEngine/Requirements.md) · [Impl](file:///docs/App#1-SystemIdentityStateCaptureEngine/Implementation.md) |
| App: 2 | Telemetry Rendering & Skin Engine | [`docs/App#2-TelemetryRenderingSkinEngine/`](file:///docs/App#2-TelemetryRenderingSkinEngine) | [Arch](file:///docs/App#2-TelemetryRenderingSkinEngine/Architecture.md) · [Req](file:///docs/App#2-TelemetryRenderingSkinEngine/Requirements.md) · [Impl](file:///docs/App#2-TelemetryRenderingSkinEngine/Implementation.md) |
| App: 3 | Desktop & Logon Wallpaper Setter | [`docs/App#3-DesktopLogonWallpaperSetter/`](file:///docs/App#3-DesktopLogonWallpaperSetter) | [Arch](file:///docs/App#3-DesktopLogonWallpaperSetter/Architecture.md) · [Req](file:///docs/App#3-DesktopLogonWallpaperSetter/Requirements.md) · [Impl](file:///docs/App#3-DesktopLogonWallpaperSetter/Implementation.md) |
| App: 4 | Phase Execution Harness & Interactive Dashboard | [`docs/App#4-PhaseExecutionHarnessInteractiveDashboard/`](file:///docs/App#4-PhaseExecutionHarnessInteractiveDashboard) | [Arch](file:///docs/App#4-PhaseExecutionHarnessInteractiveDashboard/Architecture.md) · [Req](file:///docs/App#4-PhaseExecutionHarnessInteractiveDashboard/Requirements.md) · [Impl](file:///docs/App#4-PhaseExecutionHarnessInteractiveDashboard/Implementation.md) |
