## MODIFIED Requirements

### Requirement: App lifecycle supports launching with injected environment variables
The `AppLifecycleController` SHALL support a "launch with environment" variant that forwards a caller-supplied set of `SIMCTL_CHILD_*` environment variables to `xcrun simctl launch`, so callers can inject `DYLD_INSERT_LIBRARIES` and feature-specific configuration into the target app process. The pre-existing terminate/launch behavior used by non-camera flows SHALL remain available and unchanged.

#### Scenario: Launch forwards SIMCTL_CHILD env vars
- **WHEN** a caller invokes the env-aware launch variant with one or more `SIMCTL_CHILD_*` env vars
- **THEN** the system invokes `xcrun simctl launch` with exactly those env vars set in the child process environment, in addition to whatever simctl normally inherits

#### Scenario: Existing relaunch path is unaffected
- **WHEN** an existing caller invokes the original terminate/launch pair without an env-vars argument
- **THEN** the system behaves identically to today (no `SIMCTL_CHILD_*` env vars are added)
