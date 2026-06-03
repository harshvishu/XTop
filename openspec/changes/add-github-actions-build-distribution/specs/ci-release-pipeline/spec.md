## ADDED Requirements

### Requirement: Automated build on pushes and pull requests
The system SHALL run a GitHub Actions workflow that builds the `XTop` Xcode scheme on a macOS runner for every push to `main`, every pull request targeting `main`, and every `workflow_dispatch` invocation, without requiring any repository secrets.

#### Scenario: Pull request triggers build-only run
- **WHEN** a pull request is opened or updated against `main`
- **THEN** the workflow runs `xcodebuild` in Release configuration with `CODE_SIGNING_ALLOWED=NO`
- **AND** the workflow fails the check if the build fails
- **AND** no GitHub Release is created or modified

#### Scenario: Manual dispatch produces a downloadable artifact
- **WHEN** a maintainer triggers the workflow via `workflow_dispatch`
- **THEN** the workflow builds and packages the app
- **AND** uploads the `.dmg` and `.zip` as a workflow-run artifact retained for at least 7 days

### Requirement: Tag-triggered release publishing
The system SHALL publish a GitHub Release with downloadable artifacts whenever a tag matching `v*` is pushed.

#### Scenario: Pushing a version tag publishes a release
- **WHEN** a tag `vX.Y.Z` is pushed to the repository
- **THEN** the workflow builds the app with `MARKETING_VERSION=X.Y.Z`
- **AND** creates (or updates) a GitHub Release named `vX.Y.Z`
- **AND** attaches `XTop-X.Y.Z.dmg`, `XTop-X.Y.Z.zip`, and `SHA256SUMS.txt` to the release

#### Scenario: Release notes include install instructions
- **WHEN** the workflow creates a release
- **THEN** the release body includes drag-to-Applications install instructions
- **AND** documents the right-click → Open Gatekeeper workaround
- **AND** documents the `xattr -dr com.apple.quarantine` alternative
- **AND** states that the build is ad-hoc signed and not notarized

### Requirement: Build without an Apple Developer account
The system SHALL produce a runnable `.app` bundle without requiring any Apple Developer Program credentials, certificates, provisioning profiles, or notarization tokens.

#### Scenario: Workflow runs with no signing secrets configured
- **WHEN** the workflow executes on a repository that has no `APPLE_*` secrets configured
- **THEN** the build completes successfully
- **AND** the produced `.app` launches on a Mac via the documented install flow

#### Scenario: Build pins Xcode version
- **WHEN** the workflow starts
- **THEN** it selects a specific Xcode version via `xcode-select`
- **AND** records the selected Xcode and macOS versions in the build log

### Requirement: Ad-hoc code signing of the produced bundle
The system SHALL apply an ad-hoc code signature to the `.app` bundle before packaging so the bundle has a valid signature for Gatekeeper's first-launch evaluation.

#### Scenario: Bundle is ad-hoc signed
- **WHEN** the build step finishes
- **THEN** the workflow runs `codesign --force --deep --sign - --options runtime` on `XTop.app`
- **AND** `codesign --verify --deep --strict XTop.app` exits successfully

### Requirement: Drag-and-drop DMG packaging
The system SHALL package the built `.app` into a `.dmg` whose root contains the app and a symbolic link to `/Applications`, so users can install by dragging the app onto the link.

#### Scenario: DMG contains app and Applications symlink
- **WHEN** the packaging step runs
- **THEN** the produced `.dmg` mounts to a volume named `XTop`
- **AND** the volume root contains `XTop.app` and a symlink named `Applications` pointing to `/Applications`

#### Scenario: DMG is compressed
- **WHEN** `hdiutil create` runs
- **THEN** it uses the `UDZO` format for compression

### Requirement: ZIP packaging preserves code signature
The system SHALL also publish a `.zip` of the `.app` produced with `ditto` so the code signature and extended attributes are preserved on extraction.

#### Scenario: ZIP is created with ditto
- **WHEN** the packaging step runs
- **THEN** the workflow invokes `ditto -c -k --sequesterRsrc --keepParent XTop.app XTop.zip`
- **AND** unpacking the zip on a Mac produces a `XTop.app` whose `codesign --verify` succeeds

### Requirement: Published checksums
The system SHALL publish SHA-256 checksums for every release artifact.

#### Scenario: SHA256SUMS file is attached
- **WHEN** the release is created
- **THEN** a `SHA256SUMS.txt` file is attached
- **AND** it contains one line per artifact in the standard `<hex>  <filename>` format

### Requirement: User-facing install documentation
The system SHALL document how a non-developer Mac user installs the published artifact.

#### Scenario: README explains download and install
- **WHEN** a user visits the repository README
- **THEN** they find a "Download & Install" section
- **AND** it links to the latest GitHub Release
- **AND** it explains the right-click → Open first-launch flow
- **AND** it explains the `xattr` quarantine-removal alternative
- **AND** it states the build is unsigned/not notarized
