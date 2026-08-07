# Prediction 2 — size, build, speed

Written **before** the measurements, at 2026-08-05T23:45Z, on pin `collate`
(tree `735a2c2ee2e8`, binary `a01fcb3448c4`). Same rule as Prediction 1: each
row names what falsifies it.

## What I knew when I wrote this

Measured by me, incidentally, while building the refusal census:

- `joints` is **1,764,104 bytes**, one binary, no per-grammar native code.
- Folios on disk: bash 887,376 · c 295,728 · cpp 726,288 · css 71,760 ·
  elixir 246,032. Thirty exist under `.local/standing/`.
- tree-sitter dylibs already compiled on this machine: html 51,752 ·
  toml 51,064 · lua 84,472 · css 151,080 · go 249,160 · c 645,928 ·
  php 1,093,304 · elixir 1,638,432 · haskell 3,885,104 · cpp 5,636,440 ·
  **sql 11,099,608 · verilog 18,281,904**.
- tree-sitter's own summary line on `picorv32.v`: `Parse: 23.40 ms,
  4045 bytes/ms` — about 4 MB/s, excluding process start and dylib load.
- `tree-sitter parse` takes `--edits "<position> <delcount> <text>"` and
  `--json-summary`, so an incremental comparison can be like for like.
- `joints amend <grammar> <file> FROM..TO=TEXT` exists, with `--cold` to
  re-read the whole file per edit *for the comparison* — the flag is already
  the right shape for this measurement.
- The README's claim, unverified here: **252 of 461 declared externals seated
  with zero lines of per-grammar C.**
- `differential.py` had to fetch a hand-written C scanner from each grammar's
  own commit for seven of eleven pins, reproduce a monorepo's directory depth
  for three of them, and **still cannot build yaml**: its scanner does
  `#include _file(YAML_SCHEMA)`, a macro-constructed include no fetcher can
  see, so `tree-sitter parse` on `ci.yml` dies with `fatal error:
  'schema.core.c' file not found`.

| | prediction | falsified by |
|---|---|---|
| Q1 | The folio is smaller than the dylib on **at least 24 of 30**, median ratio **≤ 0.40** | fewer than 24, or median > 0.40 |
| Q2 | **At least one grammar where the folio is bigger.** A claim with no losing row in it has not been measured | every one of the thirty is smaller |
| Q3 | Grammar to usable artifact — `joints mint` against `tree-sitter generate` plus the C compile — joints is **at least 5× faster at the median** | median speedup < 5× |
| Q4 | **Cold parse throughput is a loss, by at least 2× at the median.** The incumbent has had ten years of it and joints's own README says not to reach for it | joints is within 2×, or faster |
| Q5 | Incremental re-parse is a **worse** loss than cold parse — a larger ratio — because tree-sitter's whole design is arranged around it and joints's `amend` is new | the incremental ratio is smaller than the cold ratio |
| Q6 | **Zero of thirty folios need a C toolchain** and at least **20 of 30** tree-sitter grammars need a hand-written external scanner compiled per grammar | any folio needs a compiler, or fewer than 20 grammars ship a scanner |
| Q7 | The 252/461 headline **does not survive being asked per grammar**: fewer than half of the thirty have *every* declared external seated, so a grammar-weighted rate is materially below 54.7% | at least 15 of 30 seat all of theirs |
| Q8 | **My speed instrument flatters joints on its first run**, by counting a cost on one side and not the other — process start, dylib load, folio load, or tree printing | the first numeric run is like-for-like on the first reading |

## Why each

**Q1/Q2.** A dylib is compiled code; a folio is data. That should win almost
everywhere, and a measurement where it wins *everywhere* is more likely to be
measuring two different things than to be a clean sweep. verilog's dylib is
18 MB and verilog's folio will not be, so the median will be dramatic — which
is exactly when to look for the row that goes the other way.

**Q3.** `tree-sitter generate` writes a `parser.c` that can be megabytes, and
then clang has to compile it. Two processes and a C compiler against one
in-process press.

**Q4/Q5.** Honest. The brief says the incumbent is never allowed to win, and on
these two rows I expect it does today. Saying so first is the point.

**Q6.** This is the claim the whole project rests on and it has never had a
number. It is also the one where the measurement is nearly free: count the
scanners on disk.

**Q7.** 252/461 is a token-weighted rate. A grammar with 113 externals all
seated (yaml) and a grammar with 12 seated none (php) both count once in the
denominator that matters to a user, who has one language and not 461 tokens.

**Q8.** The obvious asymmetry: `tree-sitter parse` is a process that starts,
loads a dylib, parses, and prints a tree; `joints parse --quiet` is a process
that starts, loads a folio, parses, and prints nothing. Timing both with a
shell clock measures four things and reports one.

## What I am deliberately not predicting

**Whether an installation axis is a win.** It looks like the largest one
available and that is exactly why the measurement has to be able to say no. The
rule fixed in advance: a size or installation row counts as an improvement only
if it names *what a user must have on their machine* and both sides are priced
for the same outcome — one language parsing, from nothing.
