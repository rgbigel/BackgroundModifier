# BackgroundModifier

Version: 8.0.0

BackgroundModifier is a deterministic PowerShell solution for rendering and applying information-rich backgrounds in Windows logon and desktop contexts.

Platform scope: Windows 11 only.
Installer/runtime prerequisite: PowerShell 7 (`pwsh`) must be available.

## Key Capabilities
1. Deterministic identity and environment capture.
2. Repeatable background rendering pipeline.
3. Consistent apply stage for generated outputs stored in assets.
4. Structured runtime logging for diagnostics.

## Repository Layout
1. `Install`: installation and verification entry scripts.
2. `Source`: active runtime scripts.
3. `Modules`: shared helper modules.
4. `docs`: requirements, architecture, implementation, and change-history documentation.

## Runtime Layout
1. `C:\BackgroundMotives\assets`
2. `C:\BackgroundMotives\logs`

Generated output images are also stored in `C:\BackgroundMotives\assets` and are distinguished from base inputs by filename.

## Versioning Rule
All active scripts, modules, and active documentation pages use the same visible solution version. For this baseline, that value is `8.0.0`.

📁 Directory Layout
Bootmgr-Solution/
│
├─ Modules/
│   ├─ BootIdentity/
│   ├─ Overlay-LockScreen/
│   ├─ Overlay-Desktop/
│   ├─ Registry-Enforce/
│   ├─ Diagnostics/
│   └─ Orchestrator/
│
├─ Logs/
│   ├─ BootIdentity.log
│   ├─ Overlay-LockScreen.log
│   ├─ Overlay-Desktop.log
│   ├─ Registry-Enforce.log
│   └─ Diagnostics.log
│
├─ Output/
│   ├─ LockScreen/
│   └─ Desktop/
│
└─ README.md



🔧 Extensibility Hooks
Each module exposes hooks for:
- Additional metadata fields
- Alternate overlay layouts
- Custom color schemes
- Alternate ESP ID derivation strategies
- Future Python migration
These hooks are documented in each module’s header.

📜 License
To be defined by the repository owner.

🤝 Contributing
Contributions are welcome.
Please follow the module conventions:
- Deterministic logic
- Stateless design
- Per‑module logging
- Version headers
- Architectural notes
- Changelogs
- Extensibility hooks

