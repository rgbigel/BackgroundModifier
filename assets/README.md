# BackgroundModifier Seed Assets

This folder contains deterministic seed assets deployed by Installer.ps1 and used by Setup.ps1 to initialize runtime assets under `C:\BackgroundMotives\assets`.

Current required seed files:
- `state.json` (baseline runtime state scaffold)

Rules:
- Setup seeds missing runtime files from this folder.
- Existing runtime files are preserved (no overwrite) to avoid clobbering active state.
