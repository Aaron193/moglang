# GitHub Math Import Example

This is a package-managed Mog project that imports the public source package at
`github.com/moglang/math`.

Run it from the repository root:

```bash
./scripts/run_github_math_example.sh
```

To physically inspect the generated `mog.lock` and `.mog/install` directory
inside this example, run:

```bash
./scripts/run_github_math_example.sh --in-place
```

Expected output:

```text
moglang/math v0.1.0
50
42
```
