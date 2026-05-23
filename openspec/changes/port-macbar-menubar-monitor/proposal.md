## Why

`XTop` currently has a placeholder SwiftUI menu bar shell while the older `macbar` project already proves the menu bar interaction model and dashboard logic needed for a useful developer monitor. Porting the reliable pieces into `XTop` now establishes a working macOS menu bar foundation without carrying forward unfinished sensor setup and destructive maintenance workflows.

## What Changes

- Replace the placeholder menu bar panel path with a status item and popover dashboard behavior derived from the working `macbar` app.
- Show live baseline system telemetry for CPU, per-core CPU, memory, storage, disk cache, and relevant developer-process usage with unavailable states where a metric cannot be collected.
- Surface read-only Xcode developer context such as DerivedData usage, open Xcode projects, provisioning profile summaries, code-signing certificate summaries, and focused-project Git/worktree context.
- Keep sampling and developer-context refresh work behind view-model and service boundaries so the menu bar UI stays responsive.
- Trim the imported `macbar` surface to exclude advanced GPU, temperature, and fan helper setup plus cache cleanup, SwiftPM mutation, CocoaPods mutation, and other destructive maintenance actions from this change.

## Capabilities

### New Capabilities
- `menubar-monitor-surface`: Provide the XTop menu bar status item, status summary, and popover lifecycle for the dashboard.
- `system-telemetry-dashboard`: Provide baseline live system telemetry and developer-process visibility in the menu bar dashboard.
- `xcode-developer-context`: Provide read-only Xcode environment and focused-project Git/worktree context in the dashboard.

### Modified Capabilities
- None.

## Impact

- Affects `XTop` app entrypoint, menu bar hosting behavior, dashboard views, settings surface, and view-model ownership.
- Reuses and trims code copied from `/Users/harsh/Projects/macbar`, including telemetry and Xcode/Git service logic already staged in `XTop`.
- Introduces domain models and sampling state needed by the imported dashboard while removing dependencies on out-of-scope maintenance and advanced sensor settings.
- Uses local macOS system and developer-tool integrations such as Mach telemetry, filesystem scans, Xcode document discovery, `git`, and code-signing metadata queries with fallback messaging when data is unavailable.
