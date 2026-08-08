The freshness stamp counted a `README.md` under `src/` as a source newer than
the binary, so writing a paragraph of prose made every board print `STALE -
rebuild before believing this`. Markdown is not compiled by anything, so the
edit could not have moved the binary no matter what it said.

`builds()` already made this exact argument for `*_test.zig` - a warning that
fires when nothing that could move the binary has moved is how a warning teaches
people to ignore it - and markdown is the same case, one step further from the
build. It and `.DS_Store` join the exclusion. It stays a denylist of things that
provably cannot compile rather than an allowlist of `.zig`, so a data file added
under `src/` and pulled in with `@embedFile` still counts; all seven stamp
conditions, `STALE` among them, still fire when they should.
