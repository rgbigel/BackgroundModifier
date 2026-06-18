# BackgroundModifier

Version: 8.0.0

BackgroundModifier is a deterministic PowerShell solution for rendering and applying information-rich backgrounds in Windows logon and desktop contexts.

Platform scope: Windows 11 only.
Installer/runtime prerequisite: PowerShell 7 (`pwsh`) must be available.

## Key Capabilities
1. Two-phase runtime model:
	- Phase 1 pre-logon identity capture and phase preparation.
	- Phase 2 post-logon enrichment, render completion, and apply.
2. Single-source runtime state in `C:\BackgroundMotives\assets\state.json`.
3. Orchestrated sequence enforcement to block invalid phase transitions.
4. Structured runtime logging is mandatory for diagnostics and recovery.
5. Installer-managed runtime deployment plane in `D:\OneDrive\BTools`.
6. Installer-managed user exposure layer in `D:\OneDrive\cmd`.
7. Context-driven runtime path ownership for per-repository private state/log roots.
8. Versioned module contracts with compatibility pre-check script.

## Repository Layout
1. `Install`: installation and verification entry scripts.
2. `Source`: active runtime scripts.
3. `Modules`: shared helper modules.
4. `docs`: requirements, architecture, implementation, and change-history documentation.

## Runtime Layout
1. Runtime deployment root (non-repository): `D:\OneDrive\BTools`
2. Per-repository deployed runtime: `D:\OneDrive\BTools\<RepositoryName>`
3. Shared module catalog for multi-repository use: `D:\OneDrive\BTools\SharedModules`
4. Inventory and deployment mapping data: `D:\OneDrive\BTools\Inventory`
5. User-facing exposed entrypoints: `D:\OneDrive\cmd`

Within `D:\OneDrive\BTools\<RepositoryName>`, deployable content includes:
1. `Source`
2. `Modules`
3. fallback/base assets required to initialize runtime state

BTools does not hold live runtime state. Runtime state is created and maintained under `C:\BackgroundMotives` and initialized from deployed BTools content during install/update.

Runtime state paths:
1. `C:\BackgroundMotives\assets`
2. `C:\BackgroundMotives\logs`
3. `C:\BackgroundMotives\assets\state.json`

Logging is required and is written only to `C:\BackgroundMotives\logs`, never to `D:\OneDrive\BTools`.
This placement is intentional for multi-boot stability.

Generated output images are stored in `C:\BackgroundMotives\assets` and are distinguished from base input images by filename.

The duplicate pattern `SharedModules\SharedModules` is intentionally not used in this model. Shared modules are exposed from `D:\OneDrive\BTools\SharedModules`.

## User Exposure Layer
1. `D:\OneDrive\cmd` is the user-facing command surface.
2. Installer creates and updates command launchers/links in `cmd` that target runtime entrypoints in `BTools`.
3. `cmd` exposure is Inventory-driven: stale entries are removed, active entries are refreshed.
4. Exposed command mappings are validated during install/update.

## Versioning Rule
All active scripts, modules, and active documentation pages use the same visible solution version. For this baseline, that value is `8.0.0`.

## Runtime Sequencing
1. Phase 1 does not invoke phase 2 setter behavior.
2. Phase 2 runs only when orchestrator validation confirms phase 1 readiness.
3. Transient pending intent is represented in `state.json`, not in a separate marker file.

## Shared Module Contracts
1. Runtime context and state helper interfaces are documented under `docs/contracts`.
2. Compatibility can be pre-checked with `Install/Test-SharedModuleCompatibility.ps1`.
3. Installer and Setup enforce minimum required contract versions before continuing.

## Inventory As Control Surface
1. Installer writes `D:\OneDrive\BTools\Inventory\<RepositoryName>.json` during deploy handoff.
2. Setup updates the same record after verifier completion.
3. Inventory includes module contract versions and install/setup support metadata.

