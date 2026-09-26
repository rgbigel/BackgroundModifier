# App: 3 - Desktop & Logon Wallpaper Setter Requirements

### 1. Technical Invariants & Prerequisites
- **Two-Step Cache-Busting Refresh**: Desktop apply must swap to a temporary unique path before setting the final stable path to defeat Windows Explorer image path caching.
- **Two-Tier Logon Apply**: Applies logon/lock wallpaper via primary Windows API, falling back to policy-registry apply when the API is unavailable.
- **Audit Logging**: Every apply execution must log the selected branch (`DesktopRefreshTwoStep`, `LogonApiPrimary`, `LogonPolicyFallback`) and fallback reason.

### 2. Safety & Error Handling Boundaries
- **Registry & API Resilience**: Registry modifications must be verified immediately post-write; failures must log descriptive errors without interrupting desktop shell operations.
- **File Access Interlocks**: Verifies image file readability and dimensions before attempting shell apply.

---
