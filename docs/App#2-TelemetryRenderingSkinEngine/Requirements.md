# App: 2 - Telemetry Rendering & Skin Engine Requirements

### 1. Technical Invariants & Prerequisites
- **Zero-Drift State Consumption**: Reads telemetry exclusively from `state.json`; never accepts runtime configuration as script parameters.
- **Conditional Generation**: Re-generates Rainmeter telemetry meters and triggers `!Refresh` bangs only when `state.systemInfo.hash` differs from `state.render.lastSystemInfoHash` or on user override.
- **Dynamic Multi-Drive Scaling**: Dynamically generates `.ini` meter definitions to scale across 13+ drives with usage alerts.

### 2. Safety & Error Handling Boundaries
- **Layout Zone Safety**: Visual meters must remain bound within designated screen zones without obscuring desktop icons, taskbars, or secondary monitor boundaries.
- **Missing Asset Fallback**: If custom overlay assets are missing, falls back to default high-contrast system fonts and colors.

---
