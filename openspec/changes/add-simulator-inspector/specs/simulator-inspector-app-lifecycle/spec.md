## ADDED Requirements

### Requirement: System terminates and launches the inspected app
The system SHALL support terminating the inspected app on its simulator and launching it again so that inspector edits take effect.

#### Scenario: Relaunch action runs terminate then launch
- **WHEN** the user invokes "Relaunch App"
- **THEN** the system terminates the inspected app on its simulator and launches it again

#### Scenario: Termination failure surfaces an error
- **WHEN** termination of the inspected app fails
- **THEN** the system reports the failure and does not attempt to launch the app

### Requirement: System suggests relaunch after UserDefaults writes
The system SHALL surface a non-blocking suggestion to relaunch the inspected app after any successful `UserDefaults` write.

#### Scenario: Successful write surfaces relaunch suggestion
- **WHEN** a `UserDefaults` write succeeds
- **THEN** the system displays a non-blocking affordance to relaunch the inspected app
