# Migrating from Mog to Kelvra

Kelvra is the new name of the language previously called Mog. This is a clean,
breaking rename: the runtime does not keep aliases for the old source extension,
manifest names, CLI, editor identifiers, or package metadata fields.

The runtime repository remains [`kelvralang/kelvra`](https://github.com/kelvralang/kelvra).
Official package repositories and import paths use the `kelvralang`
organization.

## Project migration

Rename project files and generated state as follows:

| Before | After |
| --- | --- |
| `*.mog` | `*.kel` |
| `package.api.mog` | `package.api.kel` |
| `mog.toml` | `kelvra.toml` |
| `mog.lock` | `kelvra.lock` |
| `.mog/` | `.kelvra/` |

Update source imports from paths such as `./math.mog` to `./math.kel`. Change
official imports from `github.com/moglang/<package>` to
`github.com/kelvralang/<package>`.

Project and package manifests now use `kelvra_runtime` instead of
`mog_runtime`. Regenerate lockfiles and installed state with `kelvra install`;
do not copy digest or cache metadata from an old lockfile by hand.

## Tooling migration

The user-facing executables are `kelvra` and `kelvra-lsp`. Environment variables
that began with `MOG_` now begin with `KELVRA_`, including `KELVRA_CACHE_DIR`
and `KELVRA_LSP_PATH`.

The VS Code language identifier is `kelvra`, the extension is
`kelvralang.vscode-kelvra`, and settings use the `kelvra.*` namespace. Remove
the old Mog extension before installing the Kelvra extension so both language
clients do not activate for the same workspace.

## Coordinated release notes

Existing package tags contain Mog-era filenames and metadata, so official
packages need new releases before they can be consumed by a Kelvra-only
runtime. Merge the coordinated changes to the runtime, package templates,
package actions, and official package default branches before cutting tags.
Then publish new package versions, the runtime archives, and finally the VS Code
extension. Verify that release workflows reference `kelvralang/kelvra` for the
runtime repository and `kelvralang/<package>` for package repositories.
