<!--
Components are conceptual parts of the solution. 
They describe responsibilities, behavior, and interactions in the SYSTEM → USER execution pipeline loop.

The Bootmgr Solution is composed of independent components.  
Each component is implemented by one or more PowerShell modules (PS-modules) located in Source\, Modules\, or Install\.
Components are not PowerShell modules (PS-Modules are named .psm1), scripts (.ps1). 
-->
Readme.md

# Bootmgr Solution — Overview

Deterministic Multi‑Boot Identity, Overlays, and Diagnostics for Windows

The Bootmgr Solution is a modular stateful, fully documented toolkit for generating deterministic boot identity overlays, enforcing crisp lock screen rendering, and performing forensic diagnostics across multi‑boot Windows environments. It is designed for safe installation by the end-user, long‑term maintainability, reproducibility, and architectural clarity.

The solution avoids unreliable hacks, has exactly one persistent state file, and relies exclusively on explicit inputs, deterministic logic, and reproducible outputs.

✨ Key Features
- Data concerning physical disk structure is obtained by querying DISKPART and interpreting the output.
- Synthetic ESP ID
A deterministic, volume-label‑dependent identifier for EFI System Partitions, stable across firmware updates, drive letter existance or changes, and imaging workflows.
- Deterministic Overlays
PowerShell‑native rendering of lock screen and desktop overlays containing boot identity, ESP ID, and optional metadata.
- Crisp Lock Screen Enforcement
Registry enforcement to prevent Windows from blurring or recompressing lock screen images.
- Forensic Diagnostics
Comprehensive snapshot of ESPs, BCD stores, Secure Boot state, firmware metadata, and localized Windows Security UI mapping.

**Solution Memory**  
A JSON data structure that is created, loaded, and updated across executions.  
It is generated or amended during the elevated SYSTEM stage and consumed/amended during the user‑session stage.  
Solution Memory persists across runs and is reused by all stages on subsequent executions.


Each functional component of the solution operates independently and produces deterministic outputs based solely on its inputs.

Note: “Component” refers to conceptual solution parts, not PowerShell components (.ps1, .psm1).

- GitHub‑Ready Documentation
Components are documented in Docs\.
Each PS-module includes version headers, synopsis, architectural notes, changelog, and extensibility hooks.

## Documentation Model (Authoritative)

Authoritative Documentation Hierarchy

1. Requirements (Requirements.md)
   - Describes the expected functionality the solution must provide.
   - May reference Implementation.md in rare cases to support understanding of implementation principles.
   - Uses Architecture.md for end-user flow context where useful.

2. Architecture (Architecture.md)
   - End-user view of the solution.
   - Describes phase/time-flow behavior across preparation, install, pre-logon, logon, runtime tests, and disable/uninstall.

3. Implementation (Implementation.md)
   - Describes how the Requirements are or will be implemented.
   - Focuses on design decisions, patterns, and technical realization.
   - May reference ModuleDocumentation.md for detailed component-level behavior.

4. Component Documentation (ModuleDocumentation.md)
   - New, dedicated file.
   - Describes components, their responsibilities, interfaces, and interactions.
   - Serves as the detailed technical reference for the implementation.

📦 Component Architecture
The Bootmgr Solution is composed of independent components. 
The components are implemented as PS-modules (Directories: Source\, Modules\, Install\) in PowerShell.
The term "module" is used as short-hand notation for PS-Module where the distinction is obvious.
Anything affected at runtime may only use the Solution Memory (folder BackgroundMotives\). 

In accordance with the individual type, each PS-module
- Lives in its type-specific directory
- Contains a version header, synopsis, architectural notes, changelog, and extensibility hooks
- Produces a single log file per invocation, overwritten each run
- Accepts explicit inputs only
- Produces explicit outputs only
- supports testing and verification
- checks for warnings, errors and abort-level results whereever this is possible.

Module Overview
See Implementation.md

🔍 Synthetic ESP ID — Rationale & Design
Windows provides no stable, label‑independent identifier for EFI System Partitions. Labels are mutable. Drive letters are unstable. Firmware paths change. GUIDs are not guaranteed.
The Bootmgr Solution introduces a synthetic ESP ID, derived from:
- Partition offset
- Partition size
- Filesystem UUID (if present)
- Hash of the ESP root directory structure
This yields a reproducible identifier that survives:
- Label changes
- Drive letter changes
- Firmware updates
- Multi‑boot environments
- Imaging and restoration workflows
The synthetic ESP ID is the foundation for overlays, diagnostics, and multi‑boot differentiation.

🖼️ Overlay Rendering Workflow
Both lock screen and desktop overlays follow the same deterministic pipeline:
- Acquire synthetic ESP ID
- Collect boot metadata (BCD, firmware, Secure Boot state)
- Render overlay using PowerShell-native drawing
- Write deterministic log file
- Output final PNG
Lock Screen Overlay
- Registry enforcement ensures Windows does not blur or recompress the image
- Output is placed in a dedicated directory for manual or automated deployment
- Overlay includes boot identity, ESP ID, and optional timestamp
Desktop Overlay
- Symmetric to lock screen workflow
- Designed for instant multi‑boot differentiation
- Supports optional color coding based on ESP ID hash

🛡️ Secure Boot & Firmware Diagnostics
The diagnostics module captures:
- Secure Boot state (enabled/disabled)
- DB/DBX/KEK/PK status
- Firmware vendor and version
- ESP enumeration
- BCD store enumeration
- Localized Windows Security UI mapping (e.g., German → English)
This enables reproducible troubleshooting across systems and languages.

📁 Directory Layout (in GIT Repository)
BackgroundModifier/
│
├─ Docs\
|   ├─ README.md
│   ├─ Requirements.md
│   ├─ Implementation.md
│   └─ ...
|
├─ Install\
│   ├─ Setup.ps1
│   ├─ ... see Implementation.md
│   └─ 
├─ Source/
│   ├─ BootIdentity.ps1
│   ├─ ... see Implementation.md
│   └─ 
├─ Modules/
│   ├─ BackgroundNoBlurReg.psm1
│   ├─ ... see Implementation.md
│   └─ 
└─

📁 Directory Layout (Solution Memory)
|
├─ BackgroundMotives
|   ├─ Assets
|   |  ├─ LogonBase.jpg
|   |  ├─ DesktopBase.jpg
|   ├─ Logs
|   │   ├─ BootIdentity.log
│   |   ├─ Overlay-LockScreen.log
│   |   ├─ Overlay-Desktop.log
│   |   ├─ <component>-<timestamp>.log
|   |   └─ ...
|   ├─ Rendered
|   |   ├─ LogonScreen.jpg
|   |   |  DesktopScreen.jpg
|   ├─ SolutionCode
|   |   |  ... symlinks, see Implementation.md
|   |   └─ ...
|   └─ State.json