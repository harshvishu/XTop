## ADDED Requirements

### Requirement: System clears a simulator's keychain with explicit confirmation
The system SHALL provide a destructive action that deletes the selected simulator's keychain database file (and its SQLite sidecar files) only after explicit user confirmation.

#### Scenario: User confirms keychain clear
- **WHEN** a user invokes "Clear Keychain" and completes the confirmation step
- **THEN** the system deletes the simulator's keychain database and sidecar files and reports success

#### Scenario: User cancels keychain clear
- **WHEN** a user invokes "Clear Keychain" and cancels the confirmation step
- **THEN** the system performs no destructive operation and the keychain remains unchanged

### Requirement: System requires target app termination before keychain clear
The system SHALL require the inspected app to be terminated on the simulator before clearing the keychain.

#### Scenario: Keychain clear is blocked while app is running
- **WHEN** the inspected app is running and the user attempts to clear the keychain
- **THEN** the system blocks the action with a clear message and offers to terminate the app first

### Requirement: Per-item keychain editing is out of scope for v1
The system SHALL NOT expose per-item keychain viewing or editing in v1; only the "clear all" destructive action is supported.

#### Scenario: Inspector communicates v1 scope
- **WHEN** a user opens the Keychain tab
- **THEN** the system clearly indicates that v1 supports only clearing the entire keychain and not per-item inspection
