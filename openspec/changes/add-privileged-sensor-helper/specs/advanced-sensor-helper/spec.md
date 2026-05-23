## ADDED Requirements

### Requirement: Advanced sensor setup reflects real helper state
XTop SHALL determine advanced sensor readiness from the actual privileged helper installation, authorization, connectivity, and host support state.

#### Scenario: Helper is not installed
- **WHEN** the advanced sensor helper is absent
- **THEN** XTop shows advanced sensors as unavailable with setup guidance and keeps baseline telemetry active

#### Scenario: Helper is installed but not authorized
- **WHEN** the helper product exists but the user has not approved privileged access
- **THEN** XTop reports that approval is required before GPU, temperature, and fan metrics can be sampled

#### Scenario: Helper is connected
- **WHEN** the helper is installed, approved, reachable, and the host supports at least one advanced sensor
- **THEN** XTop reports advanced sensor setup as connected

#### Scenario: Host does not support advanced sensors
- **WHEN** the running Mac or OS does not expose a requested advanced sensor
- **THEN** XTop marks that metric unavailable with a host support reason instead of marking the whole helper setup as failed

### Requirement: Advanced metrics are sampled through the helper
XTop SHALL request GPU, temperature, and fan readings through the privileged helper when advanced sensors are enabled and connected.

#### Scenario: Helper returns all advanced metrics
- **WHEN** the helper returns GPU utilization, temperature, and fan speed values
- **THEN** the telemetry snapshot contains available `gpuPercent`, `temperatureC`, and `fanRPM` metric values with the returned measurements

#### Scenario: Helper returns a partial sample
- **WHEN** the helper returns only some advanced sensor values
- **THEN** XTop records available metrics for returned values and explicit unavailable reasons for missing values

#### Scenario: Advanced sensors are disabled
- **WHEN** the user disables advanced sensors
- **THEN** XTop does not request advanced metrics from the helper and reports GPU, temperature, and fan values as disabled or unavailable

#### Scenario: Helper sampling fails
- **WHEN** the helper request fails, times out, or returns invalid data
- **THEN** XTop records unavailable advanced metric values and an actionable failure reason without blocking the telemetry refresh

### Requirement: Baseline telemetry remains independent of the helper
XTop SHALL continue collecting CPU, per-core CPU, memory, storage, disk-cache, and developer telemetry without requiring advanced sensor helper setup.

#### Scenario: Helper is missing during refresh
- **WHEN** a telemetry refresh runs and no helper is installed
- **THEN** baseline telemetry is sampled normally and only advanced sensor metrics are unavailable

#### Scenario: Helper fails during refresh
- **WHEN** a telemetry refresh runs and the helper connection fails
- **THEN** baseline telemetry remains available in the resulting snapshot

### Requirement: Sensor diagnostics explain setup and sampling failures
XTop SHALL expose advanced sensor diagnostics that distinguish installation, approval, connectivity, host support, disabled, and sampling failure states.

#### Scenario: User opens sensor settings
- **WHEN** the user opens the sensor settings or diagnostics view
- **THEN** XTop shows the current helper status and the latest advanced sensor access test result

#### Scenario: User starts setup
- **WHEN** the user starts advanced sensor setup
- **THEN** XTop attempts the real helper setup or guides the user to the next required approval step

#### Scenario: User tests access
- **WHEN** the user tests advanced sensor access
- **THEN** XTop performs a real helper connectivity and sample check and records the outcome for diagnostics
