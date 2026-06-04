## ADDED Requirements

### Requirement: Inspector exposes a Grid tab
The system SHALL expose a "Grid" tab in the Simulator Inspector as a peer of the `UserDefaults`, `Keychain`, `App Groups`, and `Camera` tabs.

#### Scenario: Grid tab is selectable in the inspector
- **WHEN** the user selects a simulator in the inspector
- **THEN** the system presents a "Grid" tab alongside the existing inspector tabs
- **AND** selecting the Grid tab renders the grid overlay configuration UI for the selected simulator
