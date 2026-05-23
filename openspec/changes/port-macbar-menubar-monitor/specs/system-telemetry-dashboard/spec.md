## ADDED Requirements

### Requirement: Baseline system telemetry is sampled
XTop SHALL collect baseline system telemetry snapshots for overall CPU usage, per-core CPU usage, memory usage, storage usage, and disk-cache information without requiring advanced sensor helper setup.

#### Scenario: Baseline telemetry is available
- **WHEN** the monitor refreshes on a supported macOS host
- **THEN** the telemetry snapshot contains baseline CPU, per-core CPU, memory, storage, and disk-cache values or explicit unavailable values for each metric

#### Scenario: Advanced helper is absent
- **WHEN** no advanced sensor helper is configured
- **THEN** baseline telemetry remains available to the dashboard without requiring GPU, temperature, or fan setup

### Requirement: Telemetry dashboard renders live monitor state
XTop SHALL render the current system telemetry snapshot in the dashboard with refresh state and visible fallback handling.

#### Scenario: Dashboard renders current snapshot
- **WHEN** the dashboard has a current telemetry snapshot
- **THEN** it shows the current baseline system values and per-core CPU detail from that snapshot

#### Scenario: Collector data is unavailable
- **WHEN** a baseline metric cannot be collected
- **THEN** the dashboard shows the metric as unavailable without hiding the other telemetry data

### Requirement: Developer process usage is visible when collected
XTop SHALL surface collected CPU and memory usage for relevant local developer processes without making process discovery mandatory for the rest of telemetry.

#### Scenario: Developer processes are collected
- **WHEN** relevant developer processes are detected in a telemetry sample
- **THEN** the dashboard shows their collected usage summaries

#### Scenario: No developer processes are collected
- **WHEN** no relevant developer processes are detected or process lookup fails
- **THEN** the telemetry dashboard still renders the baseline system snapshot
