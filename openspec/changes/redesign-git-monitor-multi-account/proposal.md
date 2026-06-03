## Why

The current Git surface in XTop is tied to one focused project context and cannot reliably support a repo-monitor workflow. We need a dedicated Git monitor that supports per-repository credential binding, multi-account switching, and periodic monitoring across many repositories.

## What Changes

- Introduce a dedicated Git monitor domain that manages a registry of repositories independently from focused Xcode project detection.
- Add account management for both HTTPS token profiles and SSH key identity profiles.
- Bind each monitored repository to a specific account profile (per-repo account binding).
- Support login/logout flows for account profiles, including popup credential entry and secure secret storage.
- Add deep recursive scanning from user-defined base folders to discover repositories automatically.
- Support manual repository addition alongside auto-discovery.
- Run periodic sync for all active repositories, combining local status refresh and remote tracking checks.
- Persist repositories that are no longer reachable on disk as inactive entries instead of deleting them.
- Add one primary repository shown in the main menu section and show remaining repositories in nested submenu sections.
- Keep operations read-only and monitoring-focused (status, branch, change counts, ahead/behind, sync/error state), excluding merge/rebase/cherry-pick style mutation operations.

## Capabilities

### New Capabilities
- `git-monitor-repository-registry`: Manage monitored repositories via deep folder scan and manual add, with active/inactive lifecycle.
- `git-monitor-account-profiles`: Manage HTTPS and SSH credential profiles, login/logout, and secure credential storage.
- `git-monitor-sync-engine`: Periodically sync all active repositories and publish local/remote monitoring snapshots.
- `git-monitor-menu-surface`: Present primary repository in the main menu and other repositories in nested submenu sections.

### Modified Capabilities
- None.

## Impact

- Affects app state composition, service protocols, git models, and menu/dashboard views that currently consume focused-project Git snapshot data.
- Introduces new persistence and keychain access paths for repository/account profiles.
- Adds recurring background sync scheduling and bounded concurrent git command execution across all active repositories.
- Requires migration from current single-context Git card behavior to repository-registry-driven rendering.
