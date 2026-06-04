## ADDED Requirements

### Requirement: System injects a bundled shim dylib into a target simulator app via simctl launch
The system SHALL launch the inspected simulator app through `xcrun simctl launch` with `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES` pointing at the bundled `XTopCameraShim.dylib`, so the shim loads into the app process before any app code runs.

#### Scenario: Inject & Launch starts a clean app process with the shim
- **WHEN** the user clicks "Inject & Launch" on the Camera tab for an installed app on a booted simulator
- **THEN** the system terminates the target app if running, then launches it via `simctl launch` with `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES` set to the bundled shim's absolute path

#### Scenario: Launch fails when the bundled shim is missing
- **WHEN** the bundled `XTopCameraShim.dylib` cannot be located in `Bundle.main`
- **THEN** the system surfaces a non-destructive error in the Camera tab and does not attempt to launch the app

### Requirement: System forwards per-launch transport configuration via SIMCTL_CHILD environment variables
The system SHALL forward exactly one localhost port and one cryptographically random 32-byte token per launch to the shim via `SIMCTL_CHILD_XTOP_CAMERA_PORT` and `SIMCTL_CHILD_XTOP_CAMERA_TOKEN`, generated fresh for each "Inject & Launch" invocation.

#### Scenario: Each launch uses a fresh port and token
- **WHEN** the user clicks "Inject & Launch" two times in succession
- **THEN** the system generates a new ephemeral port and a new 32-byte random token for each launch and never reuses a previous value

### Requirement: System exposes an Xcode scheme env-var snippet for non-XTop launches
The system SHALL provide an action that copies a `DYLD_INSERT_LIBRARIES` + `XTOP_CAMERA_PORT` + `XTOP_CAMERA_TOKEN` environment-variable snippet suitable for pasting into an Xcode scheme's Run → Environment Variables, so apps launched directly from Xcode can still be injected.

#### Scenario: User copies a scheme snippet
- **WHEN** the user activates "Copy Xcode scheme snippet" on the Camera tab
- **THEN** the system copies a multi-line `KEY=VALUE` snippet to the pasteboard, including the resolved absolute dylib path and a pinned port/token pair valid for the current Camera-tab session

### Requirement: System terminates the shim transport and offers to terminate the target app on stop
The system SHALL stop the frame source, close the transport listener, and present a non-blocking offer to terminate the target app when the user stops injection, switches the selected app, or closes the Camera tab.

#### Scenario: Stop closes the transport and offers termination
- **WHEN** the user clicks "Stop" while a camera session is active
- **THEN** the system stops the active frame source, closes the localhost listener, and surfaces a non-blocking "Terminate \<bundle-id\>?" affordance
