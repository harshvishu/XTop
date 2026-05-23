## MODIFIED Requirements

### Requirement: Advanced sensor readers run in-process
XTop SHALL provide an in-process implementation of `AdvancedSensorClient` that reads GPU data from IOAccelerator and temperature/fan data from IOHIDEventSystemClient, without requiring a privileged helper, installation step, or system approval prompt.

#### Scenario: Readers are usable on the host
- **WHEN** the running Mac exposes at least one supported advanced sensor source
- **THEN** XTop reports the advanced sensor status as installed, approved, and ready

#### Scenario: Readers cannot reach any source
- **WHEN** neither IOAccelerator nor IOHIDEventSystemClient returns usable data on the host
- **THEN** XTop marks advanced sensors as unsupported and keeps baseline telemetry active

### Requirement: Thermal data access is read-only and source-restricted
XTop SHALL read temperature and fan data only via the IOHIDEventSystemClient surface, only from services on Apple vendor usage pages for temperature and power sensors, and SHALL NOT expose any write, calibration, or fan-control operation through this surface.

#### Scenario: Temperature sensor read
- **WHEN** the thermal reader collects temperature readings
- **THEN** the reader enumerates IOHIDEventSystemClient services on the temperature usage page and returns parsed values for services in the recognized temperature range

#### Scenario: Fan sensor read
- **WHEN** the thermal reader collects fan readings
- **THEN** the reader enumerates IOHIDEventSystemClient services for fan-named entries on the recognized usage pages and returns parsed RPM values in the recognized fan range

#### Scenario: Thermal SPI cannot be opened
- **WHEN** the IOHIDEventSystemClient cannot be created on the host
- **THEN** the reader reports all temperature and fan metrics as unavailable with a host support reason and never falls back to a write-capable surface

#### Scenario: Caller requests an unsupported metric
- **WHEN** any caller asks the thermal reader for a metric outside temperature or fan
- **THEN** the reader does not issue any IOHIDEventSystemClient call and reports the metric as unsupported

### Requirement: Advanced metrics degrade per source
XTop SHALL return a partial advanced sensor sample when some readers succeed and others fail.

#### Scenario: GPU available, thermal unavailable
- **WHEN** the GPU reader returns a value but the thermal reader cannot create an IOHIDEventSystemClient
- **THEN** the telemetry snapshot contains a usable GPU metric and unavailable reasons for temperature and fan metrics

#### Scenario: Thermal available, GPU unavailable
- **WHEN** the thermal reader returns temperature and fan values but no accelerator publishes performance statistics
- **THEN** the telemetry snapshot contains usable temperature and fan metrics and an unavailable reason for GPU utilization

### Requirement: Advanced sensor settings reflect reader reality
XTop SHALL surface reader status, the user's enabled/disabled preference, the per-metric capability list, and the most recent access test outcome in sensor settings. The settings UI SHALL NOT present install, approval, "set up helper", or "remove configuration" affordances, because the in-process readers have no such state.

#### Scenario: User opens sensor settings
- **WHEN** the user opens the sensor settings view
- **THEN** XTop shows whether the readers are usable, whether sensors are enabled, the per-metric capability list, and the latest access test summary, and does not show any install, approval, set-up, or remove-configuration control

#### Scenario: User disables advanced sensors
- **WHEN** the user disables advanced sensors
- **THEN** XTop stops calling the readers during telemetry refresh and reports GPU, temperature, and fan as disabled

#### Scenario: User tests access
- **WHEN** the user runs a sensor access test
- **THEN** XTop invokes the readers once and records the per-metric results in the diagnostics summary

## ADDED Requirements

### Requirement: Fan-less hosts report fan as honestly unavailable
XTop SHALL distinguish between "fan read failed" and "no fan hardware is present on this Mac" and SHALL report the latter with a dedicated, non-error reason so the settings UI can present it as the expected state rather than a malfunction.

#### Scenario: Mac without fan hardware
- **WHEN** the host has no fan service registered with the thermal SPI
- **THEN** the advanced sensor sample reports fan RPM as unavailable with a reason indicating no fan hardware is present, not an error reason

#### Scenario: Mac with fan hardware but no readable RPM
- **WHEN** the host has fan services registered but they do not return a usable RPM value
- **THEN** the advanced sensor sample reports fan RPM as unavailable with a read-failure reason distinct from the no-hardware reason
