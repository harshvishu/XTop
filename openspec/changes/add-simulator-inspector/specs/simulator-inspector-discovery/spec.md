## ADDED Requirements

### Requirement: System enumerates booted iOS Simulators
The system SHALL list all currently booted iOS Simulators, including device name, runtime, and unique device identifier (UDID).

#### Scenario: Booted simulators are listed
- **WHEN** the Simulator Inspector is opened or refreshed
- **THEN** the system displays every currently booted iOS Simulator with its device name, runtime, and UDID

#### Scenario: No simulators are booted
- **WHEN** no iOS Simulator is currently booted
- **THEN** the system shows an empty state explaining how to boot a simulator

### Requirement: System lists installed apps per simulator
The system SHALL list all third-party apps installed on a selected booted simulator, including bundle identifier, display name, and resolved data container path.

#### Scenario: Installed apps are listed for the selected simulator
- **WHEN** a user selects a booted simulator
- **THEN** the system lists installed apps with bundle identifier, display name, and an icon when available

#### Scenario: Selected app has no data container yet
- **WHEN** a selected app has not yet been launched on the simulator and has no data container
- **THEN** the system displays a clear state indicating the inspector cannot operate until the app has been launched at least once

### Requirement: System resolves App Group containers
The system SHALL resolve the App Group container paths for the selected installed app when present.

#### Scenario: App Group containers are resolved
- **WHEN** a user opens the inspector for an installed app that declares App Group entitlements
- **THEN** the system resolves and exposes the App Group container paths so they can be inspected
