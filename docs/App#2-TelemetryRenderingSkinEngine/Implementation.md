# App: 2 - Telemetry Rendering & Skin Engine Implementation

### 1. Constituent Manifest Table
| Relative Path | Role / Layer | Primary Cmdlets / Entrypoints | Test Suite |
|:---|:---|:---|:---|
| `Source/BackgroundRenderer.ps1` | Phase 2 Orchestrator | `Invoke-BackgroundRenderer` | `tools/Test-RepoReadiness.ps1` |
| `Modules/RenderTools.psm1` | Skin & Meter Generator | `Export-RainmeterSkin`, `New-TelemetryOverlay` | `tools/Test-RepoReadiness.ps1` |
| `Modules/ImageTools.psm1` | Image Processing | `Resize-BackgroundAsset` | `tools/Test-RepoReadiness.ps1` |
| `Modules/ImageStateTools.psm1` | Render Hash Cache | `Test-RenderStateDelta` | `tools/Test-RepoReadiness.ps1` |

### 2. Exported Interfaces & State Contracts
- Reads `state.systemInfo` and updates `state.render` block with rendered timestamps and hash receipts.
- Generates dynamic Rainmeter meter file `C:\BackgroundMotives\assets\Telemetry.ini`.

---
