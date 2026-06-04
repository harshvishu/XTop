## ADDED Requirements

### Requirement: Grid overlay is configured per simulator UDID
The system SHALL store grid overlay configuration (enabled flag, opacity, per-axis spec) keyed by simulator UDID and SHALL restore it on subsequent launches.

#### Scenario: Configuration persists across launches
- **WHEN** the user enables the grid overlay for a simulator and quits XTop
- **AND** the user relaunches XTop and selects the same simulator
- **THEN** the system restores the previously configured grid spec and enabled state for that simulator UDID

#### Scenario: Configurations are independent per simulator
- **WHEN** the user configures different grid specs for two different simulator UDIDs
- **THEN** the system stores and retrieves each configuration independently

### Requirement: Grid overlay supports uniform and custom spacing per axis
The system SHALL support, independently for the horizontal and vertical axes, both a uniform spacing mode (single point value repeated) and a custom offsets mode (explicit list of cumulative point offsets from the leading/top edge).

#### Scenario: Uniform spacing fills the window dimension
- **WHEN** the user sets vertical mode to uniform with spacing `8`
- **THEN** the system draws vertical lines at x = 8, 16, 24, … pt from the left edge until the Simulator window width is reached

#### Scenario: Custom offsets are cumulative from the edge
- **WHEN** the user sets vertical mode to custom with offsets `[8, 8, 4, 4]`
- **THEN** the system draws vertical lines at x = 8, 16, 20, 24 pt from the left edge of the Simulator window

#### Scenario: Horizontal and vertical axes are independent
- **WHEN** the user configures the horizontal axis to uniform `8` and the vertical axis to custom `[12, 12]`
- **THEN** the system applies each axis spec independently when rendering

### Requirement: Grid overlay renders as a transparent click-through window pinned to the Simulator
The system SHALL render the grid in a transparent, borderless macOS window positioned over the Simulator window for the selected UDID, and the overlay SHALL NOT intercept mouse or keyboard input.

#### Scenario: Simulator stays interactive under the overlay
- **WHEN** the grid overlay is enabled and the user clicks inside the Simulator window
- **THEN** the click reaches the Simulator and the overlay does not consume the event

#### Scenario: Overlay tracks the Simulator window frame
- **WHEN** the user drags or resizes the Simulator window
- **THEN** the system updates the overlay window frame to match without manual refresh

### Requirement: Grid overlay tears down with the Simulator window
The system SHALL automatically remove the overlay when the tracked Simulator window is destroyed, when the simulator shuts down, when the user disables the toggle, or when the user navigates away from the Simulator Inspector destination.

#### Scenario: Overlay disappears on simulator shutdown
- **WHEN** the user shuts down the simulator whose overlay is active
- **THEN** the system removes the overlay window and reflects the disabled state in the Grid tab

#### Scenario: Overlay disappears when leaving the inspector
- **WHEN** the user navigates away from the Simulator Inspector destination
- **THEN** the system removes all active overlays
- **AND** the system restores them when the user returns to the inspector if the persisted configuration is enabled

### Requirement: Grid overlay requires Accessibility permission
The system SHALL require macOS Accessibility permission to locate and track the Simulator window and SHALL surface a clear empty state with a "Grant Accessibility Access" affordance when permission is not granted.

#### Scenario: Permission empty state
- **WHEN** the user opens the Grid tab and XTop is not trusted for Accessibility
- **THEN** the system disables the enable toggle and renders an empty state with an affordance that opens the macOS Accessibility settings pane

#### Scenario: Permission granted enables the tab
- **WHEN** the user grants Accessibility permission and returns to the Grid tab
- **THEN** the system enables the toggle and allows configuring and activating the overlay

### Requirement: Grid overlay uses a fixed line style with configurable opacity
The system SHALL render grid lines as red hairline rules (0.5 pt width) and SHALL expose a single opacity slider in the Grid tab, defaulting to 30% and bounded between 10% and 80%.

#### Scenario: Opacity slider updates the overlay live
- **WHEN** the user adjusts the opacity slider while the overlay is enabled
- **THEN** the system updates the rendered line opacity without re-enabling the overlay

### Requirement: Grid overlay is documented as 100%-zoom only
The system SHALL display a persistent informational notice in the Grid tab stating that alignment accuracy requires the Simulator to be set to 100% zoom (Cmd+0).

#### Scenario: Notice is visible on the Grid tab
- **WHEN** the user opens the Grid tab
- **THEN** the system displays a notice instructing the user to use 100% Simulator zoom for accurate alignment

### Requirement: Custom offsets input is validated with inline feedback
The system SHALL parse the custom offsets text input as a comma-separated list of positive point values and SHALL surface inline parser errors without crashing or applying a partial spec.

#### Scenario: Invalid input shows inline error
- **WHEN** the user enters `"8, abc, 4"` in the custom offsets field
- **THEN** the system shows an inline error and does not update the rendered overlay

#### Scenario: Valid input updates the overlay
- **WHEN** the user enters `"8, 8, 4, 4"` in the custom offsets field
- **THEN** the system parses it as `[8, 8, 4, 4]` and updates the overlay accordingly
