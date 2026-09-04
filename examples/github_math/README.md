# GitHub Math Import Example

This is a package-managed Kelvra project that imports the public source package at
`github.com/kelvralang/math`.

Run it from the repository root:

```bash
./scripts/run_github_math_example.sh
```

To physically inspect the generated `kelvra.lock` and `.kelvra/install` directory
inside this example, run:

```bash
./scripts/run_github_math_example.sh --in-place
```

Expected output:

```text
kelvralang/math v0.1.0
50
42
```
