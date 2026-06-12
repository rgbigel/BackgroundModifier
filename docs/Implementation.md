# Architecture.md  
**Version:** 7.0.0  
**Profile:** default  
**Author:** Rolf Bercht  

## Purpose
- Provide an end‑user architecture view of the solution.  
- Explain the solution as a time‑flow across phases.  
- Show what to prepare, what happens during runtime stages, what can be re‑run, and how to disable/uninstall.  

## Scope Note
- This document is user‑centric and phase‑centric.  
- Requirements define functional intent.  
- Implementation defines runtime wiring and technical mechanics.
- Platform scope is Windows 11 only.

---

## 1. End‑User Time Flow

The solution is experienced in ordered phases:

1. Preparation before installation  
2. Installation, configuration, and installation checks  
3. Runtime Stage A: pre‑logon (startup/system context)  
4. Runtime Stage B: logon and post‑logon (interactive user context)  
5. Runtime tests and re‑runnable operations after logon  
6. Disable and uninstall  

**Solution behavior (7.0.0):**

- A single unified background is produced for both the Windows logon screen and the desktop.  
- The background is refreshed automatically at each logon.  
- The lock screen displays the background clearly without blur.  
- System and session information is collected and used to generate the background.

---

## 2. Phase 1: Preparation Before Installation

When preparing or installing, be sure that:

1. Required base assets are available.  
2. Sufficient permissions exist for installation and for startup/logon automation.  
3. You are aware that the solution operates in two runtime stages:
   - Pre‑logon stage  
   - Logon stage  

Be aware that:

1. One stage collects system and boot identity.  
2. Another stage renders and applies the unified background.  
3. Each stage produces logs and outputs that can be reviewed later.

---

## 3. Phase 2: Installation, Configuration, and Checks

### What Happens
1. The solution is installed and its runtime structure is set up.  
2. Startup and logon automation is configured.  
3. Installation checks verify prerequisites and consistency.  
4. Operational entry points are placed in the user’s command directory.  
5. A single elevated admin shell provides a menu‑driven operational interface.

### What You See/Do
1. Review setup and validation results.  
2. Address any reported prerequisite gaps.  
3. Re‑run installation checks after making corrections.

---

## 4. What Is Created and Provided on the User PC

After installation/configuration, the system contains:

1. A runtime data area used by the solution.  
2. A shared state file used across startup and logon stages.  
3. A rendered unified background image for logon and desktop.  
4. Logs and diagnostics for troubleshooting.  
5. Automation configuration for startup/logon execution.  
6. Verification and maintenance routines available after installation.

### Interpretation
1. These artifacts support predictable behavior, diagnostics, and controlled re‑runs.  
2. Disable/uninstall options determine whether these artifacts remain or are removed.  
3. Technical details and paths are documented in *Implementation.md*.

---

## 5. Phase 3: Runtime Stage A (Pre‑Logon)

### What Happens (User‑Level View)
1. System and boot identity information is collected.  
2. Shared state is created or updated with startup‑stage data.  
3. Logs for this stage are recorded.  
4. The collected information is later used to generate the unified background.

### Be Aware
1. This stage is non‑interactive.  
2. No background is rendered or applied here.

---

## 6. Phase 4: Runtime Stage B (Logon and Post‑Logon)

### What Happens (User‑Level View)
1. Shared state is loaded and enriched with session context.  
2. The unified background is rendered.  
3. The rendered background is applied to:
   - the Windows logon screen  
   - the desktop wallpaper  
4. Logs for this stage are recorded.  
5. The lock screen blur is disabled so the background appears clearly.

### After Logon, You Can
1. Inspect logs and validation results.  
2. Run verification tools.  
3. Re‑run supported configuration or test operations.

---

## 7. Phase 5: Runtime Tests and Re‑Run Model

### Available Runtime Tests
1. Installation/setup verification.  
2. Startup‑stage verification.  
3. Logon‑stage verification.  
4. Configuration verification.  
5. Non‑destructive repair/update routines.

### User‑Level Interpretation
1. Installation verification checks that prerequisites remain valid.  
2. Startup‑stage verification checks that identity information can be collected.  
3. Logon‑stage verification checks that the unified background can be rendered and applied.  
4. Configuration verification checks that active settings are valid.  
5. Repair/update routines help recover from partial setup drift.

### Execution Context
1. Some checks run during startup, others after logon.  
2. Implementation defines exact entry points and context rules.

### Rules
1. Re‑runs should behave predictably.  
2. Re‑runs avoid destructive side effects.  
3. Shared‑state integrity is preserved across stages.

---

## 8. Phase 6: Disable and Uninstall

### Disable
1. Stops startup/logon automation without removing data.  
2. Can be reversed without reinstalling.

### Enable
1. Restores automation.  
2. Does not reinstall or remove data.

### Uninstall
1. Removes automation and configuration.  
2. Removes or preserves runtime data depending on your choice.  
3. Never modifies repository source.

### Cleanup
1. Removes stale logs/outputs without uninstalling.  
2. Does not remove automation unless explicitly chosen.  
3. Disable/enable affects automation only.

### Uninstall Scope Options
1. Keep diagnostics and state for later analysis.  
2. Remove diagnostics and state for full removal.  
3. Keep base assets for later re‑installation.

### Operational Entry‑Point Model
1. Canonical source remains in repository paths.  
2. Runtime data resides in the solution’s runtime directory.  
3. Operational entry points include install, verify, enable/disable, uninstall, cleanup, and source‑level actions.  
4. Source actions include identity collection, rendering, and apply operations.  
5. Apply runs automatically after successful rendering.  
6. Setup may elevate itself when required.

---

## 9. Cross‑Document Consistency Rules
1. *Requirements.md*: functional outcomes and contracts.  
2. *Architecture.md*: end‑user time‑flow and stage behavior.  
3. *Implementation.md*: technical realization.  
4. *ModuleDocumentation.md*: module‑level 