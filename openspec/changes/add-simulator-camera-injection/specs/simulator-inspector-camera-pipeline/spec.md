## ADDED Requirements

### Requirement: System produces frames from a configurable on-host source at ~30 fps
The system SHALL produce `CVPixelBuffer` frames at a target rate of 30 fps from one of four built-in sources — test pattern, Mac webcam, local video file, or screen region — and SHALL drop frames rather than queue them when the transport cannot keep up.

#### Scenario: Test pattern source produces frames without permissions
- **WHEN** the user selects the "Test Pattern" source
- **THEN** the system produces deterministic color-bar frames at ~30 fps without requesting any system permissions

#### Scenario: Webcam source requests camera permission on first use
- **WHEN** the user selects the "Webcam" source for the first time
- **THEN** the system requests the macOS camera permission lazily and produces frames from the chosen camera once granted

#### Scenario: Video file source loops at end of file
- **WHEN** the user selects a video file and the file reaches its end
- **THEN** the system restarts the file from the beginning and continues producing frames without interruption

#### Scenario: Screen region source requests screen recording permission on first use
- **WHEN** the user selects the "Screen Region" source for the first time
- **THEN** the system requests the macOS screen recording permission lazily and produces frames from the chosen window or rectangle once granted

### Requirement: System transports frames over an authenticated localhost-only channel
The system SHALL transport frames over a TCP listener bound to `127.0.0.1`, gated by a 32-byte token validated on connect, and SHALL refuse any connection that fails token validation.

#### Scenario: Connection without a valid token is refused
- **WHEN** a client connects to the listener and sends an incorrect or missing token
- **THEN** the system closes the connection immediately and does not deliver any frames

#### Scenario: Listener is bound to loopback only
- **WHEN** the listener is started
- **THEN** the system binds exclusively to `127.0.0.1` and does not accept connections from any other interface

### Requirement: System encodes frames as JPEG with configurable quality
The system SHALL encode each delivered frame as JPEG (default quality 0.7) before transmission, using a length-prefixed framed binary protocol with a fixed 4-byte magic header.

#### Scenario: Frame is framed with magic header and length prefix
- **WHEN** the system sends a frame
- **THEN** the on-wire bytes begin with the 4-byte magic `XTCM`, followed by a 4-byte little-endian payload length, followed by the JPEG payload of that exact length

### Requirement: System remembers the last-used source per app
The system SHALL persist the last-used frame source and its parameters keyed by simulator UDID and bundle ID, and SHALL restore that selection when the same app is selected again.

#### Scenario: Per-app source is restored on next selection
- **WHEN** the user selects an app that previously had a source configured
- **THEN** the system restores the previously-used source and its parameters in the Camera tab UI
