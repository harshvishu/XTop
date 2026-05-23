## Context

`MenuBarPanelView` now embeds the imported `DashboardRootView`, which reads the root-injected `MacbarViewModel` from SwiftUI environment. The imported view still came from an older synchronous maintenance-action API, while the current XTop view model exposes `performMaintenanceAction(_:)` as async after the Swift 6 concurrency migration.

## Goals / Non-Goals

**Goals:**
- Make `DashboardRootView` compile against the current async `MacbarViewModel`.
- Keep dashboard state read through `@Environment(MacbarViewModel.self)`.
- Preserve the dashboard-first menu bar panel UI requested by the user.
- Verify the menu bar app builds, focused unit tests pass, and the app launch smoke path succeeds.

**Non-Goals:**
- Redesign the imported dashboard UI beyond what is needed for compile correctness.
- Replace the root environment-injection architecture.
- Add new services, dependencies, or AppKit host architecture.
- Remove the old `StatusSummaryView` type unless it is proven unused and safe to delete.

## Decisions

- Wrap async maintenance calls in view-local `Task` helpers rather than making the view model API synchronous again.
  - Rationale: maintenance work already crosses actor-backed services and shell commands, so async is the correct model.
  - Alternative considered: reintroduce synchronous view-model wrappers. Rejected because it would hide actor hops and re-create Swift 6 isolation warnings.

- Keep `DashboardRootView` as the menu bar content under the existing root-injected `MacbarViewModel`.
  - Rationale: this preserves the single-instance environment architecture and avoids reintroducing singleton state.
  - Alternative considered: initialize a local dashboard view model in the view. Rejected because the menu bar and settings scenes must share the root-owned app state.

- Limit UI cleanup to compile-critical and Swift concurrency issues.
  - Rationale: the user explicitly wants the imported UI, so this change should not broadly restyle or decompose the file.
  - Alternative considered: full SwiftUI style refactor. Deferred because it is larger than the error-fix scope.

## Risks / Trade-offs

- Async `Task` calls launched from button actions can outlive the immediate button tap -> keep state mutation in `MacbarViewModel`, which is main-actor isolated, and await the async API inside the task.
- `DashboardRootView` remains a large imported file -> defer broad decomposition until after the UI compiles and the requested replacement is verified.
- The old `StatusSummaryView` may remain in the target unused -> acceptable for this change unless the final grep proves no references and the user wants cleanup.
