## Context

XTop currently derives Git information from a single focused Xcode project path and displays read-only repository context in the dashboard. This does not satisfy a dedicated monitor workflow where users manage multiple repositories and credentials across different hosts and organizations.

The redesign introduces a Git monitor subsystem that is independent from focused-project detection and centered around a repository registry with per-repository account binding. The monitor must support both HTTPS token and SSH identity authentication, periodic sync across all active repositories, deep recursive repository discovery, and an explicit inactive lifecycle for missing paths.

## Goals / Non-Goals

**Goals:**
- Provide a multi-repository monitoring model with explicit repository registry ownership.
- Support per-repository account binding for both HTTPS and SSH authentication profiles.
- Support secure login/logout flows and credential lifecycle management.
- Perform periodic sync for all active repositories, including local status and remote tracking state.
- Support deep recursive repository discovery from configured base folders and manual repository add.
- Mark missing repositories inactive instead of deleting metadata.
- Present one primary repository in the main menu with the remaining repositories in nested submenu sections.

**Non-Goals:**
- Implement mutation-heavy Git workflows such as merge, rebase, cherry-pick, and conflict resolution.
- Replace terminal-first Git workflows for advanced operations.
- Introduce cloud account synchronization for credentials or monitor settings in this change.

## Decisions

1. Introduce a dedicated Git monitor domain model and service boundary.
- Decision: Add registry/account/snapshot domain models and a `GitMonitorService` actor rather than extending `GitContextSnapshot`.
- Rationale: The existing focused-project model is structurally single-context and cannot safely express per-repo binding plus all-repo sync behavior.
- Alternative considered: Extend the existing Git context service with array-based snapshots. Rejected because it keeps an implicit dependency on focused-project resolution and mixes concerns.

2. Implement per-repository account binding as first-class persisted metadata.
- Decision: Every monitored repository stores a bound account profile ID and auth mode.
- Rationale: This ensures deterministic remote operations when repositories target different hosts or identities.
- Alternative considered: One globally active account. Rejected because it breaks multi-host and mixed-organization workflows.

3. Support HTTPS and SSH profile types in v1.
- Decision: Account profiles support `https-token` and `ssh-key` modes from day one.
- Rationale: SSH identity switching is a hard user requirement and common in multi-repository environments.
- Alternative considered: HTTPS-only v1. Rejected because it would force partial functionality and immediate follow-up redesign.

4. Use per-command SSH identity override for repository-bound operations.
- Decision: Execute SSH remote operations with a repository-selected identity via command-scoped SSH options.
- Rationale: This avoids mutating global SSH configuration and keeps identity selection local to each repository operation.
- Alternative considered: Writing global `~/.ssh/config` host aliases. Rejected due to user-environment side effects and higher rollback complexity.

5. Run sync for all active repositories with bounded concurrency.
- Decision: Periodic sync includes all active repositories, with separate local and remote refresh lanes and capped parallelism.
- Rationale: Satisfies the all-repos requirement while controlling CPU/network pressure.
- Alternative considered: Sync only primary or recently changed repositories. Rejected because it conflicts with explicit user direction.

6. Deep recursive scan with exclusion rules and canonical deduplication.
- Decision: Base-folder discovery recursively scans nested paths, skipping known high-cost folders and deduplicating canonical repository roots.
- Rationale: Preserves deep discovery behavior without pathological scans.
- Alternative considered: depth-limited scan. Rejected due to requirement for deep recursive behavior.

7. Missing repositories transition to inactive state.
- Decision: Discovery/sync never hard-deletes missing repositories; entries are marked inactive and can auto-reactivate when found again.
- Rationale: Preserves user intent, bindings, and history while preventing data loss.
- Alternative considered: Automatic deletion after repeated failures. Rejected because path volatility is common and deletion is surprising.

8. Menu layout prioritizes a single primary repository.
- Decision: Main menu section displays the primary repository snapshot; all other active repositories appear under nested submenu sections with inactive repositories grouped separately.
- Rationale: Keeps top-level menu concise while maintaining full monitor visibility.
- Alternative considered: flat list of all repositories in main panel. Rejected for menu noise and reduced scanability.

## Risks / Trade-offs

- [Large repository counts can increase sync latency and system load] -> Mitigation: enforce concurrency caps, lane-specific intervals, and timeout/backoff per repository.
- [SSH key passphrase or agent availability can fail headless operations] -> Mitigation: classify auth errors explicitly, expose actionable UI states, and provide profile validation checks.
- [Deep recursive scans may traverse very large directory trees] -> Mitigation: apply exclusion patterns, canonical path dedupe, and scan cadence controls.
- [Per-repo credential storage introduces security sensitivity] -> Mitigation: store secrets only in Keychain, never in plain preferences, and scrub command/log output.
- [Migration from focused-project Git card may break existing user expectations] -> Mitigation: introduce compatibility fallback messaging and preserve read-only status semantics in UI.

## Migration Plan

1. Add new monitor domain models, stores, and service protocol without removing existing focused-project Git context.
2. Introduce account profile management and secure credential storage with login/logout flows.
3. Introduce repository registry persistence, deep scan discovery, and inactive-state lifecycle.
4. Add sync scheduler for all active repositories and publish unified monitor snapshots.
5. Switch dashboard/menu rendering to monitor snapshots with primary-repository and submenu grouping.
6. Keep old focused-project Git context behind fallback messaging during transition, then trim unused paths after verification.

## Open Questions

- Should repository creation without an account binding be allowed as a pending state, or should account selection be mandatory at add time?
- What default local and remote sync intervals best balance freshness and resource usage for macOS menu bar workloads?
- Should inactive repositories be hidden by default or always shown in a dedicated collapsed section?
