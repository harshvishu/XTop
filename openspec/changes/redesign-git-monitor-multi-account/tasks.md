## 1. Domain Model and Storage Foundations

- [x] 1.1 Add Git monitor domain models for repository registry, account profiles, repository snapshots, sync state, and primary/inactive lifecycle.
- [x] 1.2 Add persistent repository registry storage that supports active/inactive state and canonical path deduplication.
- [x] 1.3 Add persistent account profile storage for HTTPS and SSH metadata while excluding secrets from plain preferences.
- [x] 1.4 Add secure secret storage integration for account credentials and validate create/read/delete lifecycle behavior.

## 2. Service and Protocol Refactor

- [x] 2.1 Introduce `GitMonitorService` protocol and actor-backed implementation separate from focused-project Git context.
- [x] 2.2 Add migration-friendly app service wiring so existing focused-project Git context can coexist during transition.
- [x] 2.3 Add repository binding APIs that enforce per-repository account profile selection for remote operations.
- [x] 2.4 Add command gateway behavior for repository-scoped SSH identity switching without mutating global SSH config.

## 3. Repository Discovery and Lifecycle

- [x] 3.1 Implement deep recursive base-folder scanning with exclusion rules and canonical repository root detection.
- [x] 3.2 Implement manual repository add/remove flows integrated with registry persistence.
- [x] 3.3 Implement inactive-state transitions for missing paths and auto-reactivation when paths reappear.
- [x] 3.4 Add primary repository assignment logic that guarantees exactly one primary repository at a time.

## 4. Sync Engine and Scheduling

- [x] 4.1 Implement periodic sync scheduler that runs refresh for all active repositories.
- [x] 4.2 Implement local status refresh collection (branch, staged/unstaged/untracked counts, commit metadata).
- [x] 4.3 Implement remote tracking refresh (ahead/behind, last sync timestamps) using bound repository credentials.
- [x] 4.4 Add bounded concurrency, timeout, and per-repository failure isolation for sync operations.
- [x] 4.5 Add auth/error classification so repository-level states distinguish auth-required, timeout, and generic failures.

## 5. Account UX and Credential Flows

- [x] 5.1 Add account management UI for listing, adding, editing, and removing HTTPS and SSH profiles.
- [x] 5.2 Add login popup flow for credential entry and validation before profile activation.
- [x] 5.3 Add logout flow that removes secure secrets and marks bound repositories as recoverable auth-required.
- [x] 5.4 Add repository-level account binding controls in monitor UI.

## 6. Menu and Dashboard Integration

- [x] 6.1 Replace single focused-project Git card rendering with registry-driven repository monitor rendering.
- [x] 6.2 Render primary repository snapshot in the main menu section.
- [x] 6.3 Render non-primary active repositories in nested submenu sections.
- [x] 6.4 Render inactive repositories in a dedicated section with clear inactive state labels.
- [x] 6.5 Keep Git action surface monitor-focused and exclude merge/rebase/conflict workflow actions.

## 7. Verification and Migration Cleanup

- [x] 7.1 Add focused unit tests for repository registry lifecycle, inactive transitions, and primary selection behavior.
- [x] 7.2 Add focused tests for per-repository account binding and SSH identity command-scoping behavior.
- [x] 7.3 Add sync engine tests for all-repo scheduling, bounded concurrency, and failure isolation.
- [x] 7.4 Build and run XTop to verify menu rendering, account flows, and periodic sync behavior end-to-end.
- [x] 7.5 Remove obsolete focused-project-only Git monitor paths once new monitor integration is verified.
