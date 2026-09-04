# Kelvra editor tooling development

Open the `kelvra` repository root in VS Code and select **Kelvra: Extension
Development Host** in Run and Debug. Its pre-launch task configures
`build/tooling-debug`, builds `kelvra-lsp`, opens `examples/` in an isolated
Extension Development Host, and passes the development server path without
changing user settings.

The first configure checks `CMakeCache.txt`. If the checkout moved, it stops and
prints the cached and current source paths. Remove or rename only the reported
tooling build directory and configure again.

Repository tasks provide the normal loop:

- **Kelvra: Install Extension Dependencies** uses the committed lockfile and
  compiles the extension bundle.
- **Kelvra: Configure Tooling Debug Build** creates the isolated debug cache.
- **Kelvra: Build Language Server** rebuilds only `kelvra-lsp`.
- **Kelvra: Run LSP Tests** runs the extension's aggregate LSP test command against
  `build/tooling-debug/kelvra-lsp`.
- **Kelvra: Package Development VSIX** stages the current host's freshly built
  server, creates `build/vscode-kelvra-development.vsix`, and smoke-tests the exact
  package before removing the staging copy.

After changing server source, run the build task and invoke **Kelvra: Restart
Language Server** in the development host. The nested
`tooling/vscode-kelvra/.vscode/launch.json` is an extension-folder-only fallback;
the repository-root launch is the supported workflow because it also builds the
server and opens a representative Kelvra workspace.

The launch environment uses `KELVRA_SERVER_PATH` only for the isolated development
host. Public users should rely on the bundled target server; `kelvra.serverPath`
remains an explicit advanced override.

CI runs manifest, grammar, formatting, import-diagnostic, navigation, protocol
smoke, client unit, and Extension Development Host tests. Protocol fixtures must
remain network-independent unless the test creates its own local registry.

The initial performance budgets for the maintained integration fixture are a
warm p95 below 250 ms for completion and hover, diagnostics published within 2
seconds of a change, and initial workspace indexing below 5 seconds. Release
reports compare these measurements with the previous stable release. Budgets may
be revised only with an explained fixture or product change, not to hide a
regression.
