# App: 4 - Phase Execution Harness & Interactive Dashboard Requirements

### 1. Technical Invariants & Prerequisites
- **Phase Separation Invariant**: Strict isolation between Phase 2a (non-interactive, automated scheduled post-logon refresh) and Phase 2b (interactive, user-initiated action menu).
- **Logon Timestamp Guard**: `logon.logonTime` is recorded exactly once during initial Phase 2a execution per session; Phase 2b must NEVER overwrite or mutate `logonTime`.
- **Operator Visual Feedback**: Phase 2b dashboard must present clear diagnostic summaries, state inspection, and log review options.

### 2. Safety & Error Handling Boundaries
- **Non-Interactive Autorun Guard**: Phase 2a must never invoke interactive prompts or modal dialogs; errors must be logged to disk and exit with non-zero error codes.
- **Session Transcript Isolation**: Captures execution transcripts into isolated per-run logs under `C:\BackgroundMotives\logs\`.
