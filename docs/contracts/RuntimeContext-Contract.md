# RuntimeContext Contract

Contract name: RepoRuntimeContext
Contract version: 1.0.0

Purpose:
- Provide explicit per-repo runtime paths to shared modules.
- Avoid hardcoded cross-repo state locations.

Required fields:
- RepoName (string)
- RuntimeRoot (string)
- AssetsRoot (string)
- LogRoot (string)
- StateFilePath (string)
- SchemaVersion (string)

Construction:
- Use New-RepoRuntimeContext from Modules/RuntimeContext.psm1.
- Each repo entry script builds context once and passes it to shared functions.

Compatibility policy:
- Adding optional fields is a minor version change.
- Removing/renaming required fields is a major version change.
- Consumers must validate with Test-RepoRuntimeContext before state operations.

Consumer obligations:
- Do not derive state paths inside shared functions.
- Do not bypass context with hardcoded fallback paths in business logic.
