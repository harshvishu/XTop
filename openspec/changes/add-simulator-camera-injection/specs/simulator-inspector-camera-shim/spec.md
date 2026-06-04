## ADDED Requirements

### Requirement: Shim intercepts the public AVFoundation camera surface
The shim SHALL swizzle, at `+load` time, the public AVFoundation entry points required for an unmodified iOS app to receive injected frames: `AVCaptureSession` start/stop/addInput/addOutput, `AVCaptureDevice` discovery and authorization, `AVCaptureVideoDataOutput` delegate delivery, `AVCaptureMetadataOutput` delegate delivery for barcode and QR types, `AVCapturePhotoOutput.capturePhoto(with:delegate:)`, and `UIImagePickerController(sourceType: .camera)`.

#### Scenario: Camera authorization returns authorized
- **WHEN** the host app calls `AVCaptureDevice.authorizationStatus(for: .video)` after the shim has loaded
- **THEN** the shim returns `.authorized`

#### Scenario: requestAccess invokes completion with true asynchronously
- **WHEN** the host app calls `AVCaptureDevice.requestAccess(for: .video, completionHandler:)`
- **THEN** the shim invokes the completion handler with `true` on a background queue after a small delay that resembles a real OS roundtrip

#### Scenario: VideoDataOutput delegate receives injected frames
- **WHEN** the host app registers an `AVCaptureVideoDataOutput` with a sample-buffer delegate and starts the session
- **THEN** the shim delivers injected frames to the delegate's `captureOutput(_:didOutput:from:)` on the delegate's configured queue, each frame backed by a `CVPixelBuffer` decoded from the latest transport payload

#### Scenario: MetadataOutput delegate receives barcode results from injected frames
- **WHEN** the host app registers an `AVCaptureMetadataOutput` with barcode or QR metadata object types and starts the session
- **THEN** the shim runs barcode detection on each injected frame and delivers any matching results to the delegate

#### Scenario: PhotoOutput captures a still from the current injected frame
- **WHEN** the host app calls `AVCapturePhotoOutput.capturePhoto(with:delegate:)`
- **THEN** the shim delivers a single `AVCapturePhoto` to the delegate, derived from the most recent injected frame

#### Scenario: UIImagePickerController returns the current frame for camera source
- **WHEN** the host app presents `UIImagePickerController(sourceType: .camera)` and the user (or shim auto-confirm) takes a photo
- **THEN** the shim invokes the picker's delegate with the current injected frame as `info[.originalImage]`

### Requirement: Shim is a no-op when env vars are absent
The shim SHALL detect the absence of `XTOP_CAMERA_PORT` or `XTOP_CAMERA_TOKEN` at load time and SHALL install no swizzles in that case, so apps launched without XTop's injection coordinator behave identically to apps with no shim present.

#### Scenario: Missing env vars leave AVFoundation untouched
- **WHEN** the host app is launched without the XTop camera env vars
- **THEN** the shim performs no swizzling and `AVCaptureDevice.default(for: .video)` returns whatever the underlying simulator would normally return

### Requirement: Shim never crashes the host app on swizzle failure
The shim SHALL wrap each swizzle installation so any individual failure is logged via `os_log` to the simulator's unified log but does not raise into the host app process.

#### Scenario: Single swizzle failure is contained
- **WHEN** any single swizzle installation fails at `+load` time
- **THEN** the shim logs the failure and continues installing the remaining swizzles without raising
