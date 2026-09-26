# App: 1 - System Identity & State Capture Engine Requirements

### 1. Technical Invariants & Prerequisites
- **State Serialization Single Source of Truth**: Gathers volatile (IP, volumes) and non-volatile (hostname, OS, build, BCD default, EFI label) telemetry into `C:\BackgroundMotives\assets\state.json`.
- **Reboot Detection Invariant**: Captures `Win32_OperatingSystem.LastBootUpTime` to detect kernel restarts (cold boots, restarts, crash recovery) while ignoring sleep/hibernate resumes.
- **Cryptographic Fingerprint**: Computes SHA-256 hash across identity fields to enable downstream change detection.
- **Module Purity Invariant**: Modules only compute and return payloads; callers handle atomic `state.json` persistence.

### 2. Safety & Error Handling Boundaries
- **Query Fault Tolerance**: If BCD or EFI label queries fail due to privilege or configuration anomalies, records safe fallback identifiers without halting execution.
- **Atomic File Operations**: All `state.json` updates must use temp-file write + atomic replacement to prevent file corruption during sudden system shutdowns.

---
