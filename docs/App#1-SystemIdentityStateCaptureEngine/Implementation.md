# App: 1 - System Identity & State Capture Engine Implementation

### 1. Constituent Manifest Table
| Relative Path | Role / Layer | Primary Cmdlets / Entrypoints | Test Suite |
|:---|:---|:---|:---|
| `Source/BackgroundModifier.ps1` | Phase 1 Orchestrator | `Invoke-BackgroundModifier` | `tools/Test-RepoReadiness.ps1` |
| `Modules/SystemInfoTools.psm1` | Identity Harvester | `Get-SystemInfo`, `Get-BootTime` | `tools/Test-RepoReadiness.ps1` |
| `Modules/StateTools.psm1` | State Store Engine | `Get-BackgroundState`, `Set-BackgroundState` | `tools/Test-RepoReadiness.ps1` |
| `Modules/RuntimeContext.psm1` | Context Provider | `Get-RuntimeContext` | `tools/Test-RepoReadiness.ps1` |
| `Modules/Logging.psm1` | Audit Logger | `Write-StructuredLog` | `tools/Test-RepoReadiness.ps1` |

### 2. Exported Interfaces & State Contracts
- Produces immutable `state.systemInfo` block in `C:\BackgroundMotives\assets\state.json`.
- Exports SHA-256 fingerprint in `state.systemInfo.hash`.

---
