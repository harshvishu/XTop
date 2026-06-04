## Why

The iOS Simulator has no built-in camera support — `AVCaptureDevice.default(for: .video)` returns `nil`, and Apple's Simulator menu offers no camera passthrough as of Xcode 26.1. Every developer building a QR scanner, barcode reader, document capture flow, ML/Vision pipeline, or AR prototype either (a) stubs out the camera path with `#if targetEnvironment(simulator)`, (b) tests only on a physical device, or (c) ships a brittle "use a photo instead" fallback. Existing OSS tools (iCimulator, SimulatorCamera) and commercial tools (RocketSim) solve this, but the OSS tools require the developer to add an SDK to their iOS app source — which directly contradicts the Simulator Inspector's stated goal of helping developers debug apps **without going into the code**.

XTop is already the natural home for this: the Simulator Inspector already enumerates booted simulators, lists installed apps, and resolves app data containers. Routing macOS-side video (webcam, video file, screen region, or test pattern) into an installed simulator app — with zero changes to the app's source — extends that surface in the exact spirit of the existing tabs.

A Phase 0 spike (2026-06-04) confirmed the foundational technique: setting `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES` on `xcrun simctl launch` successfully injects an ad-hoc-signed `arm64-apple-ios-simulator` dylib into a launched app process on Xcode 26.1.1 / iOS 26.1 simruntime, including into a `SystemApp`-classified process (`com.apple.Preferences`). The architecture is real and uses only public API.

## What Changes

- Add a new "Camera" tab to the Simulator Inspector for any selected installed app.
- Ship an `XTopCameraShim` simulator-targeted dynamic library, bundled inside the macOS app, that swizzles AVFoundation entry points (capture session start/stop, video data output delivery, authorization status, metadata output for barcode detection) to deliver frames produced by XTop.
- Add a frame-source pipeline on the macOS side that produces `CVPixelBuffer` frames at ~30 fps from one of: a built-in test pattern (color bars / counter), the Mac webcam (via `AVCaptureDevice` on the host), a local video file (looped via `AVAssetReader`), or a screen region (via `ScreenCaptureKit`).
- Add a localhost-only transport (TCP on a randomly chosen high port, per-launch token-authenticated) between the macOS frame producer and the in-simulator shim.
- Add a launch flow that wraps `xcrun simctl launch` with `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES` and a small set of `SIMCTL_CHILD_XTOP_CAMERA_*` environment variables (port, auth token, frame format hints). Always `terminate` first, then `launch`, mirroring the existing relaunch pattern.
- Add a Camera-tab preview panel that shows exactly what frames are being delivered to the app, plus a status row indicating whether the target app is currently injected and streaming.
- Add an optional "Generate Xcode scheme snippet" affordance that emits a `DYLD_INSERT_LIBRARIES` + env-var block the developer can paste into the Run scheme, so Xcode-launched debug runs also pick up the shim without going through XTop's launch button.

## Capabilities

### New Capabilities
- `simulator-inspector-camera-injection`: Inject a bundled simulator shim into a target app via `simctl launch` env vars, manage the injection lifecycle (terminate, launch, stop), and surface clear status.
- `simulator-inspector-camera-pipeline`: Produce `CVPixelBuffer` frames on macOS from configurable sources (test pattern, webcam, video file, screen region) and stream them to the in-simulator shim over an authenticated localhost transport.
- `simulator-inspector-camera-shim`: An iOS-simulator-targeted dynamic library, bundled in the XTop app, that swizzles the public AVFoundation capture surface to deliver injected frames to the host app's existing capture pipeline.
- `simulator-inspector-camera-surface`: A "Camera" tab inside the Simulator Inspector that selects a source, previews the outgoing feed, and drives the launch / relaunch / stop actions for the inspected app.

### Modified Capabilities
- `simulator-inspector-app-lifecycle`: Extended to support a "launch with environment" variant that injects the shim and forwards camera-pipeline configuration via `SIMCTL_CHILD_*` env vars. The existing terminate/launch pair remains untouched for non-camera flows.
- `simulator-inspector-surface`: Extended to include a "Camera" tab in the per-app inspector tab strip, alongside UserDefaults / App Groups / Keychain.

## Impact

- Adds a new feature area with a non-trivial build surface: a SwiftPM target (or build phase) that compiles a dual-arch (`arm64` + `x86_64`) iOS-simulator dynamic library and bundles it inside the macOS app's `Resources/`.
- Adds a host-side `AVFoundation` + `ScreenCaptureKit` capture path inside XTop. This requires the macOS camera entitlement (`com.apple.security.device.camera`) **only when the user selects the webcam source**, and screen recording permission only when the screen-region source is selected. Both should be requested lazily, on first use, with clear UI explaining why.
- Adds a localhost TCP listener that is bound to `127.0.0.1`, authenticated per launch with a random token, and torn down when the Camera tab is closed or the target app exits. No external network exposure.
- Does **not** modify Git, sensor, dashboard, or non-camera Simulator Inspector capabilities.
- Distribution: the bundled simulator dylib must be ad-hoc signed (or co-signed with XTop's Developer ID) at build time. Phase 0 confirmed ad-hoc signing is sufficient for injection; the GH Actions distribution pipeline (`add-github-actions-build-distribution`) will need a small addition to (re)sign the dylib after the macOS app is signed.
- The Camera tab is a developer-facing tool that can drive arbitrary frame data into a target app. UX must make it obvious which app is currently injected and stop injection cleanly when the tab is left or the app is terminated.

## Non-Goals (v1)

- Injecting into apps that XTop did not launch (post-attach injection is out of scope; the user must launch via XTop's "Inject & Launch" button or via the generated Xcode scheme snippet).
- Real-device support — physical iOS devices remain out of scope (same boundary as the rest of Simulator Inspector).
- Mocking `AVCaptureMovieFileOutput` recording-to-disk paths, ProRes/HEVC capture, multi-cam sessions, or depth/LiDAR / `AVCaptureDepthDataOutput`. v1 covers the high-frequency surface: `AVCaptureVideoDataOutput` (frame delivery), `AVCaptureMetadataOutput` (barcode/QR), `AVCapturePhotoOutput` (still capture), `AVCaptureDevice.authorizationStatus`, and `UIImagePickerController(sourceType: .camera)`.
- VisionKit `DataScannerViewController` interception (deferred to a follow-up; v1 will document the limitation).
- Audio capture (`AVCaptureAudioDataOutput`) — video only in v1.
- Routing frames into apps running on a physical Mac's iOS-on-Mac (Catalyst) environment.
- Recording the simulated feed to disk from XTop's side (deferred; the user can record via QuickTime against the simulator window).
- A general-purpose plugin system for custom frame sources — the four v1 sources (test pattern, webcam, video file, screen region) are fixed.
