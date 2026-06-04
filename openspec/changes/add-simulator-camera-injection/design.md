## Context

XTop's Simulator Inspector already enumerates booted simulators, lists installed apps via `simctl listapps`, resolves app data containers, and drives terminate/launch via `simctl`. The Camera feature extends that infrastructure with one new dimension: pushing media into the target app process at runtime, without the developer modifying their app's source.

The two prominent OSS references (iCimulator, dautovri/SimulatorCamera) both require the developer to add a Swift Package to their iOS app and rewrite capture call sites — that approach is incompatible with the Simulator Inspector's "debug without going into the code" mission. The commercial RocketSim "Simulator Camera" claims "use the same AVCapture APIs as normal," which is only possible via in-process runtime interception. The only public mechanism that achieves this is `xcrun simctl launch`'s `SIMCTL_CHILD_*` env-var passthrough combined with `DYLD_INSERT_LIBRARIES` and Objective-C method swizzling inside the loaded dylib.

A Phase 0 spike on 2026-06-04 with Xcode 26.1.1 / iOS 26.1 simruntime confirmed that an ad-hoc-signed `arm64-apple-ios-simulator` dylib loads into a `simctl launch`-ed app process before app code runs, including in a `SystemApp`-classified target. This validates the architecture before any production work begins.

## Goals / Non-Goals

**Goals:**
- A developer can pick a booted simulator and an installed app, choose a frame source, click "Inject & Launch," and have their unmodified app receive `CMSampleBuffer`s through its existing `AVCaptureVideoDataOutput` / `AVCaptureMetadataOutput` / `AVCapturePhotoOutput` paths.
- Coverage of the four highest-frequency real-world use cases: QR/barcode scanning, document/photo capture, ML/Vision pipelines, and visual demos.
- Four built-in frame sources: test pattern, Mac webcam, local video file, screen region.
- Zero changes required to the target app's source code or build settings.
- Optional "paste into Xcode scheme" snippet for developers who launch via Xcode rather than via XTop.
- All transport is localhost-only and per-launch token-authenticated.

**Non-Goals:**
- Post-attach injection into already-running apps.
- Real-device camera injection.
- Audio, depth, multi-cam, ProRes/HEVC, `AVCaptureMovieFileOutput` to disk, or `DataScannerViewController`.
- Custom user-supplied frame sources or a plugin SDK.
- Recording the outgoing feed to disk.

## Decisions

1. **Inject via `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES` on `simctl launch`, not via a host-side virtual camera.**
- Decision: Bundle an iOS-simulator dynamic library inside XTop and inject it per-launch by passing `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=<path>` to `xcrun simctl launch`.
- Rationale: It is the only public mechanism that lets unmodified apps receive frames in the simulator. Phase 0 confirmed it works on current Xcode. It also keeps the feature scoped to one app at a time, which matches the Simulator Inspector's per-app mental model.
- Alternative considered: A macOS CoreMediaIO Camera Extension (system extension) that exposes a virtual camera. Rejected because (a) the iOS Simulator's AVFoundation does not consistently expose host virtual cameras to guest iOS, (b) shipping a system extension requires Developer ID + provisioning + user approval in System Settings — far heavier than the existing distribution story, and (c) it would camera-bridge for the entire host, not per-app.
- Alternative considered: Asking the user to add a Swift Package (iCimulator / SimulatorCamera model). Rejected: contradicts the Simulator Inspector's "no app source changes" mission.

2. **Swizzle only the public AVFoundation surface from inside the injected dylib.**
- Decision: The shim swizzles a small, public surface: `AVCaptureSession.startRunning/stopRunning/addInput/addOutput`, `AVCaptureDevice.default(for:)` / `devices(for:)` / `authorizationStatus(for:)` / `requestAccess(for:completionHandler:)`, `AVCaptureVideoDataOutput.setSampleBufferDelegate(_:queue:)` delivery path, `AVCaptureMetadataOutput`'s `metadataObjectTypes` and delegate delivery, `AVCapturePhotoOutput.capturePhoto(with:delegate:)`, and `UIImagePickerController(sourceType: .camera)`'s present/dismiss + delegate callback.
- Rationale: This is the surface ~95% of real iOS camera-using apps actually call. Pure public API. No private symbols, no entitlements beyond what a normal iOS app uses, and easy to audit.
- Alternative considered: A wholesale `AVCaptureSession` replacement subclass exposed to the app. Rejected because the app's existing code already references `AVCaptureSession` directly; we cannot rewrite their types from outside.

3. **Authorization always returns `.authorized`; `requestAccess` invokes the completion with `true` synchronously on a background queue.**
- Decision: The shim swizzles `AVCaptureDevice.authorizationStatus(for: .video)` to return `.authorized` and `requestAccess` to deliver `true` without prompting. No iOS-level camera permission prompt is involved (the simulator has no camera; the prompt would be meaningless).
- Rationale: Apps gate their capture path on this — if we leave it untouched, swizzled outputs never receive frames because the app never starts the session.
- Alternative considered: Honor the iOS-level setting in Settings.app. Rejected; meaningless without a real camera, and would make the feature silently fail.

4. **Frame transport is localhost TCP with a per-launch random token, frames as JPEG over a framed binary protocol.**
- Decision: A fresh listener binds to `127.0.0.1` on an ephemeral high port at "Inject & Launch" time. XTop passes the chosen port and a 256-bit random token via `SIMCTL_CHILD_XTOP_CAMERA_PORT` and `SIMCTL_CHILD_XTOP_CAMERA_TOKEN`. The shim opens one TCP connection, sends the token, then receives JPEG-encoded frames in length-prefixed records.
- Rationale: Localhost-only by construction. Per-launch token prevents any other process on the host from connecting. JPEG keeps frame size manageable (~30 fps × 1280×720 stays well inside loopback throughput) and decodes cheaply via `ImageIO` into `CVPixelBuffer`. Mirrors the proven SimulatorCamera SCMF protocol shape but adds the auth token.
- Alternative considered: XPC. Rejected because simulator processes do not share an XPC namespace with the host. Alternative: `IOSurface` shared memory. Rejected for v1 because the simulator process is in a separate kernel context from the host on Apple Silicon and `IOSurface` sharing across that boundary is not a public API.
- Alternative considered: Raw `CVPixelBuffer` over the wire. Rejected: bandwidth-heavy and adds pixel-format negotiation complexity for no v1 benefit.

5. **The frame producer lives in the XTop process, off the main actor, with `ScreenCaptureKit` for screen sources and `AVCaptureSession` for webcam.**
- Decision: One actor-isolated `CameraPipeline` owns the active source, runs at ~30 fps, encodes frames to JPEG (configurable quality, default 0.7), and pushes them to any connected shim client. Sources are `TestPatternSource`, `WebcamSource` (host `AVCaptureSession` with `AVCaptureVideoDataOutput`), `VideoFileSource` (`AVAssetReader` looping a `.mp4`/`.mov`), and `ScreenRegionSource` (`SCStream` with a user-picked window or display region).
- Rationale: Matches XTop's existing actor-based service patterns. Encoding off the main actor keeps the UI smooth.
- Alternative considered: Encoding on the simulator side from a raw stream. Rejected: more work to ship, less benefit for v1.

6. **The dylib is built as part of XTop's main build, dual-arch, ad-hoc signed.**
- Decision: Add a separate SwiftPM target (or an Xcode aggregate target) that builds `XTopCameraShim.dylib` for `arm64-apple-ios-simulator` and `x86_64-apple-ios-simulator`, lipos them into a single fat binary, ad-hoc signs it, and copies it into the macOS app bundle's `Contents/Resources/XTopCameraShim.dylib`. The macOS app resolves this path at runtime via `Bundle.main.url(forResource:withExtension:)`.
- Rationale: Phase 0 confirmed ad-hoc signing is sufficient for injection. Bundling inside Resources keeps it user-readable from the simulator process (which runs as the user, outside XTop's sandbox).
- Alternative considered: Downloading the dylib on first launch. Rejected: adds network dependency, code-signing-validation complexity, and an offline-broken experience.

7. **Launch flow is "always terminate, then launch with env"; no in-place injection.**
- Decision: "Inject & Launch" always runs `simctl terminate <UDID> <bundleID>` (ignoring "not running" errors), then `simctl launch <UDID> <bundleID>` with the `SIMCTL_CHILD_*` env vars. Reuses existing `AppLifecycleController` with an env-aware variant.
- Rationale: `DYLD_INSERT_LIBRARIES` only applies at process start. Trying to inject into an already-running process is not supported by `simctl`.

8. **One injected app at a time; clear status of which app is "live."**
- Decision: The pipeline tracks at most one connected shim client. Switching the selected app, switching sources, or closing the Camera tab terminates the connection and offers to terminate the inspected app process. The Camera tab status row always names the injected bundle ID and PID (when known).
- Rationale: A single, clearly-attributed feed is dramatically easier to reason about than multi-target injection. Multi-app injection is an unrequested generalization.

9. **Xcode-scheme escape hatch is offered, not enforced.**
- Decision: A "Copy Xcode scheme env vars" action emits a snippet (`DYLD_INSERT_LIBRARIES=<absolute-path>`, `XTOP_CAMERA_PORT=…`, `XTOP_CAMERA_TOKEN=…`) the developer can paste into their scheme's Run → Arguments → Environment Variables. When Xcode launches the app, the same shim activates. The port/token must remain stable across runs in this mode; XTop offers a "pin port" toggle for that purpose.
- Rationale: Many developers Cmd-R from Xcode rather than via XTop. Without this, the feature only works for `simctl launch`-driven runs.

10. **Phase 0 spike is the gate, not the implementation.**
- Decision: Phase 0 (proven 2026-06-04) is captured as task 1.1 and is marked complete. All subsequent tasks may assume DYLD injection into simctl-launched simulator app processes is a working public mechanism on Xcode 26.1+.
- Rationale: Documenting the spike in `tasks.md` makes the "why we believe this is feasible" auditable in the change record.

## Risks / Trade-offs

- **AVFoundation surface drift across iOS releases.** Apple can change AVFoundation internals between iOS major versions. The shim must be smoke-tested on each new simruntime; the swizzled symbols are public but call ordering can shift. Mitigation: explicit per-iOS-version smoke checklist in `tasks.md`, and a feature-flag killswitch so the Camera tab can be disabled if a future runtime breaks it.
- **Preview layer fidelity.** `AVCaptureVideoPreviewLayer` has a private connection to the capture pipeline. v1 mitigates by swizzling its `session` setter and rendering injected frames into the layer via a `CAMetalLayer` or `AVSampleBufferDisplayLayer` shim. If the swizzle proves brittle, v1 documents "preview may not render in some apps; the data output still works" and ships.
- **App expects `AVCaptureDevice.requestAccess` to be asynchronous.** We deliver `true` synchronously from a background queue; some apps assume a UI roundtrip. Mitigation: post the completion on `DispatchQueue.global().asyncAfter(deadline: .now() + 0.05)` to better resemble the real OS behavior.
- **Localhost token leak.** A buggy app that logs all env vars would expose the per-launch token. Mitigation: token is single-use and per-launch; even if leaked, the listener only lives for the duration of that launch and only accepts one connection.
- **Frame backpressure.** A slow app could fall behind 30 fps. Mitigation: the producer drops frames rather than queuing; the shim never blocks the app's capture queue.
- **Cross-arch (Intel Mac) builds.** XTop targets macOS broadly; the simulator dylib must include `x86_64-apple-ios-simulator` too. Mitigation: the build script always lipos both slices; CI must keep this honest.
- **Sandbox + bundled dylib.** Phase 0 confirmed injection works from `/tmp`. The bundled-Resources path inside the `.app` is user-readable; the simulator process runs as the user, so reading the dylib from inside the sandboxed app's `Contents/Resources/` should work. Verified during task 1.2.
- **Camera entitlement on the host.** Requesting `com.apple.security.device.camera` lazily on first webcam-source selection requires a hardened-runtime entitlement and a clear `NSCameraUsageDescription`. Screen recording permission is requested via TCC on first screen-region selection. Both are scoped narrowly per source.

## Migration Plan

- Net-new feature; no migration of existing user data.
- The new tab is hidden by default behind a feature flag (`SimulatorInspectorFeatureFlags.cameraInjectionEnabled`, default `false`) until task 11.x flips it on after end-to-end QA on at least three real third-party apps (a barcode scanner, a Vision-based app, and a `UIImagePickerController`-based app).
- The GitHub Actions distribution change (`add-github-actions-build-distribution`) needs one addition: re-sign the bundled `XTopCameraShim.dylib` with the same Developer ID after macOS app signing, before notarization. Captured as task 12.x.

## Open Questions

- Should the v1 webcam source list include Continuity Camera (iPhone-as-webcam)? Free if we use the host `AVCaptureSession`, but worth confirming it shows up as a normal device.
- For the screen-region source, should we expose window-pick (à la `SCContentSharingPicker`) or rectangle-pick first? Picker is less code and matches macOS Sequoia/15+ norms; rectangle is more flexible but heavier UI.
- Should the Camera tab be hidden until an iOS-simulator runtime is detected on the host, or always visible with an instructive empty state? Lean: always visible, empty state explains.
