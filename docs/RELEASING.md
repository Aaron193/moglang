# Releasing Mog

Mog releases are built by GitHub Actions when a version tag beginning with `v`
is pushed. Ordinary pushes to `main` do **not** create a release.

Foundation packages are independently versioned and released. Their shared CI,
tagging, consumer installation, and registry publication process is documented
in [PACKAGE_CI_RELEASES.md](PACKAGE_CI_RELEASES.md).

## Before releasing

1. Finish the intended changes and run relevant local tests.
2. Run `bash ../packages/github.com/moglang/ci/validate-packages.sh ./build/interpreter`
   after building the runtime. This validates every package contract and test;
   the GitHub workflow repeats the native checks on Linux x86_64/ARM64 and
   macOS ARM64.
3. Release the runtime before packages that declare its new minimum version.
   Current foundation packages require runtime `^0.1.4`; package CI tests both
   the 0.1.4 compatibility floor and runtime `main`.
4. Set the release version in the VS Code extension manifest when the editor
   extension changed. Edit `tooling/vscode-mog/package.json` and commit it with
   the release.
5. Commit and push the release source:

   ```bash
   git add <changed-files>
   git commit -m "Describe the release changes"
   git push origin main
   ```

## Choose a version

Mog uses semantic versioning:

- Patch (`v0.1.6`): backward-compatible runtime or tooling improvements.
- Minor (`v0.2.0`): backwards-compatible language or tooling feature.
- Major (`v1.0.0`): breaking language, CLI, or package compatibility change.

## Publish a runtime release

Tag the exact commit that should be released and push only that tag:

```bash
git tag -a v0.1.6 -m "Mog 0.1.6"
git push origin v0.1.6
```

The `Release Mog` GitHub Actions workflow then:

1. Builds `mog` and `mog-lsp` on Linux x64, macOS ARM64, and Windows x64.
2. Produces `.tar.gz` and `.zip` archives for each platform.
3. Verifies the embedded `mog --version` output against the tag.
4. Creates or updates the matching GitHub Release and attaches the archives and
   `SHA256SUMS`.

Open the workflow run in GitHub Actions and wait for every job to succeed.
Then review the release notes and assets on the GitHub Releases page.

## Publish the VS Code extension

The VS Code extension is versioned independently in
`tooling/vscode-mog/package.json`. Keep its version aligned with the Git tag
unless there is a reason to publish it separately.

```bash
cd tooling/vscode-mog
npx @vscode/vsce publish
```

This uses the publisher credentials created with `npx @vscode/vsce login
moglang`. Do not commit the Marketplace token. Store it in a password manager;
for CI, store it as a GitHub Actions secret.

## User installation

Users download the archive for their platform, extract it, and add its `bin`
directory to `PATH`. The distribution contains both `mog` and `mog-lsp`.

```bash
mog program.mog
```

The Marketplace extension supplies syntax highlighting and LSP features. It
finds `mog-lsp` automatically when the executable is on the editor's `PATH`.

## If a release build fails

Do not replace an existing version tag with different source. Fix the issue,
increment the runtime version, update the changelog, and publish a new tag after
CI passes. Tags and published release artifacts are immutable release records.
