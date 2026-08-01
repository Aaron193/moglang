# Foundation Package Compatibility

| Package | Kind | Mog runtime | ABI | Notes |
| --- | --- | --- | --- | --- |
| encoding, json, log, math, path, test | source | ^0.1.4 | — | Portable |
| fs, random, time | native | ^0.1.4 | 3 | Linux x86_64/aarch64; macOS arm64 |
| window | native | ^0.1.4 | 3 | Same targets; SDL2 >= 2.0 |

Mog 0.1.4 is the first release whose default source build embeds the correct
runtime version used by `mog_runtime` checks. Package CI tests that release as
the compatibility floor and current runtime `main` for forward compatibility.

The initial fs scope excludes directory listings, byte buffers, streams, and watchers until a safe byte/collection ABI exists.
