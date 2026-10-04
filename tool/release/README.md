# Release artifacts

These scripts build the experimental Python and Rust source interfaces and the
separate native library they require. Run with Python 3.12 or newer, uv,
Zig 0.16.0, and Rust 1.85.0 installed by rustup. Clone irregex beside joints at
`508ad3158efc8346469427e18276f01790c17229`. The source checkouts must be clean.
No command silently overwrites an existing artifact receipt or native archive.

```sh
python3 tool/release/artifacts.py native --version 0.1.0 \
  --target macos-arm64 --output dist/native
python3 tool/release/artifacts.py packages --version 0.1.0 \
  --native dist/native/joints-0.1.0-macos-arm64.tar.gz --output dist
python3 tool/release/artifacts.py verify --version 0.1.0 --packages dist \
  --native dist/native/joints-0.1.0-macos-arm64.tar.gz --python python3.12
python3 -O -m unittest discover -s tool/release -p 'test_*.py'
```

Linux uses `linux-x86_64`; macOS uses `macos-arm64`. Each native archive is
built and tested on its named host. Its `joints-VERSION-TARGET/` root contains
the CLI, shared and static libraries, C header, committed JSON grammar fixture,
license files, and a manifest with artifact hashes, compiler version, exact Git
commits, and source ledgers. Archive timestamps are normalized. The manifest
records reproducible inputs; it does not promise reproducible compiler output.

The `packages` command builds one portable wheel and sdist, verifies their
metadata, and packages Cargo with the native archive. It writes exact file
hashes and source identity to `dist/packages.json`. Verification installs the
wheel in a fresh Python 3.12 environment, builds and installs the sdist in
another environment, and tests an extracted Cargo archive using Rust 1.85.0.
The installed Python package must strictly parse, query original Unicode
bytes, refuse malformed input, and parse again after refusal. The Rust archive
runs its native integration tests and ownership and thread compile-fail docs.
Installed checks run outside the source checkout; the same matching native
artifact supplies both interfaces.

Before publication, `probe --version VERSION --packages dist` checks both
public registries. It prints JSON states `pypi` and `crates`, each `present` or
`absent`. Only an explicit HTTP 404 means absent. A present version must list
the exact expected files, index checksums, and downloaded bytes, and must not
be yanked. A version collision or a registry failure stops the release.

`publish-crate --version VERSION --packages dist --native ARCHIVE` repackages
the clean source with Cargo, verifies it against the tested crate checksum,
then invokes ordinary `cargo publish --locked` with the same native library.
Credentials come from Cargo's environment; the script does not print them.
The workflow invokes this command only after all build and authorization gates.

After both indexes publish, `registry --version VERSION --packages dist
--native ARCHIVE --python python3.12` fetches the actual public index artifacts,
compares their hashes to the tested files, and repeats installed verification.
It fails if a version is absent, an index does not answer, or bytes differ.
Python wheels remain portable interfaces requiring a separately supplied
native library; there are no bundled platform wheels in this release.

`checksums --packages dist --native-directory dist/native` validates both native
archives and their source identity against the portable packages, then writes
`dist/SHA256SUMS`. Entries use the basenames attached to the GitHub release.
Building the portable packages uses the source commit's timestamp for Python
archive timestamps, allowing an identical retry to resolve the same bytes.
