## ADDED Requirements

### Requirement: Account profiles support HTTPS token and SSH key modes
The system SHALL provide account profiles for both HTTPS token authentication and SSH key identity authentication.

#### Scenario: User creates HTTPS profile
- **WHEN** a user saves a profile with host, username, and token credentials
- **THEN** the system stores non-secret profile metadata and stores the token in secure credential storage

#### Scenario: User creates SSH profile
- **WHEN** a user saves a profile with host, username, and SSH key identity details
- **THEN** the system stores profile metadata and references the selected SSH identity for repository-bound operations

### Requirement: Per-repository account binding is required for remote operations
The system SHALL bind each monitored repository to a specific account profile for remote synchronization.

#### Scenario: Repository is bound to account profile
- **WHEN** a user selects an account profile for a repository
- **THEN** remote sync commands for that repository execute using only that bound profile

### Requirement: Login and logout flows manage credential lifecycle
The system SHALL provide login and logout flows for account profiles and SHALL remove secrets on logout.

#### Scenario: Login via credential popup
- **WHEN** a user submits credentials in the login popup
- **THEN** the system validates and stores credentials, then makes the profile available for repository binding

#### Scenario: Logout removes secrets
- **WHEN** a user logs out from an account profile
- **THEN** the system removes secure secrets for that profile and marks bound repositories with a recoverable auth-required state

### Requirement: SSH identity switching is repository-scoped
The system SHALL apply SSH identity selection at command execution time using the repository's bound profile.

#### Scenario: Remote command uses bound SSH identity
- **WHEN** a repository bound to an SSH profile performs a remote sync command
- **THEN** the command executes with that repository's selected SSH identity and does not require global SSH config mutation
