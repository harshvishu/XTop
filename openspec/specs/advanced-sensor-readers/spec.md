# advanced-sensor-readers Specification

## Purpose
TBD - created by archiving change add-advanced-sensor-readers. Update Purpose after archive.
## Requirements
### Requirement: Advanced sensor readers run in-process
XTop SHALL provide an in-process implementation of `AdvancedSensorClient` that reads GPU, temperature, and fan data from IOKit and SMC without requiring a privileged helper, installation step, or system approval prompt.

#### Scenario: Readers are usable on the host
- **WHEN** the running Mac exposes at least one supported advanced sensor source
- **THEN** XTop reports the advanced sensor status as installed, approved, and ready

#### Scenario: Readers cannot reach any source
- **WHEN** neither IOAccelerator nor SMC returns usable data on the host
- **THEN** XTop marks advanced sensors as unsupported and keeps baseline telemetry active

### Requirement: SMC access is read-only and key-restricted
XTop SHALL only issue SMC read requests for a fixed allowlist of temperature and fan keys and SHALL NOT expose any SMC write or fan-control operation.

#### Scenario: Allowlisted key is requested
- **WHEN** the SMC reader is asked to read a key from the temperature or fan allowlist
- **THEN** the reader issues a `kSMCReadKey` request and returns the parsed value or an unavailable reason

#### Scenario: Non-allowlisted key is requested
- **WHEN** any caller passes an SMC key outside the allowlist
- **THEN** the reader refuses the request and reports an explicit allowlist violation reason

#### Scenario: SMC service cannot be opened
- **WHEN** the AppleSMC IOService is unavailable
- **THEN** the reader reports all temperature and fan metrics as unavailable with a host support reason

### Requirement: GPU statistics use IOAccelerator performance data
XTop SHALL read GPU utilization from the first IOAccelerator service that publishes a `PerformanceStatistics` dictionary and SHALL report GPU utilization as unavailable when no accelerator publishes that data.

#### Scenario: Accelerator publishes performance statistics
- **WHEN** an IOAccelerator service publishes a `PerformanceStatistics` dictionary that contains a recognized utilization key
- **THEN** XTop reports a GPU utilization metric value in percent

#### Scenario: No accelerator publishes performance statistics
- **WHEN** no IOAccelerator service publishes a usable utilization key
- **THEN** XTop reports GPU utilization as unavailable with a host support reason

### Requirement: Advanced metrics degrade per source
XTop SHALL return a partial advanced sensor sample when some readers succeed and others fail.

#### Scenario: GPU available, SMC unavailable
- **WHEN** the GPU reader returns a value but the SMC reader cannot open the AppleSMC service
- **THEN** the telemetry snapshot contains a usable GPU metric and unavailable reasons for temperature and fan metrics

#### Scenario: SMC available, GPU unavailable
- **WHEN** SMC returns temperature and fan values but no accelerator publishes performance statistics
- **THEN** the telemetry snapshot contains usable temperature and fan metrics and an unavailable reason for GPU utilization

### Requirement: Advanced sensor settings reflect reader reality
XTop SHALL surface reader status, the user's enabled/disabled preference, and the most recent access test outcome in sensor settings without offering install or approval actions that do not apply to in-process readers.

#### Scenario: User opens sensor settings
- **WHEN** the user opens the sensor settings view
- **THEN** XTop shows whether the readers are usable, whether sensors are enabled, and the latest access test summary

#### Scenario: User disables advanced sensors
- **WHEN** the user disables advanced sensors
- **THEN** XTop stops calling the readers during telemetry refresh and reports GPU, temperature, and fan as disabled

#### Scenario: User tests access
- **WHEN** the user runs a sensor access test
- **THEN** XTop invokes the readers once and records the per-metric results in the diagnostics summary

### Requirement: Baseline telemetry is independent of advanced readers
XTop SHALL collect CPU, per-core CPU, memory, storage, disk-cache, and developer telemetry regardless of advanced reader status, failure, or timeout.

#### Scenario: Readers fail during refresh
- **WHEN** the advanced readers throw or time out during a telemetry refresh
- **THEN** the snapshot still contains baseline telemetry and the advanced metrics are marked unavailable

