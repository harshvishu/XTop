## 1. Establish Root Ownership

- [x] 1.1 Audit current singleton/default dependency usage for `MacbarPreferences`, `SensorSettingsModel`, `DeveloperDiagnosticsStore`, and `MacbarViewModel`.
- [x] 1.2 Add root-owned `@State` instances in `XTopApp` for preferences, sensor settings, diagnostics, services, and the root `MacbarViewModel`.
- [x] 1.3 Wire production service dependencies once at the app root and pass explicit dependencies into `MacbarViewModel`.
- [x] 1.4 Remove `static let shared` from `MacbarPreferences`, `SensorSettingsModel`, and `DeveloperDiagnosticsStore`.

## 2. Inject State Through SwiftUI Environment

- [x] 2.1 Inject the root-owned observable instances into both the menu bar scene and settings scene with SwiftUI environment.
- [x] 2.2 Update `MenuBarPanelView` and any dashboard views that need shared state to read models from `@Environment`.
- [x] 2.3 Replace `SettingsView` placeholder wiring with `SettingsRootView` or an equivalent environment-backed settings root.
- [x] 2.4 Update settings child views to read environment models directly or use local `@Bindable` projections for controls that mutate preferences.
- [x] 2.5 Update previews and tests to provide explicit environment values instead of relying on singletons.

## 3. Fix MacbarViewModel Concurrency Boundaries

- [x] 3.1 Change `MacbarViewModel` initializer parameters so preferences, sensor settings, and diagnostics are required explicit dependencies.
- [x] 3.2 Remove default `.shared` arguments and any call sites that rely on implicit shared observable state.
- [x] 3.3 Resolve `MainActor.run` capture warnings by keeping view-model state mutation in main-actor-isolated code with explicit `self` usage where needed.
- [x] 3.4 Audit the developer-context collection path and move slow work behind actor-safe async service boundaries without marking observable state or domain model properties `nonisolated`.
- [x] 3.5 Remove any existing `nonisolated` property workaround added only to silence Swift 6 warnings.

## 4. Keep SwiftUI Code Organized

- [x] 4.1 Move shared observable model types out of `MacbarViewModel.swift` into dedicated files if implementation work touches those types.
- [x] 4.2 Keep `@Observable` app state types main-actor isolated and avoid `ObservableObject`, `@Published`, `@StateObject`, and `@EnvironmentObject` unless a legacy integration requires them.
- [x] 4.3 Keep view bodies focused on rendering and move dependency construction or service wiring out of SwiftUI view bodies.

## 5. Verify

- [x] 5.1 Build `XTop` and confirm no `MacbarViewModel` main-actor-isolation warnings remain.
- [x] 5.2 Run focused unit tests with `xcodebuild -project XTop.xcodeproj -scheme XTop -destination platform=macOS -derivedDataPath .build/xcode-derived-data CODE_SIGNING_ALLOWED=NO -only-testing:XTopTests test`.
- [x] 5.3 Run the app verification path and confirm the menu bar panel and settings scene use the same preference, sensor, diagnostics, and monitor instances.
- [x] 5.4 Review the final diff to confirm singleton instances were removed and no observable/domain properties were marked `nonisolated`.
