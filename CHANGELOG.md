# Changelog

## 0.1.7

- Install Python on the Windows runtime release runner so packaged `mog-lsp`
  smoke validation can complete before archives are published.

## 0.1.6

- Add Host API v2 so native packages can retain Mog values and invoke Mog
  callbacks safely across garbage collections.
- Preserve callback results, native handles, byte arrays, nested invocations,
  and recoverable runtime errors across the native package boundary.
- Reject persistent values used by a different VM or from a foreign thread.
- Generate the package manager's published native API header from the canonical
  runtime header and retain compatibility with existing native ABI 3 packages.
- Exercise Host API v2 and the HTTP/WebSocket package in runtime CI.

## 0.1.5

- Add `mog --version` with native ABI diagnostics.
- Enforce semantic caret ranges for pre-1.0 packages and require Git tags to
  match package manifest versions.
- Gate releases on runtime and package-manager regressions, validate tag/version
  consistency, and publish SHA-256 checksums.
- Fix package-manager regression tests that depended on one developer's absolute
  checkout path or a hard-coded generator version.
- Stage reference-package manifests beside clean-build native libraries and keep
  native-handle type-safety tests independent of optional external packages.
- Test all foundation package repositories from runtime CI and automate pinned
  GitHub Action and documentation dependency updates.

## 0.1.4

- Implement `charCodeAt`, `charFromCode`, and `slice` in the virtual machine.
- Support the documented `any` type in source package function signatures.
- Resolve local native packages through an adjacent `package.so` library.
- Use the configured release version when evaluating `mog_runtime` requirements.

These changes are required by the 0.1.1 foundation-package releases.
