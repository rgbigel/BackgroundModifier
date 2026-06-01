Copilot Anchor for BackgroundModifier (v6.0.0)

Use Docs/Readme.md for the authoritative documentation hierarchy.

Meaning of each anchor item:

1. Components are conceptual.
This means a component is a solution capability or responsibility (for example rendering, setup, verification), not a specific file.

2. PS-modules are implementation artifacts.
This means psm1 files are concrete code containers that implement component behavior. They are replaceable implementation units and are not the same thing as the conceptual component definition.

3. Solution Memory is persistent across executions.
This means runtime state and outputs are stored outside the repository and reused between runs.

4. Architecture.md is active, not legacy.
This document provides the end-user time-flow view (preparation, install, stages, tests, disable, uninstall).

5. Follow the documentation hierarchy exactly as defined.
Use the role split documented in Docs/Readme.md:
- Requirements: functional intent and contracts
- Architecture: end-user phase flow
- Implementation: runtime wiring and mechanics
- ModuleDocumentation: module-level contracts and boundaries

6. During repository analysis, include dependency detection for PowerShell modules.
Include direct imports, dot-sourcing or include-style links, and function-level call relationships. Keep XREF notes in Implementation-oriented analysis sections when requested.
