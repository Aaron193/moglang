# Kelvra Package Policy

Kelvra keeps its language-provided library deliberately small: primitive values, core collections, conversions, errors, and basic math/time helpers remain runtime features. Reusable libraries are independently versioned packages.

## Names and ownership

- `std/...` is reserved for language-owned modules. It is not a publishing namespace.
- `github.com/kelvralang/...` is the canonical module namespace for official external packages. Shared code must use that path; `import_name` is only a local convenience alias.
- Public packages require a stable `package.api.kel`, semantic version, license, changelog, compatibility declaration, runnable README example, and tests.

## Native boundary

Source packages are preferred. Native packages are limited to platform APIs, secure entropy, or functionality that cannot safely be represented in source. They must use CMake, declare targets and system dependencies, and fit ABI v3: primitives, strings, optional values, and opaque handles. This foundation release does not expand that ABI.
