## ADDED Requirements

### Requirement: System reads UserDefaults with preserved types
The system SHALL read the selected app's `UserDefaults` from `<container>/Library/Preferences/<bundleID>.plist` and present each entry with its original plist value type.

#### Scenario: UserDefaults entries are listed with types
- **WHEN** a user opens the UserDefaults tab for an installed app
- **THEN** the system displays every key with its value and its plist type (Bool, Int, Double, String, Date, Data, Array, Dictionary)

#### Scenario: UserDefaults plist does not yet exist
- **WHEN** the selected app has never written to `UserDefaults`
- **THEN** the system displays an empty state and allows adding the first entry

### Requirement: System edits, adds, and deletes UserDefaults entries with type fidelity
The system SHALL allow users to edit existing entries, add new entries with explicit type selection, and delete entries, persisting changes to the on-disk plist while preserving plist value types.

#### Scenario: Editing an entry preserves its type
- **WHEN** a user edits the value of an existing entry
- **THEN** the system writes the entry back with its original plist type preserved

#### Scenario: Adding a new entry requires a type
- **WHEN** a user adds a new entry
- **THEN** the system requires an explicit plist type selection and stores the entry with that type

#### Scenario: Deleting an entry removes it from the plist
- **WHEN** a user confirms deletion of an entry
- **THEN** the system removes the entry from the on-disk plist

### Requirement: System warns when target app is running before writes
The system SHALL detect whether the inspected app is currently running on the simulator and SHALL warn the user before any write operation.

#### Scenario: Write is attempted while target app is running
- **WHEN** the user initiates a write while the inspected app is running
- **THEN** the system surfaces a warning that edits may be overwritten unless the app is terminated first

### Requirement: System inspects App Group UserDefaults
The system SHALL support reading and editing `UserDefaults` plists located in resolved App Group containers using the same typed read/write behavior as the primary app `UserDefaults`.

#### Scenario: App Group UserDefaults are editable
- **WHEN** a user selects an App Group container for the inspected app
- **THEN** the system reads, edits, adds, and deletes entries in that App Group's `UserDefaults` plist with type fidelity
