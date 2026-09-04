# Package CI, Versioning, and Releases

This is the release policy for the independently versioned packages in the
`kelvralang` GitHub organization. Package repositories keep their implementation,
tests, and workflows locally; this document is the shared explanation of how
those workflows are expected to behave.

For runtime releases, see [RELEASING.md](RELEASING.md). For the current runtime
and native ABI compatibility floor, see
[PACKAGE_COMPATIBILITY.md](PACKAGE_COMPATIBILITY.md).

## What package CI does

Every package has a `Package CI` workflow. It runs for pull requests, pushes to
`main`, and version tags. The final job is always named `validate`, providing a
stable branch-protection check even when the compatibility matrix changes.

The workflow verifies that:

- `kelvra.toml` has a version and a supported license declaration;
- `LICENSE`, `README.md`, `CHANGELOG.md`, `package.api.kel`, and
  `tests/main.kel` are present and consistent;
- the changelog contains an entry for the manifest version;
- a tag such as `v0.2.0` matches manifest version `0.2.0` exactly;
- the package passes `kelvra validate-package`;
- its public test program succeeds from a separate consumer project; and
- fixtures under `tests/errors/` fail as intended.

Source packages are tested against the Kelvra `v0.2.0` compatibility floor and
Kelvra `main` after the initial 0.2.0 release bootstrap. Native packages also build with strict
compiler warnings and test these target/runtime combinations:

| Target | Runtime ref |
| --- | --- |
| Linux x86_64 | `v0.2.0` and `main` |
| Linux ARM64 | `main` |
| macOS ARM64 | `main` |

Window installs SDL2 in CI and runs with a headless video driver. Native package
manifests must declare every target built by the matrix.

Testing both the compatibility floor and runtime `main` catches two different
classes of problem: accidentally raising the minimum runtime and upcoming
runtime changes that would break a package.

## Version fields have separate meanings

Packages use semantic versioning independently from Kelvra itself:

- Patch: backwards-compatible bug, documentation, or packaging fix.
- Minor: backwards-compatible API or feature addition.
- Major: breaking API, behavior, package identity, or native ABI change.

Before `1.0.0`, incompatible API changes normally increment the minor version.
Kelvra applies standard pre-1.0 caret boundaries: `^0.2.0` accepts versions from
`0.2.0` up to, but not including, `0.3.0`; `^0.0.4` accepts only compatible
`0.0.4` patch releases.

Do not confuse these manifest fields:

- `version` is the version of the package.
- `kelvra_runtime` is the compatible Kelvra toolchain range. Raise it only when the
  package actually stops working with the existing floor.
- `native_abi` is the loader ABI for native packages. It must match the ABI
  printed by `kelvra --version`.

Package and runtime versions do not need to match. If a package raises its
`kelvra_runtime` floor, release the required Kelvra runtime first, then release the
package.

## Preparing a package release

Make the following changes together in one pull request:

1. Choose the next semantic version.
2. Set `version` in `kelvra.toml` without a leading `v`.
3. Add a matching `## X.Y.Z` entry to `CHANGELOG.md`.
4. Update `package.api.kel`, implementation, examples, and tests as needed.
5. Update `kelvra_runtime`, `native_abi`, targets, or system dependencies only when
   compatibility actually changed.
6. Wait for the required `validate` check and every matrix job to pass.
7. Merge the pull request before creating the tag.

For example, a manifest release version is written as:

```toml
version = "0.2.0"
kelvra_runtime = "^0.2.0"
```

The corresponding Git tag is `v0.2.0`. The release workflow rejects a tag that
does not exactly match `kelvra.toml`, and Kelvra rejects a Git dependency when its
selected tag disagrees with the package manifest.

## Tagging and GitHub Releases

Tag the exact commit on `main` that passed CI:

```bash
git switch main
git pull --ff-only
git tag -a v0.2.0 -m "Release 0.2.0"
git push origin v0.2.0
```

Pushing a `v*` tag starts the package release workflow. A normal push to `main`
never creates a release.

For a source package, the workflow validates the package with Kelvra `main`, runs
its tests, creates a source archive, generates `SHA256SUMS`, and attaches both
to a GitHub Release.

For a native package, the workflow builds and validates every supported target,
creates one archive per target, generates a combined `SHA256SUMS`, and attaches
the artifacts to a GitHub Release. A failure on any target prevents the release
job from publishing a partial set.

After the workflow succeeds:

1. Confirm the GitHub Release points at the intended commit.
2. Confirm all expected archives and `SHA256SUMS` are present.
3. Test a clean consumer installation using the new tag.
4. For native packages, smoke-test each target artifact when suitable runners
   are available.

Treat published tags as immutable. Do not force-push or replace a version tag.
If a release is defective, fix it on `main`, increment the package version, and
publish a new tag.

## How users select and import a package

A Git dependency selects the Git tag in the project manifest:

```toml
[dependencies]
"github.com/kelvralang/encoding" = { version = "v0.2.0" }
```

The source code imports the canonical module path, not the local installation
directory and not the GitHub Release archive name:

```kelvra
const encoding = @import("github.com/kelvralang/encoding")
```

Users then install and run through their own Kelvra executable:

```bash
kelvra --version
kelvra install
kelvra run app.kel
```

Commit `kelvra.lock` for applications and use `kelvra install --locked` in CI so the
same package tag and content are installed reproducibly.

Git dependencies for native packages build from source and therefore require
the declared compiler, CMake, and system libraries. The target archives on a
GitHub Release are convenience artifacts; Kelvra does not automatically treat
them as registry packages.

## GitHub Releases versus a Kelvra registry

The tag workflows publish GitHub Release assets and checksums. They do not:

- publish or promote a package in a configured Kelvra registry;
- sign a registry index or native registry artifact;
- manage registry credentials; or
- publish the VS Code extension.

Prebuilt native installation requires a separate `kelvra publish` operation for
each target against a configured registry, with the deployment's credentials
and signing key. Keep those secrets outside the repository. For example:

```bash
kelvra publish --registry official \
  --target linux-x86_64-gnu \
  --native-artifact-dir ./dist/linux-x86_64-gnu \
  --signing-key ./keys/release.toml .
```

Registry publication should happen only after the Git tag workflow is green and
must use the same manifest version and source commit.

## Automation maintenance

GitHub Actions are pinned to commit SHAs. Dependabot proposes weekly updates to
those pins. Review and merge such updates like any other CI change; do not
replace a pinned action with a floating branch or mutable tag.

When the supported runtime floor or target matrix changes, update the package
workflows and [PACKAGE_COMPATIBILITY.md](PACKAGE_COMPATIBILITY.md) together.
