## ADDED Requirements

### Requirement: Repository registry supports deep discovery and manual add
The system SHALL maintain a persistent registry of monitored Git repositories and support both deep recursive discovery from configured base folders and manual repository addition.

#### Scenario: Deep recursive discovery finds nested repositories
- **WHEN** a base folder scan runs
- **THEN** the system recursively discovers nested Git repositories and records canonical repository roots without duplicates

#### Scenario: Manual repository add succeeds
- **WHEN** a user selects a valid Git repository path manually
- **THEN** the system stores the repository in the registry with monitoring enabled

### Requirement: Missing repositories are marked inactive
The system SHALL mark repositories as inactive when their paths are missing or unreachable and SHALL preserve repository metadata and bindings.

#### Scenario: Repository path is no longer reachable
- **WHEN** scan or sync cannot resolve a previously registered repository path
- **THEN** the system marks the repository inactive instead of deleting it

#### Scenario: Inactive repository becomes reachable again
- **WHEN** a future scan resolves a canonical path that matches an inactive repository
- **THEN** the system reactivates that repository and resumes monitoring

### Requirement: Repository has explicit primary designation
The system SHALL support a single primary repository designation for menu prioritization.

#### Scenario: User sets primary repository
- **WHEN** a user marks a repository as primary
- **THEN** the system stores that designation and clears primary designation from any previously primary repository
