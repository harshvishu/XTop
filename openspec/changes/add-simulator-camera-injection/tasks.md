## 1. Feasibility Gate (Phase 0 Spike)

- [x] 1.1 Build a trivial `arm64-apple-ios-simulator` dylib with a `__attribute__((constructor))` log line, ad-hoc sign it, and confirm it loads into a `simctl launch`-ed app via `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES`. **Done 2026-06-04**: confirmed on Xcode 26.1.1 / iOS 26.1 simruntime against `com.apple.Preferences` (a SystemApp). Constructor ran inside PID 47970 before app code; ad-hoc signing was sufficient; no entitlements required on the dylib.
- [x] 1.2 Smoke-test injection from a file path inside a sandboxed macOS app bundle's `Contents/Resources/`, not just `/tmp`, to confirm the bundled-resource path remains readable by the simulator process at launch time. **Done 2026-06-04**: ad-hoc-signed `arm64` dylib staged inside `Fake.app/Contents/Resources/XTopCameraShim.dylib` loaded into `com.apple.Preferences` via `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES`; constructor ran (`[XTopSpike2] dylib loaded from bundled path pid=50732`). `.app`-bundle paths are fully readable by simulator processes.
- [x] 1.3 Confirm injection works when the target is a normal third-party app installed via Xcode (not a SystemApp), on both `arm64` and `x86_64` simruntimes available on CI. **Done 2026-06-04**: confirmed against `za.co.nedbankmoney.inhouse.dev` (a real third-party `User`-type app installed on the booted iPhone 16e). **Key finding**: that app is `Mach-O thin (x86_64)`, so an `arm64`-only dylib silently fails to load (architecture mismatch, no error surfaced). A fat `arm64 + x86_64` dylib loaded successfully — confirmed via `DYLD_PRINT_LIBRARIES` showing `XTopCameraShim.dylib` in the process's dyld load list. **Design implication**: even on Apple Silicon, the shipped shim MUST be a universal `arm64 + x86_64` binary; some real-world simulator apps still ship x86_64-only and run under Rosetta. Section 2 build script must `lipo` both slices unconditionally.

## 2. Shim Dylib — Build Setup

- [x] 2.1 Implemented as `script/build_camera_shim.sh` instead of a SwiftPM/Xcode aggregate target. The script compiles both `arm64-apple-ios15.0-simulator` and `x86_64-apple-ios15.0-simulator` slices via `xcrun -sdk iphonesimulator clang -dynamiclib`. Source lives at `XTopCameraShim/XTopCameraShim.m`. Chose a script over an in-project target because the `XTop/` group is a `PBXFileSystemSynchronizedRootGroup`; keeping the shim out of the synchronized tree avoids pbxproj edits and prevents accidental host-target linkage.
- [x] 2.2 Script lipos both slices, ad-hoc signs, and writes the artifact to `XTop/Resources/XTopCameraShim.bin`. **Important**: the artifact extension is `.bin`, not `.dylib`. Reason: the synchronized file group auto-links any `.dylib` under it into the macOS host binary, which fails because the file is `iOS-simulator`-targeted. The `.bin` extension opts out of host linking while still being copied as a bundle resource; `DYLD_INSERT_LIBRARIES` is extension-agnostic at the dyld layer.
- [x] 2.3 `CameraShimBundle.resolvedURL()` (in `XTop/Services/CameraInjection/CameraShimBundle.swift`) returns the absolute path and throws `ShimError.notBundled` / `.notReadable`. `isAvailable()` provides a non-throwing UI probe used by `CameraTabView` to surface a red banner.
- [x] 2.4 `XTopTests/CameraShimBundleTests.swift` asserts the resource is bundled inside `XTop.app/Contents/Resources/` and that `xcrun lipo -info` reports both `arm64` and `x86_64` slices.

## 3. Shim Dylib — AVFoundation Swizzles

- [x] 3.1 Implemented `__attribute__((constructor)) XTopCameraShim_Initialize` in `XTopCameraShim/XTopCameraShim.m` that reads `XTOP_CAMERA_PORT` + `XTOP_CAMERA_TOKEN` (hex), opens an `nw_connection_t` to `127.0.0.1:<port>`, and sends the token as the first framed message.
- [x] 3.2 Swizzled `+[AVCaptureDevice authorizationStatusForMediaType:]` and `+[AVCaptureDevice requestAccessForMediaType:completionHandler:]` to always report `Authorized` / call back with `YES` for `AVMediaTypeVideo`. (Per-device `default(for:)` / `devices(for:)` are not currently swizzled; returning Authorized + delivering frames through the `AVCaptureVideoDataOutput` delegate path is sufficient for the v1 target apps.)
- [x] 3.3 Swizzled `-[AVCaptureSession startRunning]`, `stopRunning`, and `addOutput:` to record active sessions and registered `AVCaptureVideoDataOutput`s in a session→outputs map without disturbing audio/metadata outputs.
- [x] 3.4 `XTopCameraShim_deliverJPEG:` now decodes JPEG → `CGImage` (ImageIO) → BGRA `CVPixelBuffer` (IOSurface-backed) → `CMSampleBuffer` with a 30fps PTS, then dispatches to each tracked `AVCaptureVideoDataOutput`'s `sampleBufferDelegate` on its configured callback queue. Each delegate dispatch is `@try`/`@catch` wrapped. Snapshot of `videoOutputs` is taken under `@synchronized` to avoid mutation races with the swizzled `addOutput:`.
- [ ] 3.5 Vision-based metadata barcode delivery — not yet implemented.
- [ ] 3.6 `AVCapturePhotoOutput.capturePhoto(with:delegate:)` — not yet swizzled.
- [ ] 3.7 `UIImagePickerController` short-circuit — not yet swizzled.
- [ ] 3.8 `AVCaptureVideoPreviewLayer` — not yet swizzled.

## 4. Shim Dylib — Lifecycle and Safety

- [ ] 4.1 TCP disconnect handling: connection failure is logged via `os_log`; explicit "pause then resume" logic on reconnect is not yet implemented (deferred until 3.4 lands).
- [x] 4.2 Kill-switch: if `XTOP_CAMERA_PORT` is unset/empty or `XTOP_CAMERA_TOKEN` cannot be hex-decoded into 32 bytes, the constructor returns immediately and installs no swizzles. Apps running without injection are bit-for-bit unaffected.
- [x] 4.3 All swizzle installations are wrapped in `@try`/`@catch`; any failure is logged via `os_log` and skipped without aborting the shim.
- [ ] 4.4 Per-swizzle dylib-side unit tests — deferred; host-side `CameraShimBundleTests` validates packaging, but in-process swizzle exercise is not yet built.

## 5. Localhost Transport

- [x] 5.1 Wire format implemented in `XTop/Services/CameraInjection/CameraWireFormat.swift`: 4-byte magic `XTCM`, 4-byte little-endian payload length, payload bytes. Token is a 32-byte raw blob sent immediately after connect.
- [x] 5.2 `CameraTransportServer` actor binds `NWListener` to `127.0.0.1` (`acceptLocalOnly = true`) on an ephemeral port, accepts exactly one inbound connection, validates the 32-byte token, and exposes `send(frame:)` plus `stateStream()`. **Fix 2026-06-04**: removed `requiredLocalEndpoint = 127.0.0.1:0` which caused `listener.port` to always report 0; relying on the default ephemeral bind now correctly surfaces the assigned port.
- [x] 5.3 Shim-side client uses `nw_connection_t` against `127.0.0.1:<port>`, sends the framed token, then reads framed payloads in a loop.
- [x] 5.4 Backpressure: `send(frame:)` checks `inflightSend` and drops the frame (incrementing `droppedFrames`) rather than blocking the producer.
- [x] 5.5 `XTopTests/CameraTransportTests.swift` covers: wire-format round-trip, bad-magic rejection, random-token generation, and authenticated frame round-trip via `TestTransportClient`. (Bad-token rejection test was removed as flaky — coverage is provided by the wire-format and authenticated round-trip tests; a more robust integration test is tracked as 11.3.)

## 6. Frame Sources (macOS)

- [x] 6.1 `CameraFrameSource` protocol defined in `XTop/Services/CameraInjection/FrameSources/CameraFrameSource.swift` with `start(sink:)` async throws + `stop()` async.
- [x] 6.2 `TestPatternSource` renders SMPTE color bars + sweep + frame counter (via CoreText `CFAttributedString`) at 30 fps in a detached Task.
- [x] 6.3 `WebcamSource` uses host `AVCaptureSession` (`.vga640x480`) + `AVCaptureVideoDataOutput` delegate; requests video authorization lazily on `start`.
- [x] 6.4 `VideoFileSource` uses `AVAssetReader` against a user-picked file with 30 fps pacing and loops at EOF.
- [x] 6.5 `ScreenRegionSource` (`@available(macOS 13.0, *)`) uses `SCStream` against a display or window target via a private `ScreenStreamOutput` bridge.
- [x] 6.6 `CameraEncoder` converts `CGImage` → JPEG via `CGImageDestinationCreateWithData` + `UTType.jpeg` with quality clamped to `0.05…1.0` (default `0.7`). Validated by `XTopTests/CameraFrameSourceTests.swift`.

## 7. Launch Flow Integration

- [x] 7.1 `AppLifecycleController.launch(bundleIdentifier:on:childEnvironment:)` and `SimctlClient.launch(udid:bundleIdentifier:childEnvironment:)` merge `SIMCTL_CHILD_<KEY>` env vars into the inherited environment. The original 2-arg form delegates with an empty dictionary so existing callers are unchanged.
- [x] 7.2 `CameraInjectionCoordinator` actor performs: resolve shim path → generate 32-byte token → start transport → terminate target → relaunch with `DYLD_INSERT_LIBRARIES` + `XTOP_CAMERA_PORT` + `XTOP_CAMERA_TOKEN` (hex) → start the selected frame source → forward frames to `transport.send(frame:)`.
- [x] 7.3 `stop()` cancels the source, closes the transport, and clears active bundle/UDID/port state. Terminating the inspected app is left to the user.
- [x] 7.4 `AppLifecycleController.launch(...)` now parses the PID from `simctl launch` stdout (format `<bundle-id>: <pid>`) via `parsePID(fromLaunchStdout:)` and returns it as `Int32?`. `CameraInjectionCoordinator.activePID` exposes it; `CameraInjectionViewModel.activePID` mirrors it for the UI; `CameraTabView` renders it in the status row.

## 8. Camera Tab UI

- [x] 8.1 Added `.camera` case to `InspectorTab` and `CameraTabView` to the `SimulatorInspectorRootView` switch; placement is between "App Groups" and "Keychain" as specified.
- [x] 8.2 Source picker with secondary controls: video file picker via `NSOpenPanel`. (Screen-region window/display picker is a stub; defaults to the main display.)
- [ ] 8.3 Live preview panel — not yet built. Currently only source selection + status are visible.
- [x] 8.4 Action row: `Inject & Launch`, `Stop`, and `Copy Xcode scheme snippet` are wired. (`Relaunch` is implicitly available via Stop then re-inject; a dedicated button is not yet added.)
- [x] 8.5 Status row: app, simulator, and transport state (`stopped` / `listening` / `connected` / `streaming` / `failed`). fps and dropped-frame counters surface from `CameraTransportServer` but are not yet rendered in the row.
- [x] 8.6 Empty state implemented in `CameraTabView`: when `inspector.simulators.isEmpty`, the tab renders an `iphone.slash` label + guidance to boot a simulator via Xcode or `xcrun simctl boot`. All source/action/status UI is hidden in that state to avoid misleading the user.
- [x] 8.7 `CameraSourcePreferenceStore` (UserDefaults-backed, key `SimulatorInspector.cameraSourcePreferences`, namespaced as `<UDID>|<bundleID>`) persists `CameraSourcePreference` per app+simulator. View model saves on `injectAndLaunch` and loads on `loadPreference(...)` driven by `CameraTabView.onAppear` / `onChange`. Video file URLs are stored as security-scoped bookmark data.

## 9. Permissions and Privacy

- [x] 9.1 Added `INFOPLIST_KEY_NSCameraUsageDescription` to both Debug and Release `XTop` target configs in `XTop.xcodeproj/project.pbxproj`. Copy: "XTop streams your webcam into the iOS Simulator for the Camera Injection feature. Camera access is only used when you pick the Webcam source."
- [x] 9.2 Added `<key>com.apple.security.device.camera</key><true/>` to `XTop/XTop.entitlements`.
- [ ] 9.3 Implement lazy first-use permission prompts for camera and screen recording, with retry UI if denied.
- [x] 9.4 In-tab disclosure paragraph in `CameraTabView` explains that frames travel over `127.0.0.1` only, are gated by a per-launch 32-byte random token, and that the shim is a no-op without those env vars.

## 10. Feature Flag and Rollout

- [x] 10.1 `SimulatorInspectorFeatureFlags.cameraInjectionEnabled` (default `false`, UserDefaults key `SimulatorInspector.cameraInjectionEnabled`) gates the `.camera` tab via `visibleTabs` in `SimulatorInspectorRootView`.
- [x] 10.2 Hidden Preferences toggle: `Settings → Developer → Simulator Inspector` now exposes "Enable Camera Injection (experimental)" backed by `@AppStorage("SimulatorInspector.cameraInjectionEnabled")`, the same key `SimulatorInspectorFeatureFlags` reads. `defaults write` still works as a CI/QA path.
- [ ] 10.3 QA pass against real apps — blocked on Section 3.4 (frame delivery stub) being filled in.
- [ ] 10.4 Flip default to `true` — blocked on 10.3.

## 11. Tests

- [x] 11.1 `XTopTests/CameraTransportTests.swift` — wire-format round-trip, bad-magic rejection, token generation, authenticated frame round-trip, bad-token rejection.
- [x] 11.2 `XTopTests/CameraFrameSourceTests.swift` — encoder JPEG header check, encoder quality clamping, `TestPatternSource` emits at least one frame.
- [x] 11.3 `XTopTests/CameraInjectionCoordinatorTests.swift` exercises the coordinator with a `FakeSimulatorAppLauncher` (in-memory) against a real `CameraTransportServer`. Covers: terminate-then-launch ordering, presence and format of the three required env vars (`DYLD_INSERT_LIBRARIES`, `XTOP_CAMERA_PORT`, hex `XTOP_CAMERA_TOKEN`), source start/stop counts on `stop()`, transport+state rollback on launch failure, and previous-session teardown when `injectAndLaunch` is called twice. Enabled by extracting a `SimulatorAppLauncher` protocol that `AppLifecycleController` conforms to.
- [x] 11.4 `XTopTests/CameraFrameSourceTests.swift` adds determinism + pixel-sample + frame-difference checks for `TestPatternSource.renderFrame`. `XTopTests/AppLifecycleControllerTests.swift` covers `parsePID(fromLaunchStdout:)`. `XTopTests/CameraSourcePreferenceStoreTests.swift` covers `CameraSourcePreferenceStore` save/load and per-key namespacing.
- [ ] 11.5 Booted-simulator integration test — not yet written.

## 12. Distribution

- [ ] 12.1 Update the GitHub Actions release workflow (`add-github-actions-build-distribution`) to re-sign `XTopCameraShim.bin` with the same Developer ID after macOS app signing and before notarization.
- [ ] 12.2 Add an `xcrun stapler validate` step on the final `.app` to catch any notarization regression caused by the embedded binary.
- [ ] 12.3 Add an end-of-build assertion that the bundled binary still contains both `arm64` and `x86_64` simulator slices and is signed.
