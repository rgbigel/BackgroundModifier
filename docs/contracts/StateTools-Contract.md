# StateTools Contract

Contract name: StateTools
Contract version: 1.0.0
Required context: RepoRuntimeContext 1.0.0

Purpose:
- Standardize read/write/update operations for state.json.
- Provide stable helpers for phase readiness and transient elevation markers.

Public functions:
- Read-RuntimeState
- Write-RuntimeState
- Update-PhaseState
- Get-PhaseReadiness
- Get-PendingLogonSource
- Set-PendingLogonSource
- Clear-PendingLogonSource
- Mark-InteractiveElevationRelaunch
- Clear-InteractiveElevationRelaunch
- Test-InteractiveElevationRelaunchRecentlyRequested

Behavior guarantees:
- Missing state file returns an empty object.
- Write-RuntimeState ensures parent directory exists.
- Phase helpers preserve existing object shape outside updated fields.
- Timestamps are UTC ISO 8601.

Schema expectations:
- meta.schemaVersion is maintained from context.
- phase.currentPhase, phase.phase1Status, phase.phase2Status, phase.blockedReason are canonical keys.
- transient fields are optional and may be null.

Compatibility policy:
- Signature changes to public functions require major version bump.
- New optional parameters or new additive helper functions are minor version bumps.
- Internal implementation changes with no signature change are patch version bumps.

Pre-check rule for updates:
- Any module update must run a compatibility smoke test in each consumer repo before release.
- A change is blocked if required function names or required parameters differ from this contract.
