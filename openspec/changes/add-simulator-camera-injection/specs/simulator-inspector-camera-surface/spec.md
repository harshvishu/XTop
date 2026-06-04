## ADDED Requirements

### Requirement: Simulator Inspector includes a Camera tab per app
The Simulator Inspector SHALL include a "Camera" tab in the per-app inspector tab strip, available for any installed app on a booted simulator.

#### Scenario: Camera tab is visible for an installed app
- **WHEN** the user selects an installed app in the Simulator Inspector
- **THEN** the inspector tab strip includes a "Camera" tab alongside the existing UserDefaults, App Groups, and Keychain tabs

### Requirement: Camera tab exposes source selection, live preview, and action controls
The Camera tab SHALL present a source picker (Test Pattern, Webcam, Video File, Screen Region) with per-source secondary controls, a live preview of the outgoing feed, and the controls "Inject & Launch", "Stop", "Relaunch", and "Copy Xcode scheme snippet".

#### Scenario: Preview matches the frames sent to the app
- **WHEN** a camera session is active
- **THEN** the Camera tab's preview displays the same frames the system is transmitting to the injected app

#### Scenario: Action controls reflect session state
- **WHEN** no session is active
- **THEN** "Inject & Launch" is enabled and "Stop" / "Relaunch" are disabled
- **WHEN** a session is active
- **THEN** "Stop" and "Relaunch" are enabled and "Inject & Launch" is disabled

### Requirement: Camera tab surfaces injection status clearly
The Camera tab SHALL display a status row containing the inspected app name, its bundle identifier, its launched PID when known, the transport connection state (disconnected / connected / streaming), a live fps counter, and a dropped-frame count for the current session.

#### Scenario: Status reflects connection lifecycle
- **WHEN** the shim has not yet connected after "Inject & Launch"
- **THEN** the status row shows "disconnected"
- **WHEN** the shim has connected and validated its token
- **THEN** the status row shows "connected"
- **WHEN** at least one frame has been transmitted
- **THEN** the status row shows "streaming" with a non-zero fps value

### Requirement: Camera tab presents an instructive empty state when no simulator runtime is detected
The Camera tab SHALL render an empty state with a brief explanation and a link to Xcode's simulator runtime installer when no iOS simulator runtime is detected on the host.

#### Scenario: No runtime detected
- **WHEN** the host has no installed iOS simulator runtime
- **THEN** the Camera tab displays an empty state with installation guidance instead of source pickers and action controls
