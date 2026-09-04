# Kelvra Language Support

The official VS Code extension for Kelvra provides syntax highlighting, snippets,
completion, hover information, diagnostics, go to definition, formatting, rename,
and workspace symbols through `kelvra-lsp`.

## Installation

Platform-specific Marketplace packages include a tested language server under
`runtime/<platform>/`. When using a source checkout or a generic development VSIX,
install Kelvra so `kelvra-lsp` is on `PATH`, build the server in a workspace build
directory, or set the advanced `kelvra.serverPath` setting.

Discovery is deterministic: an explicit setting, bundled server, installed Kelvra
runtime, the active project's build, every workspace folder's build, then `PATH`.
Relative settings are resolved in the setting's workspace folder. An invalid
explicit setting is reported and requires you to choose whether to fall back.

## Commands and troubleshooting

- **Kelvra: Show Language Server Status** shows the executable, working directory,
  state, server version, and tooling protocol.
- **Kelvra: Restart Language Server** performs a clean restart.
- **Kelvra: Select Language Server** validates and saves an executable override.
- **Kelvra: Open Language Server Log** shows every discovery candidate and rejection.
- **Kelvra: Install Project Dependencies** asks for consent, reports progress, and
  exposes package installation errors from the server.

If startup fails, open the language server log and check that the selected file is
a regular executable for your OS. A relocated CMake build has an invalid cached
source path; remove that dedicated build directory, configure it again from the
current checkout, and rebuild `kelvra-lsp`. Automatic crash restarts are bounded, so
repeated crashes remain visible rather than looping indefinitely.

## Development

From the Kelvra repository root, install dependencies and compile the client with
`npm --prefix tooling/vscode-kelvra ci && npm --prefix tooling/vscode-kelvra run compile`, build `kelvra-lsp`, and use the repository's
**Kelvra: Extension Development Host** launch configuration. It uses an isolated Extension
Development Host and a development-only `KELVRA_SERVER_PATH`; it never changes user
settings. Run `npm --prefix tooling/vscode-kelvra run check` for unit checks and
`npm --prefix tooling/vscode-kelvra run test:extension` for the Extension Host suite.

## Privacy and network behavior

The extension does not collect telemetry and does not download a server. Normal
language analysis is local. Project dependency installation only runs after an
explicit command and confirmation; the server may then contact registries declared
by Kelvra configuration and write lock/install data in the project.

Report problems at <https://github.com/kelvralang/kelvra/issues> and include the output
from **Kelvra: Open Language Server Log**.
