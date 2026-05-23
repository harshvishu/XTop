## ADDED Requirements

### Requirement: Status item hosts the XTop monitor
XTop SHALL provide a macOS menu bar status item that gives the monitor a compact presence without requiring a normal app window at launch.

#### Scenario: Monitor appears from the menu bar
- **WHEN** XTop finishes launching
- **THEN** the user can access the monitor from an XTop status item in the macOS menu bar

#### Scenario: Status item shows a live summary
- **WHEN** a telemetry snapshot is available
- **THEN** the status item presents a compact status summary derived from the current snapshot

### Requirement: Status item toggles the dashboard popover
XTop SHALL open and close a dashboard popover from the status item interaction.

#### Scenario: Open dashboard from status item
- **WHEN** the user activates the XTop status item while the dashboard is closed
- **THEN** XTop shows the dashboard popover anchored to the status item

#### Scenario: Close dashboard from status item
- **WHEN** the user activates the XTop status item while the dashboard popover is open
- **THEN** XTop closes the dashboard popover

### Requirement: Popover owns the monitor dashboard surface
XTop SHALL present the monitor content in a popover dashboard that contains the read-only system telemetry and Xcode developer context sections for this change.

#### Scenario: Dashboard uses the monitor sections
- **WHEN** the dashboard popover is shown
- **THEN** the user sees monitor content for system telemetry and Xcode developer context instead of the placeholder refresh panel
