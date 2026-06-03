## 1. Packaging script

- [x] 1.1 Create `script/package_app.sh` that takes a built `XTop.app` path and a version string, ad-hoc signs it (`codesign --force --deep --sign - --options runtime`), verifies the signature, and emits `XTop-<version>.zip` (via `ditto -c -k --sequesterRsrc --keepParent`) and `XTop-<version>.dmg` (via `hdiutil create -volname XTop -srcfolder <staging> -ov -format UDZO` with an `Applications` symlink in the staging dir) into an `out/` directory
- [x] 1.2 Make `script/package_app.sh` executable (`chmod +x`) and add a short usage block at the top
- [x] 1.3 Smoke-test the script locally: build via `script/build_and_run.sh`-style invocation, run the packager, mount the DMG and confirm the `Applications` symlink resolves and `XTop.app` launches via right-click → Open

## 2. GitHub Actions workflow

- [x] 2.1 Create `.github/workflows/build-and-release.yml` with triggers: `pull_request` (branches: `[main]`), `push` (branches: `[main]`, tags: `['v*']`), and `workflow_dispatch`
- [x] 2.2 Add a single `build` job running on `macos-14` with `permissions: contents: write` (needed only for the release step)
- [x] 2.3 Add steps: checkout, `sudo xcode-select -s /Applications/Xcode_16.app`, print `xcodebuild -version` and `sw_vers` to the log for traceability
- [x] 2.4 Add a "Determine version" step: if `github.ref` starts with `refs/tags/v`, set `VERSION=${GITHUB_REF_NAME#v}`; else `VERSION=0.0.0-${GITHUB_SHA::7}`. Export as `$GITHUB_ENV`
- [x] 2.5 Add a "Build" step: `xcodebuild -project XTop.xcodeproj -scheme XTop -configuration Release -derivedDataPath build -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER build`
- [x] 2.6 Add a "Package" step that invokes `script/package_app.sh build/Build/Products/Release/XTop.app $VERSION`
- [x] 2.7 Add a "Generate checksums" step that writes `out/SHA256SUMS.txt` using `shasum -a 256 XTop-*.dmg XTop-*.zip`
- [x] 2.8 Add an `actions/upload-artifact@v4` step that uploads `out/*` with name `XTop-${{ env.VERSION }}` and `retention-days: 14` (runs for all triggers)
- [x] 2.9 Add a "Create GitHub Release" step gated by `if: startsWith(github.ref, 'refs/tags/v')` using `softprops/action-gh-release@v2` with `files: out/*` and a `body` containing install instructions, the unsigned-build disclaimer, and the SHA-256 list

## 3. Documentation

- [x] 3.1 Add a "Download & Install" section to `README.md` linking to the latest release, with: (a) drag-to-Applications instructions, (b) right-click → Open first-launch flow, (c) the `xattr -dr com.apple.quarantine /Applications/XTop.app` alternative, (d) explicit "ad-hoc signed, not notarized" note
- [x] 3.2 Add a short "Releasing" section (or `docs/RELEASING.md`) describing the tag-to-release flow: `git tag vX.Y.Z && git push origin vX.Y.Z`

## 4. Validation

- [ ] 4.1 Open a PR with the workflow and confirm the build-only run on `pull_request` succeeds
- [ ] 4.2 After merge, trigger `workflow_dispatch` from `main` and download the run artifact; verify the `.dmg` mounts and the `.app` launches on a clean Mac account via right-click → Open
- [ ] 4.3 Cut a throwaway `v0.0.1-test` tag, confirm a draft/prerelease is created with `.dmg`, `.zip`, and `SHA256SUMS.txt`, then delete the tag and release
- [x] 4.4 Verify `codesign --verify --deep --strict` and `spctl --assess --type execute --verbose` outputs on the downloaded `.app` match expectations (spctl will reject ad-hoc; that is expected and the docs cover the right-click flow)
- [x] 4.5 Run `openspec validate add-github-actions-build-distribution --strict` and fix any reported issues
