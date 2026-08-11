# Releasing Mog runtime and editor tooling

Mog has independent, immutable release streams:

- `runtime/vX.Y.Z` publishes the CLI/runtime archives and `mog-lsp` for CLI
  users.
- `vscode/vX.Y.Z` publishes target-specific VSIX packages with a bundled,
  tested server.
- A pre-release extension uses a normal three-part version and the workflow's
  `pre-release` channel option. Marketplace does not accept SemVer suffixes for
  extension versions.

Normal pushes to `main` do not publish. Both workflows may be manually run for
an existing tag, but they refuse malformed tags and existing GitHub releases.
Never move a public tag or replace public bits. Fix the problem, increment the
appropriate version, and publish a new tag.

Foundation packages are independently versioned. Their process is documented
in [PACKAGE_CI_RELEASES.md](PACKAGE_CI_RELEASES.md).

## Common release checks

Before either release:

1. Start from a clean checkout of the intended commit and review `git diff`.
2. Confirm ordinary CI is green, including the named **Editor and LSP gates**
   job.
3. Review dependency and GitHub Action updates; use pinned actions for release
   steps.
4. Confirm the changelog describes user-visible behavior, compatibility, and
   recovery steps.
5. Record runtime, extension, and tooling-protocol versions in the release
   issue. The repository includes a tooling release checklist issue template.
6. Download the workflow artifacts after the run and compare their checksums
   with the published `SHA256SUMS`.

## Runtime release

Update `MOG_VERSION`, the runtime version declaration, and `CHANGELOG.md`, then
create the tag on the exact reviewed commit:

```bash
git tag -a runtime/v0.2.0 -m "Mog runtime 0.2.0"
git push origin runtime/v0.2.0
```

The `Release Mog Runtime` workflow validates version metadata, core regressions,
all editor/LSP protocol suites, and the initialize/shutdown smoke test before
packaging starts. Each platform job then extracts every generated archive,
executes the archived `mog` and `mog-lsp`, and inspects native dependencies from
the extracted location. Checksums are generated only after every package job
passes.

Review the Linux x64, macOS ARM64, and Windows x64 assets. A runtime release is
not complete if either executable is absent, an extracted executable fails, or
a dependency resolves only from a build directory.

## VS Code extension release

Update both extension versions (`package.json` and the lockfile root) and add a
matching heading to `tooling/vscode-mog/CHANGELOG.md`. Publish breaking protocol
changes as a prerelease first.

Create and push a normal `vscode/vX.Y.Z` tag. Tag pushes publish stable. To
publish a pre-release, create the tag, then manually run **Release VS Code
Extension** for that tag with channel `pre-release`. Following Marketplace
guidance, reserve even minor versions for stable releases and odd minor versions
for pre-releases. A pre-release and stable release must never reuse the same
version.

The workflow checks tag/manifest/lockfile/changelog agreement, runs client and
protocol tests, builds one server per target, inspects native dependencies,
packages a target-specific VSIX, checks its exact contents, and runs the
extension-host suite against the package. Only those tested VSIX files reach the
protected `vscode-marketplace` environment. Store the Marketplace credential as
the environment secret `VSCE_PAT`; never put it in a repository or artifact.

Required targets are `linux-x64`, `darwin-arm64`, and `win32-x64`. Promotion to
stable uses a new stable version/tag after the prerelease artifacts have passed
verification. Do not republish a prerelease VSIX as stable under the same
version.

`mog-lsp` currently links `interpreter_core`; package-manager support in that
library reaches the registry signature implementation in OpenSSL. CMake's
`MOG_STATIC_OPENSSL` option therefore defaults to `ON` for self-contained
artifacts. Release jobs request that mode explicitly and reject dynamic OpenSSL
or unresolved dependencies from the extracted artifact. Dependency reports are
retained in the job log.
The release baselines are Ubuntu 22.04/glibc 2.35 for Linux x64, macOS 14 for
Apple Silicon, and Windows 10 for Windows x64. Raising a baseline requires a
changelog compatibility note and a prerelease validation cycle.

## Compatibility and support window

Runtime version and tooling protocol version are different. The extension
status command is the source of truth for the selected extension, server,
runtime, and protocol versions.

| Extension channel | Supported server protocol | Runtime relationship |
|---|---|---|
| Stable 0.x | Protocol major 1 | Bundled tested server; current and previous runtime minor supported |
| Pre-release 0.x | Protocol major 1, experimental minor features | Bundled prerelease server |

Within a protocol major, clients should tolerate unknown optional capabilities.
An incompatible protocol major must fail visibly with an install/rollback
action. The project supports the current stable protocol major and, during one
stable extension release cycle, the immediately previous major for migration.

## Upgrade, rollback, and recovery

Users normally upgrade or roll back the extension through VS Code's extension
version menu. A target-specific VSIX can also be installed from the GitHub
release. After changing versions, run **Mog: Show Language Server Status** and
verify the server path and protocol version.

If startup fails:

1. Open **Mog Language Support** output with **Mog: Open Language Server Log**.
2. Remove an invalid `mog.serverPath` override or deliberately select a valid
   executable. The override takes precedence over the bundled server.
3. Run **Mog: Restart Language Server** after correcting configuration.
4. If a source checkout was moved, delete or rename only
   `build/tooling-debug`, then run `bash scripts/configure_tooling_build.sh`.
   Never reuse a `CMakeCache.txt` whose `CMAKE_HOME_DIRECTORY` names another
   checkout.
5. Roll back to the last compatible extension if the log reports a protocol
   major mismatch, and attach the status output when filing an issue.

No crash/startup telemetry is collected by this release process. Diagnostics
come from explicit local logs and user-submitted issue reports. Never attach
project source, registry credentials, environment dumps, or package caches to a
public issue.

## Post-release and incident checklist

- Confirm Marketplace reports the intended stable or pre-release version for
  all targets.
- Install one published VSIX in a clean profile and open a `.mog` file.
- Verify completion, hover, diagnostics, navigation, formatting, and rename.
- Verify published checksums and archive/VSIX filenames.
- Record startup and crash regressions plus completion/hover/diagnostic/indexing
  performance against the prior release.
- If publication is partial, do not overwrite artifacts. Disable or deprecate
  the defective version where the marketplace permits, document the affected
  target, and ship a new patch version.
