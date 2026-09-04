# Changelog

## 0.2.0

- Rebrand the extension, language mode, settings, bundled server, source-file
  association, documentation, and artwork from Mog to Kelvra.
- Change the supported source extension from `.mog` to `.kel`.

## 0.1.17

- Restore the existing Marketplace display name, `Kelvra Developer Tools`, so
  publishing is not rejected by the similar-name policy.

## 0.1.16

- Verify bundled-server containment with platform-aware path semantics in the
  Windows Extension Host test.

## 0.1.15

- Preserve the Windows runner toolcache PATH inside MSYS2 so Node and npm are
  available during VSIX packaging and Extension Host tests.

## 0.1.14

- Compare the project identity rather than platform-specific MSYS and native
  Windows absolute path spellings in protocol error verification.

## 0.1.13

- Keep the Windows language server's standard streams in binary mode so its
  LSP headers retain the required CRLF framing.

## 0.1.12

- Preserve bundled server executability in installed-artifact tests, exercise
  the packaged server directly, and avoid blocking activation on recovery UI.
- Normalize Windows file URI keys in rename workspace edits and make
  multi-target Marketplace publication safe to retry.

## 0.1.11

- Pin Extension Host release tests to the supported VS Code baseline and
  normalize equivalent Windows file URI spellings in navigation checks.

## 0.1.10

- Correct Windows file-URI emission and make cross-platform release checks
  bounded and reliable.

## 0.1.9

- Normalize MSYS temporary-file paths during Windows import-diagnostic release
  verification.

## 0.1.8

- Fix Windows file-URI comparison in import diagnostic release verification.

## 0.1.7

- Correct Windows LSP test framing during cross-platform release validation.

## 0.1.6

- Fix macOS VS Code executable detection and supply Python for Windows LSP
  release verification.

## 0.1.5

- Skip optional window-package navigation assertions when that platform's
  bundled fixture is not present.

## 0.1.4

- Make bundled native-package discovery portable across module filename
  suffixes and compile the language server with GCC as well as Clang.

## 0.1.3

- Fix native package resolution when an optional library path is absent, so
  platform-specific bundled package libraries load correctly.

## 0.1.2

- Fix macOS verification of imported-file diagnostic locations when the system
  resolves `/var` through `/private/var`.

## 0.1.1

- Ship platform-specific extension packages with a tested bundled Kelvra language
  server.
- Add reliable server discovery, startup diagnostics, compatibility checks, and
  workspace-aware recovery commands.

## 0.1.0

- Add completion, navigation, diagnostics, formatting, hover, and rename through
  the Kelvra language server.
- Add deterministic bundled/runtime/workspace/PATH server discovery.
- Add multi-root lifecycle management, compatibility checks, status UI, bounded
  crash recovery, explicit dependency installation, and troubleshooting commands.
