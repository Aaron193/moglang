---
name: Kelvra tooling release checklist
about: Track a reproducible VS Code extension release
title: "Release vscode/vX.Y.Z"
labels: release, tooling
---

- [ ] Stable or pre-release channel selected
- [ ] Extension manifest and lockfile root versions equal the proposed tag
- [ ] Extension changelog contains the version and compatibility notes
- [ ] Runtime/server/tooling-protocol versions recorded
- [ ] Pull-request editor and LSP gates pass
- [ ] Linux x64, macOS ARM64, and Windows x64 VSIX jobs pass
- [ ] VSIX file lists and native dependency reports reviewed
- [ ] Protected `vscode-marketplace` environment approval recorded
- [ ] Marketplace version and target availability verified
- [ ] GitHub assets and `SHA256SUMS` verified
- [ ] Clean-profile completion, hover, diagnostics, navigation, formatting, and rename smoke completed
- [ ] Upgrade/rollback notes and known issues published
