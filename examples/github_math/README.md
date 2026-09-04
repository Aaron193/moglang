# GitHub Math Import Example

This is a package-managed Kelvra project that imports the public source package at
`github.com/kelvralang/math`.

Run it from the example directory:

```bash
cd examples/github_math
../../build/kelvra run app.kel
```

The command generates an ignored `kelvra.lock` and `.kelvra/install` directory
inside the example so you can inspect the resolved package.

Expected output:

```text
kelvralang/math v0.2.0
50
42
```
