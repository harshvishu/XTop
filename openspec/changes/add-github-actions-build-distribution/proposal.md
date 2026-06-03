## Why

XTop currently has no automated way to produce a distributable macOS binary; contributors must build locally via `script/build_and_run.sh` and there is no public artifact for users to install. We need a CI-driven build that publishes a drag-and-drop installable `.app` (and `.dmg`/`.zip`) on every tagged release, without requiring a paid Apple Developer account or notarization credentials.

## What Changes

- Add a GitHub Actions workflow that builds the `XTop` Xcode scheme on macOS runners using `xcodebuild` with `CODE_SIGNING_ALLOWED=NO` (matching the local script), so it works without Apple Developer signing identities.
- Apply ad-hoc signing (`codesign --sign -`) to the produced `.app` so Gatekeeper allows it to launch via right-click → Open without a developer certificate.
- Package the `.app` into both a `.zip` (download) and a `.dmg` with a drag-to-Applications layout for end-user installation.
- Trigger the workflow on pushes to `main`, pull requests (build-only, no publish), manual `workflow_dispatch`, and `v*` tag pushes (publish a GitHub Release with attached artifacts).
- Generate SHA-256 checksums for published artifacts and include install instructions (right-click → Open, or `xattr -dr com.apple.quarantine`) in the release notes.
- Document the unsigned-distribution caveats (Gatekeeper warning, no notarization) in README and release notes.

## Capabilities

### New Capabilities
- `ci-release-pipeline`: Automated GitHub Actions build, ad-hoc signing, packaging, and release publishing for the macOS app without an Apple Developer account.

### Modified Capabilities
<!-- None: this is purely CI/distribution; no existing spec requirements change. -->

## Impact

- New file: `.github/workflows/build-and-release.yml`.
- New files: `script/package_app.sh` (zip/dmg packaging helper) and optionally `script/sign_adhoc.sh`.
- `README.md` updated with a "Download & Install" section explaining the unsigned-app flow.
- No source code changes to the Swift app, no new runtime dependencies.
- GitHub Releases will host downloadable `.dmg` and `.zip` artifacts; repository must allow Actions to write releases (`contents: write` permission in workflow).
- Build minutes consumed on GitHub-hosted `macos-14` (or newer) runners.
