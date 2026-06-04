## MODIFIED Requirements

### Requirement: Simulator Inspector per-app tab strip includes a Camera tab
The Simulator Inspector's per-app tab strip SHALL include a "Camera" tab in addition to the existing UserDefaults, App Groups, and Keychain tabs, placed after "App Groups" and before "Keychain". The visibility, ordering, and behavior of the existing tabs SHALL remain unchanged.

#### Scenario: Tab strip ordering is stable
- **WHEN** the user selects an installed app in the Simulator Inspector
- **THEN** the per-app tab strip lists, in order: UserDefaults, App Groups, Camera, Keychain
