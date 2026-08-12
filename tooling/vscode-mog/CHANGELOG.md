# Changelog

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

- Ship platform-specific extension packages with a tested bundled Mog language
  server.
- Add reliable server discovery, startup diagnostics, compatibility checks, and
  workspace-aware recovery commands.

## 0.1.0

- Add completion, navigation, diagnostics, formatting, hover, and rename through
  the Mog language server.
- Add deterministic bundled/runtime/workspace/PATH server discovery.
- Add multi-root lifecycle management, compatibility checks, status UI, bounded
  crash recovery, explicit dependency installation, and troubleshooting commands.
