# Foundation Package Compatibility

| Package | Kind | Mog runtime | ABI | Notes |
| --- | --- | --- | --- | --- |
| encoding, path, json, log, test | source | ^0.1.1 | — | Portable |
| time, random, fs | native | ^0.1.1 | 3 | Linux x86_64/aarch64; macOS arm64 |
| window | native | ^0.1.1 | 3 | Same targets; SDL2 >= 2.0 |

The initial fs scope excludes directory listings, byte buffers, streams, and watchers until a safe byte/collection ABI exists.
