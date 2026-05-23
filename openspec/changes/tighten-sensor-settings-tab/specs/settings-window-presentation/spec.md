## ADDED Requirements

### Requirement: Settings window comes to the front when opened

When the user opens the Settings window from any in-app entry point (the menu bar panel's `SettingsLink`, a keyboard shortcut, or a programmatic `openSettings()` call), XTop SHALL activate the application and bring the Settings window to the front as the key window even though the app runs as `LSUIElement` and is normally non-foreground.

#### Scenario: User opens Settings from the menu bar panel
- **WHEN** the user invokes the Settings entry from the menu bar panel
- **THEN** the Settings window appears in front of other windows, becomes the key window, and the app is the active app

#### Scenario: Another app currently has focus when Settings opens
- **WHEN** another application has focus at the moment Settings is opened
- **THEN** XTop activates itself and the Settings window is ordered above the previously focused app's windows

#### Scenario: Settings is reopened after being closed
- **WHEN** the user closes the Settings window and reopens it
- **THEN** the Settings window again appears in front and becomes key on every open, not only the first

### Requirement: Settings activation does not require user interaction beyond opening

XTop SHALL NOT require the user to click the Dock icon, alt-tab, or otherwise manually surface the Settings window after invoking Settings. The activation SHALL happen automatically as part of opening.

#### Scenario: User opens Settings while a full-screen app is active
- **WHEN** the user invokes Settings while a full-screen app is the active app
- **THEN** XTop activates and the Settings window is presented without the user needing to switch Spaces or apps to find it
