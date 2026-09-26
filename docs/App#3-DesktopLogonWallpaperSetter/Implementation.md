# App: 3 - Desktop & Logon Wallpaper Setter Implementation

### 1. Constituent Manifest Table
| Relative Path | Role / Layer | Primary Cmdlets / Entrypoints | Test Suite |
|:---|:---|:---|:---|
| `Source/BackgroundSetter.ps1` | Phase 2 Apply Entrypoint | `Invoke-BackgroundSetter` | `tools/Test-RepoReadiness.ps1` |
| `Modules/PathTools.psm1` | Cache Buster & Paths | `Resolve-BusterPath` | `tools/Test-RepoReadiness.ps1` |
| `Modules/ModeTools.psm1` | Mode Resolver | `Get-ApplyMode` | `tools/Test-RepoReadiness.ps1` |
| `Modules/SetFlagsTool.psm1` | Flag Manager | `Get-SetFlags` | `tools/Test-RepoReadiness.ps1` |

### 2. Exported Interfaces & State Contracts
- Interacts with Windows Shell via `SystemParametersInfo` (SPI_SETDESKWALLPAPER) and LockScreen registry policies.
- Logs apply receipts to `state.apply`.

---
