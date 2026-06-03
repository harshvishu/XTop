## ADDED Requirements

### Requirement: Periodic sync covers all active repositories
The system SHALL periodically refresh monitoring data for all active repositories.

#### Scenario: Periodic cycle starts
- **WHEN** a sync interval elapses
- **THEN** the system schedules refresh operations for every active repository in the registry

### Requirement: Sync reports both local and remote monitor state
The system SHALL collect local repository status and remote tracking status for each active repository.

#### Scenario: Local status refresh
- **WHEN** a repository refresh runs
- **THEN** the system reports branch, staged/unstaged/untracked changes, and last commit metadata

#### Scenario: Remote tracking refresh
- **WHEN** remote synchronization runs for a repository with valid credentials
- **THEN** the system reports ahead/behind state relative to tracking branch and updates sync timestamps

### Requirement: Sync engine remains resilient under failures
The system SHALL isolate per-repository failures and keep monitoring other repositories.

#### Scenario: One repository fails auth
- **WHEN** a repository remote sync fails with an authentication error
- **THEN** the system records an auth-specific error for that repository and continues syncing other repositories

#### Scenario: Repository exceeds operation timeout
- **WHEN** a repository operation exceeds configured timeout
- **THEN** the system records timeout state for that repository and continues the remaining sync cycle

### Requirement: Sync execution is bounded
The system SHALL use bounded parallel execution for repository sync operations.

#### Scenario: Many repositories are active
- **WHEN** the number of active repositories exceeds available worker slots
- **THEN** the system queues work and runs operations within configured concurrency limits
