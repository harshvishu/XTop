## ADDED Requirements

### Requirement: Primary repository is shown in main menu section
The system SHALL display exactly one primary repository summary in the main menu monitor section.

#### Scenario: Primary repository is configured
- **WHEN** menu content is rendered
- **THEN** the main section displays the primary repository snapshot with branch, change status, and sync health

### Requirement: Non-primary repositories are shown in nested submenu sections
The system SHALL render non-primary repositories in nested submenu sections separate from the main primary summary.

#### Scenario: Additional active repositories exist
- **WHEN** menu content is rendered with more than one active repository
- **THEN** non-primary repositories are listed in a nested submenu section

### Requirement: Inactive repositories are visibly separated
The system SHALL show inactive repositories in a dedicated section distinct from active repositories.

#### Scenario: Inactive repositories are present
- **WHEN** one or more repositories are marked inactive
- **THEN** the menu shows an inactive repository section that indicates those repositories are not currently monitored

### Requirement: Menu remains monitor-only for Git operations
The system SHALL expose read-only monitor actions and SHALL not expose merge/rebase/conflict workflows in the menu.

#### Scenario: User opens repository actions
- **WHEN** repository actions are presented in the menu
- **THEN** available actions are limited to monitor-oriented operations such as refresh, bind account, set primary, and open repository context
