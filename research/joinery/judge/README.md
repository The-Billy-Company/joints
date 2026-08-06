# judge — the oracle was never silent on verilog; the blind rule was

Verilog is the corpus's largest damage row at **62,180 bytes**, and the
[stretch lane](../stretch/README.md) had just established that its entire
un-leafed population — **4,644 of 4,644 bytes, `veiled`** — is priced at zero
*because the oracle declines*, not because it agrees. Three lanes were
optimising a row that nothing was scoring.

The premise handed to this lane was that tree-sitter fails on verilog too, so
the row needs a second judge before it can be scored, and that verilog is
therefore the corpus's strongest case for beating tree-sitter.

**Both halves of that premise are false, and the measurement is not close.**

Tree-sitter's verilog grammar fails to *close* the top-level parse and wraps
the file in one `ERROR` spanning all 94,657 bytes. `plumb.hurt()` taints by
**ERROR ancestry**, so every byte in the file inherits that single node's
verdict and the blind rule refuses all of them. Underneath that root it built
**48,883 nodes and 17,290 leaves**, and its 333 `ERROR` nodes *minus the root*
swallow only 12,526 bytes — 13.2% of the file. The root `ERROR` is a label on a
file it parsed, not a failure to parse it.

Asked the nearer question — *what is the **innermost** node covering this byte?*
— the oracle answers on **4,373 of the 4,644 (94.2%)** with a named construct
it built and left un-leafed, exactly as we did. On **3,430** of those both
trees name that construct with the identical string. That is not silence; it is
agreement, and it was there the whole time.

**The row re-prices to `slack` 4,373 by verdict and a bound of 271** — 0.29% of
the file, all of it whitespace, on which two independent SystemVerilog parsers
also stand no token. `warp` stays **0**, `owed` stays **62,180**, but now for a
reason instead of a default.

## And we do not beat tree-sitter on verilog

Against Verible's lexing of the same file (74,194 bytes carry a non-blank
token):

| | leaf bytes | of token bytes | nodes | leaves |
|---|---:|---:|---:|---:|
| outliner | 44,911 | **60.5%** | 23,497 | 9,394 |
| tree-sitter | 73,357 | **98.8%** | 48,883 | 17,290 |

**Bytes we leaf and tree-sitter does not: 0.** Our leaf set is a strict subset
of theirs across the entire file. There is no byte of verilog we lex and they
do not, so the claim this lane was sent to establish cannot be made, and the
opposite one can.

## The judges

Neither is a dependency. The load-bearing verdict is tree-sitter's own tree
read by innermost cover and needs no second parser; both of these corroborate
the two things tree-sitter cannot certify about itself.

| judge | what it settles | licence | cost |
|---|---|---|---|
| [Verible](https://github.com/chipsalliance/verible) `verible-verilog-syntax` — Google/CHIPS Alliance; `--export_json --printrawtokens` emits every token with `start`/`end` **byte offsets** ([token object spec](https://chipsalliance.github.io/verible/verilog_syntax.html)) | whether a *token* hides in a byte both trees left bare. Lexes the text **as written**, no preprocessing — the same thing both trees do | Apache-2.0 | prebuilt macOS binary, 7.9 MB, no build |
| [slang](https://github.com/MikePopoloski/slang) via [`pyslang`](https://pypi.org/project/pyslang/) — the most compliant open SystemVerilog frontend on the [chipsalliance `sv-tests`](https://github.com/chipsalliance/sv-tests) suite; drivable straight from Python (`syntax.SyntaxTree.fromFile`) | whether the corpus file is **valid verilog** at all | MIT | prebuilt wheel, `pip install pyslang` |

slang **cannot** price a byte and is not asked to: it runs the preprocessor, so
an inactive `` `ifdef `` branch and a macro body leave no token behind. It
under-covers by construction and would free bytes that are code in another
configuration. Verible over-covers in the safe direction. They disagree with
each other on purpose, which is why neither is asked to price a byte alone.

Two more were weighed and not seated. **[Icarus Verilog](https://github.com/steveicarus/iverilog)**
(GPL-2.0) is a simulator; its parse tree is an elaboration artifact reachable
only through `-tvhdl`/VVP output, so mapping it to byte offsets is a project in
itself. **[Surelog/UHDM](https://github.com/chipsalliance/Surelog)** (Apache-2.0)
emits a proper UHDM database with source ranges, but it is a heavy CMake build
and its model is *post-elaboration*, which has slang's preprocessing problem
without slang's five-second install.

## Why no second oracle was seated in `attest`

`attest.rule()` digests the transitive closure of what the identity rule reads,
so a seated judge must be pinned, digested, and reproducible on every arm. That
weight buys nothing here: the verdict that moved the row came from the oracle
already seated, read by a rule that does not throw away 94% of its answer.
Verible and slang settle two yes/no facts that do not vary with a tree — *is
the file valid*, *is a token hiding here* — and re-checking them on every board
would be paying an identity cost for a constant.

**If that changes, the thing to seat is Verible**, not slang: byte offsets,
no preprocessing, a single static binary with a release digest
(`66e9c3c6…d422d27` for `v0.0-4121-gc2ec3416` macOS), and a JSON contract
stable enough that Google ships a Python driver for it.

## Files

| file | what it is |
|---|---|
| [`judge.py`](judge.py) | the verdict, the corroboration, and `--coverage` (who leafs more of the file, us or them) |
| [`RESULT-1-adjudicator.md`](RESULT-1-adjudicator.md) | how tree-sitter actually fails, the survey, the re-pricing, the coverage loss, and what I trust least |

```text
eval "$(python3 tool/pin.py arm <name>)"                     # or every row lies
python3 tool/pin.py oracle <name>                            # mint the seat first
python3 research/joinery/judge/judge.py                      # the re-priced row
python3 research/joinery/judge/judge.py --coverage           # the coverage loss
```

`judge.py` runs without either external judge and says so, printing the verdict
marked uncorroborated. To put them on disk (both land under `.local/`, are
never imported by the product, and nothing in the repo depends on them):

```bash
mkdir -p .local/judgelane/judge && cd .local/judgelane/judge
curl -sSLO https://github.com/chipsalliance/verible/releases/download/v0.0-4121-gc2ec3416/verible-v0.0-4121-gc2ec3416-macOS.tar.gz
shasum -a 256 verible-v0.0-4121-gc2ec3416-macOS.tar.gz   # 66e9c3c65206f2d3faf3ae13c68d7611dc5e70f0061732fb4513cad90d422d27
tar xzf verible-v0.0-4121-gc2ec3416-macOS.tar.gz
cd - && python3 -m venv .local/judgelane/slangvenv && .local/judgelane/slangvenv/bin/pip install pyslang
```

Every number here was read on arm `judgelane`, binary from tree `1d7a512f8`,
repo `f7ba40004+145`, oracle `eacad4bfc` / tree-sitter 0.26.11, verible
`v0.0-4121-gc2ec3416`, pyslang 11.0.0.
