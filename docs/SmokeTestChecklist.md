# SmokeTestChecklist.md

Version: 8.0.0

## Purpose
Quick end-to-end verification of phase state transitions and apply behavior.

## Preconditions
1. Windows 11 machine.
2. PowerShell 7 available.
3. Runtime state path exists: `C:\BackgroundMotives\assets`.
4. Scripts available from runtime deployment.

## A. Phase 1 Success Path (Renderer)
1. Run renderer with defaults.
2. Confirm exit success.
3. Inspect `C:\BackgroundMotives\assets\state.json`.
4. Verify:
- `phase.currentPhase` is `Phase1`.
- `phase.phase1Status` is `ready`.
- `phase.blockedReason` is null or empty.

## B. Phase 2 Guard Path (Setter blocked by phase1)
1. Edit state.json and set `phase.phase1Status` to a non-ready value (example: `failed`).
2. Run setter.
3. Confirm setter exits with guard message.
4. Verify state:
- `phase.currentPhase` is `Blocked`.
- `phase.phase2Status` is `blocked`.
- `phase.blockedReason` is `Phase1NotReady`.

## C. Phase 2 Success Path (Setter)
1. Set `phase.phase1Status` back to `ready`.
2. Run setter with desktop apply and lock apply in valid context.
3. Confirm exit success.
4. Verify state:
- `phase.currentPhase` is `Phase2`.
- `phase.phase2Status` is `completed`.
- `phase.blockedReason` is null.

## D. Non-Interactive Elevation Block Path
1. Trigger lock/sign-in apply from a non-interactive non-elevated context.
2. Confirm no UAC relaunch attempt is made.
3. Verify state outcome by execution token capability:

Outcome D1 (expected when token cannot perform machine-scope lock/sign-in apply):
- `phase.currentPhase` is `Blocked`.
- `phase.phase2Status` is `blocked`.
- `phase.blockedReason` is `LockScreenElevationRequiredNonInteractive`.

Outcome D2 (valid when task token already has sufficient rights and apply succeeds):
- `phase.currentPhase` is `Phase2`.
- `phase.phase2Status` is `completed`.
- `phase.blockedReason` is null or empty.

If D2 is observed (for example `LastTaskResult = 0` with completed state), the non-interactive block branch was not exercised in that run.

## E. Interactive Elevation Handoff Path
1. Trigger lock/sign-in apply from interactive non-elevated context.
2. Confirm state persists pending source and requests elevation relaunch.
3. Verify state before relaunch completion:
- `phase.currentPhase` is `Blocked`.
- `phase.phase2Status` is `blocked`.
- `phase.blockedReason` is `LockScreenElevationRequiredInteractiveRelaunch`.

Note: If elevation is accepted and the elevated apply completes quickly, state may already transition to completed when inspected.

## F. Pending Source Lifecycle
1. Ensure pending source exists during elevation-required handoff.
2. Complete elevated lock apply.
3. Verify `transient.pendingLogon` is null after success.

## G. No-Op Phase 2 Path
1. Run setter with no apply targets selected (interactive no-op).
2. Verify state:
- `phase.currentPhase` is `Phase2`.
- `phase.phase2Status` is `completed`.
- `phase.blockedReason` is `NoApplyTargetsSelected`.

## H. Duplicate Elevation Relaunch Suppression
1. Seed `transient.interactiveElevationRelaunchRequestedAtUtc` with current UTC timestamp.
2. Trigger lock/sign-in apply from interactive non-elevated context.
3. Verify duplicate relaunch is suppressed.
4. Verify state:
- `phase.currentPhase` is `Blocked`.
- `phase.phase2Status` is `blocked`.
- `phase.blockedReason` is `LockScreenElevationRelaunchSuppressedDuplicate`.

## I. Automation Enable/Disable Lifecycle (Elevation Required)
1. Run `BackgroundModifier.ps1 -DisableAutomation` from a non-elevated interactive session.
2. Confirm UAC prompt appears and elevated relaunch is requested.
3. Verify scheduled tasks `BackgroundModifier-Startup`, `BackgroundModifier-Renderer`, and `BackgroundModifier-Setter` are disabled.
4. Run `BackgroundModifier.ps1 -EnableAutomation` from a non-elevated interactive session.
5. Confirm UAC prompt appears and elevated relaunch is requested.
6. Verify all three scheduled tasks are enabled again.
7. Verify `state.json` lifecycle section updates:
- `lifecycle.lastAction` equals `DisableAutomation` then `EnableAutomation`.
- `lifecycle.lastStatus` equals `completed` after each successful run.
- `automation.enabledmode` equals `False` after disable and `True` after enable.
