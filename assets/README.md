# BackgroundModifier Seed Assets

This folder contains deterministic seed assets deployed by Installer.ps1 and used by Setup.ps1 to initialize runtime assets under `C:\BackgroundMotives\assets`.

Current required seed files:
- `state.json` (baseline runtime state scaffold)
- `DesktopBase.jpg` (baseline desktop base)
- `LogonBase.jpg` (baseline logon base)

Rules:
- Setup seeds missing runtime files from this folder.
- Existing runtime files are preserved (no overwrite) for base/state files such as `*Base.jpg` and `state.json`.
- Rendered files (`*_rendered.jpg` / `*_rendered.jpeg`) may be refreshed from seed assets.
