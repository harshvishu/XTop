# swift6-environment-injection Delta Specification

## ADDED Requirements

### Requirement: XcodeProjectDetecting and ExcludedArchsManaging services are injected via MacbarViewModel
`MacbarViewModel` SHALL accept `XcodeProjectDetecting` and `ExcludedArchsManaging` as explicit initializer parameters, following the existing dependency injection pattern.

#### Scenario: MacbarViewModel is initialized with new services
- **WHEN** the app root creates `MacbarViewModel`
- **THEN** concrete implementations of `XcodeProjectDetecting` and `ExcludedArchsManaging` are passed as arguments

#### Scenario: Test creates isolated MacbarViewModel
- **WHEN** a unit test creates `MacbarViewModel` for testing arch manager or detection logic
- **THEN** it can supply stub or spy implementations without any process-global side effects

### Requirement: New services conform to Sendable and run without main-actor isolation
`XcodeProjectDetector` and `ExcludedArchsManager` SHALL be declared as `actor` or `struct` conforming to their respective protocols with `Sendable`, performing filesystem work off the main actor.

#### Scenario: Arch action does not block the main actor
- **WHEN** `ExcludedArchsManager` applies a mutation to a large `project.pbxproj`
- **THEN** the main actor is not blocked during file reading or writing
