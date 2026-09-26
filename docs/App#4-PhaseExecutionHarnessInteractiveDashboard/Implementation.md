# App: 4 - Phase Execution Harness & Interactive Dashboard Implementation

### 1. Constituent Manifest Table
| Relative Path | Role / Layer | Primary Cmdlets / Entrypoints | Test Suite |
|:---|:---|:---|:---|
| `Source/BackgroundPhase2aHarness.ps1` | Phase 2a Automated Runner | `Invoke-Phase2aHarness` | `tools/Test-RepoReadiness.ps1` |
| `Source/BackgroundPhase2bHarness.ps1` | Phase 2b Interactive Dashboard | `Invoke-Phase2bHarness` | `tools/Test-RepoReadiness.ps1` |
| `Modules/SummaryTools.psm1` | Run Summary Formatter | `Format-RunSummary` | `tools/Test-RepoReadiness.ps1` |
| `Modules/TranscriptTools.psm1` | Session Transcriber | `Start-PhaseTranscript` | `tools/Test-RepoReadiness.ps1` |
| `Modules/ErrorTools.psm1` | Diagnostics Engine | `Write-CriticalError` | `tools/Test-RepoReadiness.ps1` |

### 2. Exported Interfaces & State Contracts
- Phase 2a records `state.logon.logonTime` upon first execution.
- Phase 2b routes user action selections and presents live CLI/desktop diagnostics.
