# SQLite Vendor Source

This directory stores the vendored SQLite amalgamation source used by `package:sqlite3`.

Why it exists:
- The default `sqlite3` hook downloads prebuilt binaries from GitHub, which is unreliable in the current environment.
- Loading Android system SQLite through `source: system` still failed at runtime on the target device.
- To make builds deterministic, the project now compiles SQLite locally from `sqlite3.c`.

Important files:
- `sqlite3.c`: official SQLite amalgamation source used by the build hook
- `sqlite-amalgamation-3500200.zip`: downloaded upstream archive for traceability

Hook configuration lives in:
- `pubspec.yaml`
