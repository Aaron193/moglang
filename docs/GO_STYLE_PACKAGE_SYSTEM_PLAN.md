# Go-Style Package System Plan

## Goal

Make Mog packages usable without custom package infrastructure.

The target user experience is:

```mog
const math = @import("github.com/aaron193/math")
const vec = @import("gitlab.com/acme/vec")
const local = @import("./local.mog")
```

The compiler and package manager should treat hosted Git repositories as the
default distribution mechanism:

1. Parse the import path.
2. Recognize supported Git hosts or explicit Git URLs.
3. Clone or fetch the repository.
4. Cache the resolved source locally.
5. Read the package manifest.
6. Build source or native artifacts as needed.
7. Record exact commits in `mog.lock`.

Registries should become optional. A project should be able to depend on public
GitHub, GitLab, Codeberg, Bitbucket, or self-hosted Git repositories without any
Mog-operated server.

## Current State

Mog already has important pieces:

- Git dependencies exist in `DependencySpec`.
- `mog add --git <url> --tag|--branch|--rev` clones repositories.
- Git checkouts are cached under the Git cache root.
- `mog.lock` records resolved package entries.
- `mog install` materializes dependencies into `.mog/install/packages`.
- Runtime and tooling resolve packages through `.mog/install/registry.toml`.

The missing Go-style behavior is import-path-driven resolution.

Currently:

- Package imports are bare names such as `@import("window")`.
- `resolvePackageRegistryEntry` rejects names containing `:`.
- Imports do not derive a repository URL.
- Published package specs still require a configured registry.
- Source code imports and package dependencies are conceptually separate.

## Design Decision

Use repository import paths as package identity for external source packages.

Example:

```mog
const math = @import("github.com/aaron193/math")
```

This import path should mean:

- package import path: `github.com/aaron193/math`
- default Git URL: `https://github.com/aaron193/math.git`
- package identity: `github.com/aaron193/math`
- lock identity: resolved commit hash plus selected version/ref
- local materialization path: `.mog/install/packages/github.com/aaron193/math`

Native packages can use the same identity model, but they still need a manifest
and a supported build strategy.

## Manifest Model

Keep `mog.toml`, but add first-class import-path metadata.

Package manifest example:

```toml
kind = "source"
module = "github.com/aaron193/math"
version = "0.1.0"
entry = "src/main.mog"
```

Native package example:

```toml
kind = "native"
module = "github.com/acme/window"
version = "0.1.0"
abi_version = 3
mog_runtime = "^0.1.0"

[native]
entry = "package"
build = "cmake"
targets = ["linux-x86_64-gnu"]
```

Migration rule:

- Keep accepting `namespace`, `name`, and `import_name` for existing packages.
- Prefer `module` when present.
- Derive legacy `package_id` from `module` only for compatibility.
- Stop requiring external packages to fit `namespace:name`.

Files to change:

- [PackageManifest.hpp](/home/dev/Desktop/projects/programming-language/src/PackageManifest.hpp)
- [PackageManifest.cpp](/home/dev/Desktop/projects/programming-language/src/PackageManifest.cpp)
- [PackageRegistry.hpp](/home/dev/Desktop/projects/programming-language/src/PackageRegistry.hpp)
- [PackageRegistry.cpp](/home/dev/Desktop/projects/programming-language/src/PackageRegistry.cpp)

## Import Classification

Replace the current binary split of "source path import" vs "bare package
import" with four import classes:

1. Local source module:
   `./foo.mog`, `../foo.mog`, `/abs/foo.mog`

2. Standard package:
   `std/math`, `std/io`, or another reserved standard-library prefix

3. Installed package alias:
   Existing bare imports such as `window`, kept for compatibility

4. Remote module import:
   `github.com/owner/repo`, `github.com/owner/repo/subpkg`,
   `gitlab.com/group/repo`, `codeberg.org/user/repo`, explicit Git URL forms

Add a helper:

```cpp
enum class ImportSpecifierKind {
    LocalSource,
    StandardPackage,
    InstalledAlias,
    RemoteModule,
    Invalid,
};
```

Likely location:

- [ModuleResolver.hpp](/home/dev/Desktop/projects/programming-language/src/ModuleResolver.hpp)
- [ModuleResolver.cpp](/home/dev/Desktop/projects/programming-language/src/ModuleResolver.cpp)

This keeps syntax decisions out of `AstFrontend` and `PackageRegistry`.

## Remote Path Resolution

Add a `RemoteImportResolver` layer.

Responsibilities:

- Parse import paths into repository root and optional subpackage path.
- Map known hosts to Git URLs.
- Allow explicit `.git` URLs.
- Reject ambiguous or unsafe paths.
- Support vanity import metadata later.

Initial supported forms:

```text
github.com/<owner>/<repo>
github.com/<owner>/<repo>/<subpackage>
gitlab.com/<group>/<repo>
gitlab.com/<group>/<repo>/<subpackage>
codeberg.org/<owner>/<repo>
bitbucket.org/<owner>/<repo>
https://host/path/repo.git
ssh://git@host/path/repo.git
git@host:path/repo.git
```

Repository root rules:

- GitHub: first three segments are root: `github.com/owner/repo`.
- GitLab and Codeberg: start with first three segments for V1.
- Self-hosted HTTPS or SSH: require `.git` unless a future vanity resolver says
  otherwise.

New types:

```cpp
struct RemoteImportSpec {
    std::string importPath;
    std::string repoRoot;
    std::string subdir;
    std::string gitUrl;
};
```

Likely files:

- Add `src/RemoteImportResolver.hpp`
- Add `src/RemoteImportResolver.cpp`
- Wire into `CMakeLists.txt`

## Dependency Spec Changes

Extend `DependencySpec` to represent module imports directly.

Current Git dependency:

```toml
math = { package = "acme:math", git = "https://github.com/acme/math.git", tag = "v1.0.0" }
```

New preferred shape:

```toml
[dependencies]
"github.com/acme/math" = { version = "v1.0.0" }
```

For branch or commit:

```toml
[dependencies]
"github.com/acme/math" = { branch = "main" }
"github.com/acme/math" = { rev = "40c199..." }
```

Internal representation should fill:

- `alias`: optional local alias only
- `module`: canonical import path
- `git`: derived Git URL
- `gitTag`, `gitBranch`, or `gitRev`
- `packageId`: legacy compatibility value, eventually optional

Files to change:

- [DependencySpec.hpp](/home/dev/Desktop/projects/programming-language/src/DependencySpec.hpp)
- [PackageManifest.cpp](/home/dev/Desktop/projects/programming-language/src/PackageManifest.cpp)
- [PackageManager.cpp](/home/dev/Desktop/projects/programming-language/src/PackageManager.cpp)

## Install Behavior

`mog install` should resolve all remote module imports from `mog.toml`.

Algorithm:

1. Load project manifest.
2. Convert each module-shaped dependency key into a `RemoteImportSpec`.
3. Clone or fetch the repo using the existing Git cache.
4. Resolve the selected version:
   - exact commit if `rev` is present
   - tag if `version` or `tag` is present
   - branch if `branch` is present
   - default branch only for explicit development mode
5. Read `mog.toml` from repo root or subdir.
6. Verify `module` matches the imported module path or subpath.
7. Resolve transitive dependencies from that package manifest.
8. Materialize packages into `.mog/install/packages`.
9. Write `.mog/install/registry.toml`.
10. Write `mog.lock` with exact commits.

Important rule:

Do not let ordinary reproducible installs float on a remote default branch.
If the user imports a package without a version, resolve once, pin the commit
in `mog.lock`, and require `mog update` to move it.

## Lockfile Format

Lock entries need to preserve both module identity and Git source details.

Example:

```toml
[[package]]
module = "github.com/acme/math"
version = "v1.0.0"
git = "https://github.com/acme/math.git"
git_tag = "v1.0.0"
git_commit = "40c199..."
kind = "source"
package_dir = ".mog/install/packages/github.com/acme/math"
entry = ".mog/install/packages/github.com/acme/math/src/main.mog"
```

For subpackages:

```toml
[[package]]
module = "github.com/acme/toolkit/parser"
repo_root = "github.com/acme/toolkit"
subdir = "parser"
git = "https://github.com/acme/toolkit.git"
git_commit = "40c199..."
```

Files to change:

- Lockfile read/write helpers in [PackageManager.cpp](/home/dev/Desktop/projects/programming-language/src/PackageManager.cpp)
- Installed metadata loading in [PackageRegistry.cpp](/home/dev/Desktop/projects/programming-language/src/PackageRegistry.cpp)

## Import Resolution At Compile Time

The compiler should not run arbitrary network fetches during normal import
resolution. That keeps diagnostics deterministic and avoids surprising network
activity.

Compile-time behavior:

1. `@import("./x.mog")` resolves as a local source file.
2. `@import("github.com/acme/math")` checks `.mog/install/registry.toml`.
3. If missing, report:

```text
Package 'github.com/acme/math' is not installed. Run 'mog install'.
```

4. `mog run app.mog` may call `ensureProjectPackagesInstalled` before compile,
   as it already does.

Files to change:

- [AstFrontend.cpp](/home/dev/Desktop/projects/programming-language/src/AstFrontend.cpp)
- [PackageRegistry.cpp](/home/dev/Desktop/projects/programming-language/src/PackageRegistry.cpp)
- [Compiler.cpp](/home/dev/Desktop/projects/programming-language/src/Compiler.cpp)

## Package Registry Resolver Changes

`resolvePackageRegistryEntry` should accept full module paths.

Current behavior rejects `:` and resolves bare names. New behavior:

- Local source imports are handled before package lookup.
- `std/...` resolves to standard-library packages.
- Full module import paths resolve by `entry.module`.
- Bare import names resolve by `entry.importName` for compatibility.
- `namespace:name` can remain rejected in source imports unless explicitly
  supported as a compatibility format.

Update `PackageRegistryEntry`:

```cpp
struct PackageRegistryEntry {
    std::string module;
    std::string repoRoot;
    std::string subdir;
    ...
};
```

## CLI Changes

Keep the existing commands, but make Git-style usage the primary path.

Add dependency:

```bash
mog add github.com/acme/math@v1.0.0
mog add github.com/acme/math --branch main
mog add github.com/acme/math --rev 40c199
```

Run:

```bash
mog run app.mog
```

Install:

```bash
mog install
mog install --locked
mog update github.com/acme/math
```

Compatibility:

- Keep `mog add --git ...` as explicit advanced mode.
- Keep `mog add acme/http@^1.2.0 --registry internal` for registry users.
- Update help text to describe remote module imports first.

Files to change:

- [main.cpp](/home/dev/Desktop/projects/programming-language/src/main.cpp)
- [PackageManager.cpp](/home/dev/Desktop/projects/programming-language/src/PackageManager.cpp)

## Version Selection

Use Git tags for versions.

Rules:

- `@v1.2.3` maps to Git tag `v1.2.3`.
- `@1.2.3` may normalize to `v1.2.3` if present, otherwise `1.2.3`.
- Branch names require `--branch`.
- Commits require `--rev`.
- Semver ranges such as `^1.2.0` are registry-friendly but Git-hosted packages
  require tag enumeration.

V1 recommendation:

- Support exact tags, branches, and commits.
- Defer semver range solving for Git imports until after the basic model works.

V2:

- Fetch tags.
- Select latest semver tag satisfying `^` or `~`.
- Pin the selected tag and commit in `mog.lock`.

## Native Packages

Native packages can work without custom infrastructure, but prebuilt binary
distribution is where registries still help.

Go-style V1 native behavior:

- Clone source from Git.
- Build locally with CMake using the existing native build path.
- Cache the built artifact.
- Pin source commit in `mog.lock`.

Keep registry prebuilt support as optional:

- Registry artifacts are useful for large native packages.
- Hosted registries can remain an acceleration layer, not a requirement.

Required change:

- Make `build_from_source` the default for Git native packages.
- Make registry prebuilt lookup optional and never required for a Git import.

## Security And Reproducibility

Minimum rules:

- Never execute package build scripts except the declared native build flow.
- Reject package manifests whose `module` does not match the import path.
- Pin every remote dependency to a commit in `mog.lock`.
- `--locked` must fail if the manifest requires a remote package not present in
  the lockfile.
- `--offline` must use only cached Git checkouts and resolved commit snapshots.
- Cache paths must be based on normalized Git URL plus commit, not mutable branch
  names.

Future rules:

- Optional checksum database.
- Optional signed Git tags.
- Optional project policy to restrict allowed hosts.
- Optional `GOPRIVATE`-style setting for private hosts.

## Test Plan

Add package-manager tests:

- Parse `github.com/owner/repo` as a remote module import.
- Derive `https://github.com/owner/repo.git`.
- Clone a local test Git repository through a file URL.
- Install a source package from a Git tag.
- Install a source package from a Git commit.
- Fail `--offline` when the checkout is missing.
- Pass `--offline` when the resolved commit is cached.
- Write lockfile entries with `module`, `git`, and `git_commit`.
- Resolve `@import("github.com/acme/math")` from installed metadata.
- Report a useful diagnostic when the remote module is not installed.

Add compatibility tests:

- Existing bare package imports still work.
- Existing local path imports still work.
- Existing `--git` dependency syntax still works.
- Existing registry package tests still work.

Likely test files:

- [test_package_manager.sh](/home/dev/Desktop/projects/programming-language/tests/test_package_manager.sh)
- [test_import.sh](/home/dev/Desktop/projects/programming-language/tests/test_import.sh)
- [test_lsp_import_diagnostics.sh](/home/dev/Desktop/projects/programming-language/tests/test_lsp_import_diagnostics.sh)

## Implementation Phases

### Phase 1: Model And Parsing

- Add `module`, `repoRoot`, and `subdir` fields to package entries.
- Add `module` to package manifests.
- Add remote import classification.
- Add `RemoteImportResolver`.
- Add unit-style regression coverage for path parsing.

Outcome:

The code can classify and normalize `github.com/owner/repo/subpkg`, but install
behavior is not changed yet.

### Phase 2: Git Module Dependencies

- Let `[dependencies]` keys be full module paths.
- Teach `mog add github.com/acme/math@v1.0.0` to derive Git metadata.
- Reuse `ensureGitDependencySource` for module-shaped dependencies.
- Write `module`, `repo_root`, `subdir`, and `git_commit` into `mog.lock`.

Outcome:

Projects can install Git-hosted packages declared in `mog.toml`.

### Phase 3: Import Resolution

- Teach `resolvePackageRegistryEntry` to match by full module path.
- Keep bare-name matching for compatibility.
- Update diagnostics to say `mog install` when a remote module is missing.
- Update LSP package lookup to use the same resolver.

Outcome:

`@import("github.com/acme/math")` works after `mog install`.

### Phase 4: Transitive Dependencies

- Allow package manifests inside Git repos to declare module-shaped dependencies.
- Resolve transitive Git dependencies recursively.
- Detect cycles by module path plus commit.
- Keep registry dependencies working as an optional source.

Outcome:

Git-hosted packages can depend on other Git-hosted packages.

### Phase 5: Native Source Builds

- Default Git-native packages to local source builds.
- Cache built native artifacts by module, commit, target, and build metadata.
- Keep registry prebuilt artifacts optional.

Outcome:

Native package users do not need a binary registry.

### Phase 6: Documentation And Migration

- Update package docs to lead with remote module imports.
- Document legacy bare imports as compatibility mode.
- Add migration examples from `namespace:name` to `module`.
- Update CLI help.

Outcome:

The intended package model is clear to users.

## Compatibility Strategy

Do not remove the existing registry system immediately.

Keep these working:

- `@import("window")`
- `--package-path`
- local `packages/` discovery
- `[registries.*]`
- `mog publish`
- signed registry indexes
- prebuilt native registry artifacts

But change the default recommendation:

- Public packages: Git module imports.
- Private packages: Git module imports over SSH or HTTPS.
- Large native/prebuilt packages: optional registry.

## Main Risks

The biggest design risk is import-path identity.

If Mog lets package manifests declare a module that does not match the import
path, dependency graphs become confusing and cache poisoning becomes easier.
Make module mismatch a hard error.

The second risk is version solving.

Exact tags and commits are enough for V1. Semver ranges across Git tags should
come later, after the module identity and lockfile model are stable.

The third risk is native package builds.

Git-only distribution removes server infrastructure, but native packages still
need local compilers and system libraries. That is acceptable, but diagnostics
must be direct about missing CMake, SDL2, toolchains, or target artifacts.

## Recommended First Milestone

Build this narrow vertical slice first:

```mog
const math = @import("github.com/example/math")
```

With:

```bash
mog add github.com/example/math@v0.1.0
mog install
mog run app.mog
```

Scope:

- Source packages only.
- Exact Git tags only.
- GitHub import paths only.
- No transitive Git dependencies yet.
- Lockfile pins exact commit.
- Existing bare imports and registries remain untouched.

This proves the architecture without destabilizing native packages, registry
publishing, or version solving.
