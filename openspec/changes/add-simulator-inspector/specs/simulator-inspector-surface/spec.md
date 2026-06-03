## ADDED Requirements

### Requirement: Inspector is a top-level dashboard destination
The system SHALL expose the Simulator Inspector as a top-level dashboard destination using a master-detail layout that lets the user select a simulator, then an installed app, then an inspector tab.

#### Scenario: User navigates to the inspector
- **WHEN** the user opens the Simulator Inspector destination
- **THEN** the system presents a sidebar of booted simulators, a list of installed apps for the selected simulator, and inspector tabs for the selected app

### Requirement: Destructive actions require confirmation
The system SHALL require explicit confirmation for destructive inspector actions, including deleting a `UserDefaults` entry and clearing the keychain.

#### Scenario: Destructive action shows confirmation
- **WHEN** the user invokes a destructive inspector action
- **THEN** the system shows a confirmation step before performing the action

### Requirement: Inspector follows XTop UI conventions
The system SHALL render inspector UI using the existing `DesignSystem` spacing, typography, and color helpers and SHALL avoid heavy card-based layouts in favor of compact, data-first composition.

#### Scenario: Inspector matches XTop visual style
- **WHEN** the inspector is rendered
- **THEN** the system uses `DesignSystem.Spacing`, `DesignSystem.Typography`, and `DesignSystem.Colors`, and avoids unnecessary background containers or oversized typography
