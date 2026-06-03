## Context

XTop is a SwiftUI macOS app built with `xcodebuild` against `XTop.xcodeproj`. The existing `script/build_and_run.sh` already builds with `CODE_SIGNING_ALLOWED=NO` for local development. There is no published binary today; all install paths require a clone-and-build. Maintainers do not have a paid Apple Developer Program membership, so neither Developer ID signing nor notarization is possible. The goal is a zero-credential CI pipeline that still produces an artifact a non-developer Mac user can install with one or two clicks.

## Goals / Non-Goals

**Goals:**
- Reproducible release builds on GitHub-hosted macOS runners with no secrets required.
- Produce both `.dmg` (drag-to-Applications) and `.zip` artifacts for every release tag.
- Ad-hoc sign (`codesign --sign -`) so the bundle has a stable code signature and survives Gatekeeper's "is damaged" verdict when downloaded via the documented right-click → Open flow.
- CI on PRs and `main` to catch build breakage early (no artifact publishing for PRs).
- Clear, documented end-user install instructions covering the Gatekeeper quarantine workaround.

**Non-Goals:**
- Apple Developer ID code signing or notarization (requires paid account).
- Mac App Store submission.
- Auto-update / Sparkle integration (can be added later; out of scope here).
- Universal binary fan-out beyond what `xcodebuild` produces by default for the active scheme.
- Reproducible/hermetic builds beyond what GitHub Actions naturally provides.

## Decisions

### 1. Use `xcodebuild` directly, not `xcrun xcodebuild archive`
Use `xcodebuild -project XTop.xcodeproj -scheme XTop -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build`. The `archive` action wants a signing identity by default and adds friction. The non-archive build still yields a complete `.app` bundle in `build/Build/Products/Release/XTop.app`, which is all we need.

**Alternative considered:** `xcodebuild archive` + `xcodebuild -exportArchive`. Rejected because `exportArchive` requires an `ExportOptions.plist` with `signingStyle`/`teamID`, neither of which we have.

### 2. Ad-hoc sign with `codesign --sign - --deep --force --options runtime`
After build, run `codesign --force --deep --sign - --options runtime XTop.app`. Ad-hoc signatures are accepted by Gatekeeper when the user explicitly opens via right-click → Open, or after removing the quarantine xattr. This also protects against the "killed: 9" verdict on Apple Silicon for unsigned binaries.

**Alternative considered:** Skip signing entirely. Rejected because unsigned binaries on Apple Silicon hit `arm64e`/Gatekeeper rejection more often and produce a worse UX.

### 3. Package as both `.dmg` and `.zip`
- `.dmg`: built with `hdiutil create -volname XTop -srcfolder <staging_dir> -ov -format UDZO`, where the staging dir contains `XTop.app` plus a symlink to `/Applications`. This is the most familiar install UX for Mac users.
- `.zip`: built with `ditto -c -k --sequesterRsrc --keepParent XTop.app XTop.zip` (preserves resource forks and code signature; `zip` does not).

**Alternative considered:** `create-dmg` Homebrew tool for fancier DMG layout/background. Rejected as overkill and an extra dependency; raw `hdiutil` is sufficient and ships with macOS.

### 4. Runner: `macos-14` (Apple Silicon)
Apple Silicon runner with Xcode 16+ preinstalled. Pin Xcode version explicitly via `sudo xcode-select -s /Applications/Xcode_16.app` to avoid drift.

**Alternative considered:** `macos-latest`. Rejected because it can change between runner image releases and silently break builds.

### 5. Trigger matrix
- `pull_request` and `push` to `main`: build only, upload artifact to workflow run for inspection.
- `workflow_dispatch`: same as `main`, manual trigger.
- `push` of tag matching `v*`: build, package, create GitHub Release, attach `.dmg`, `.zip`, and `SHA256SUMS.txt`.

**Alternative considered:** Use `release: published` trigger. Rejected because we want the workflow to *create* the release from the tag, not react to a manual release.

### 6. Versioning
Derive `MARKETING_VERSION` from the tag (`v1.2.3` → `1.2.3`) by passing `MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER` on the `xcodebuild` command line. Falls back to the project's value on non-tag builds.

### 7. Release notes content
Auto-generated body includes:
- Download links for `.dmg` and `.zip`.
- SHA-256 checksums.
- Install instructions: drag to Applications, then *right-click → Open* the first time, OR run `xattr -dr com.apple.quarantine /Applications/XTop.app`.
- Explicit "unsigned build" disclaimer.

## Risks / Trade-offs

- **Gatekeeper friction** → Mitigation: prominent install instructions in README + release notes; ad-hoc signing reduces but does not eliminate the warning.
- **Quarantine xattr blocks first launch** → Mitigation: document `xattr -dr com.apple.quarantine` one-liner; recommend right-click → Open as primary path.
- **Xcode version drift on runners breaks build** → Mitigation: pin Xcode version explicitly in the workflow and update via PR when bumping.
- **GitHub Actions macOS minutes cost more than Linux** → Mitigation: only run full package step on tags; PRs do a quick build-only check. Use `actions/cache` for SwiftPM dependencies if any are added later.
- **No notarization means Safari/Chrome may warn on download** → Mitigation: documented; acceptable for a hobby/open-source release without a paid account.
- **`.dmg` size from `UDZO` compression is acceptable but not minimal** → Acceptable trade-off; the app is small.
- **Ad-hoc signature invalidated if user modifies bundle** → Acceptable; users do not normally modify `.app` contents.

## Migration Plan

1. Land workflow and packaging script on `main`; verify a `workflow_dispatch` run succeeds and produces artifacts.
2. Cut a `v0.0.1-test` tag to validate the release path end-to-end on a draft release.
3. Delete the draft, then cut the first real `v0.1.0` tag.
4. Update README with the download link template once a release exists.

Rollback: delete the workflow file and any published release; no source code is affected.

## Open Questions

- Should we also publish a Homebrew tap cask for `brew install --cask xtop`? Out of scope for this change but a natural follow-up.
- Do we want nightly builds from `main`? Defer until there is user demand.
