## Context

`XTop` is an Xcode-native macOS menu bar app using SwiftUI and `@Observable` models under project-wide `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` with approachable concurrency enabled. The current shared-state path keeps `MacbarPreferences`, `SensorSettingsModel`, and `DeveloperDiagnosticsStore` as `@MainActor @Observable` singletons and references them from `MacbarViewModel` default parameters. That creates Swift 6 warnings because default argument evaluation is nonisolated while the `.shared` static properties are main-actor isolated.

SwiftUI Pro guidance for modern data flow is to keep shared UI state in `@Observable` classes, have one owner create the instances with `@State`, and pass them through `@Environment` / `@Bindable`. This change applies that model to `XTop` instead of weakening actor isolation with broad `nonisolated` annotations.

## Goals / Non-Goals

**Goals:**
- Make `XTopApp` the single owner of app-wide observable state and the root `MacbarViewModel`.
- Inject `MacbarPreferences`, `SensorSettingsModel`, `DeveloperDiagnosticsStore`, and `MacbarViewModel` through SwiftUI environment.
- Remove `.shared` singleton storage and default `.shared` parameters from the observable models.
- Keep UI-facing observable models main-actor isolated.
- Resolve `MacbarViewModel` actor-isolation warnings without marking observable state properties or domain model properties `nonisolated`.
- Keep service and command execution dependencies explicit and testable.

**Non-Goals:**
- Reworking the menu bar UI beyond the injection and wiring needed for this fix.
- Introducing third-party dependency injection frameworks.
- Converting the whole codebase to Swift 6 language mode in this change.
- Adding destructive maintenance behavior or changing existing telemetry semantics.

## Decisions

1. Own shared app state at the SwiftUI root.
   - `XTopApp` will create one `MacbarPreferences`, one `SensorSettingsModel`, one `DeveloperDiagnosticsStore`, and one `MacbarViewModel`.
   - These instances will be stored with `@State` so SwiftUI preserves identity across scene updates.
   - Alternative considered: keep `static let shared` and use `@MainActor` access wrappers. That hides ownership and leaves tests tied to process-global state.

2. Inject observable instances with SwiftUI environment.
   - `MenuBarPanelView`, `SettingsRootView`, and child settings/dashboard views will read shared models with `@Environment(Type.self)`.
   - Views that mutate observable models will create local `@Bindable` projections from the environment model.
   - Alternative considered: continue passing every model through initializers. That can work, but the menu bar scene and settings scene both need the same instances, making environment injection simpler and closer to SwiftUI's shared-state model.

3. Make `MacbarViewModel` dependencies explicit.
   - The initializer will require `preferences`, `sensorSettings`, and `diagnostics`; it will not default them to `.shared`.
   - Service dependencies remain injectable so focused tests can provide fakes.
   - Alternative considered: construct preferences and diagnostics inside `MacbarViewModel`. That makes the view model own app state it should only coordinate.

4. Keep UI state on the main actor and move slow work behind proper async boundaries.
   - `MacbarViewModel` remains `@MainActor` because it owns observable UI state.
   - The developer context collection path should either use dedicated actor-backed services or narrowly isolated async service APIs for file/process work.
   - Implementation must not mark observable properties, snapshot properties, or app state properties `nonisolated` to silence warnings.
   - If a service API must run outside the main actor, isolate the service boundary itself with a clear concurrency contract rather than changing UI model isolation.

5. Remove unnecessary `MainActor.run` from main-actor tasks where possible.
   - Tasks launched from `MacbarViewModel` main-actor methods can update state directly after awaited background work resumes on the main actor.
   - If `MainActor.run` remains, mutations inside the closure must use explicit `self.` capture semantics.
   - Alternative considered: wrap more code in `MainActor.run`. That masks the source of the warning and can accidentally move expensive work onto the main actor.

## Risks / Trade-offs

- [Environment values missing in previews or tests] -> Provide explicit preview/test setup helpers or local `.environment(...)` injection for each root preview that needs shared state.
- [Root initializer ordering becomes awkward because `MacbarViewModel` needs the same model instances] -> Initialize local instances in `XTopApp.init`, then assign each `@State` with `State(initialValue:)`.
- [Background service warnings remain after singleton removal] -> Convert service collection APIs to async actor-backed services or narrowly isolated service methods, but do not mark observable state properties `nonisolated`.
- [Settings and menu bar scenes accidentally get different instances] -> Inject the same root-owned instances into both scenes from `XTopApp`.
- [Existing tests depend on singleton access] -> Update tests to construct explicit model instances and pass them into `MacbarViewModel`.

## Migration Plan

1. Add app-level state ownership in `XTopApp` for preferences, sensors, diagnostics, services, and `MacbarViewModel`.
2. Remove `.shared` static properties from `MacbarPreferences`, `SensorSettingsModel`, and `DeveloperDiagnosticsStore`.
3. Change `MacbarViewModel` initializer to require explicit observable dependencies and update call sites.
4. Inject root-owned instances into `MenuBarPanelView` and `SettingsRootView` via `.environment(...)`.
5. Update menu bar and settings views to read shared state from `@Environment` instead of initializer parameters.
6. Fix remaining `MacbarViewModel` warnings by keeping UI mutations on the main actor and moving slow service work behind actor-safe async service boundaries.
7. Build and run focused tests. If the change regresses app launch, rollback by restoring the previous initializer wiring while keeping source changes separated from unrelated UI work.

## Open Questions

- Should the implementation keep the current `SettingsView` as a small wrapper around `SettingsRootView`, or remove the placeholder settings view entirely once environment injection is wired?
- Should the service layer be converted fully to actor-backed async services in this change, or limited to the minimum async boundary required to remove the current `MacbarViewModel` warnings?
