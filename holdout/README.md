# STOP. Nothing in here is a place to look for a defect.

This directory is a **sealed holdout**: twenty tree-sitter grammars with real
source files, pinned to commits, chosen by a rule written down before it ran,
and never diagnosed against. It exists to answer the one question the rest of
this repository structurally cannot ask itself.

Every number in the dossier is measured over the thirty grammars in
`upstream/grammars/`. We tune against those thirty, we fix the walls those
thirty hit, and we report percentages taken on the same thirty. That is
in-sample twice over, and no instrument in the tree can see it. The gap between
this holdout's `trued` and the working corpus's is the only estimate anybody has
of how much of the work generalises.

**A grammar you diagnose against is a grammar that has stopped being held out.**
Not eventually, not a bit — the moment you read *why* one of these failed, the
number it can produce afterwards is a number about a grammar somebody tuned
toward. That is why the seal is a tool and not a promise.

## If you are a lane hunting a wall

You are in the wrong directory. The walls are in `upstream/grammars/`, and
`tool/walls.py`, `tool/standing.py --crooked` and `research/joinery/owners/`
are where the work order lives. Nothing here will help you and looking will
cost the project a measurement it cannot buy back.

## The rules, all four of them

1. **`holdout.py gate` prints aggregate per grammar and nothing finer.** Size,
   built, square, crooked, soft, unaudited, trued, and how much of it the oracle
   could judge. No wall, no state number, no refused terminal, no byte offset,
   no tree. The sealed row type has nowhere to put one — see `Sealed` in
   `tool/holdout.py`, and `holdout.py prove`, which tries to smuggle one through
   and is caught.

2. **Looking deeper costs the grammar, permanently.**

   ```
   python3 tool/holdout.py unseal <grammar> --reason "why this is worth a twentieth"
   ```

   records the unsealing in [`ledger.json`](ledger.json) — who, when, why, and
   how many are left — and **retires that grammar from the holdout into the
   working corpus**. There is no verb that puts one back. The twenty shrinks
   visibly and nobody can quietly spend it.

3. **A defect crosses the seal as a shape, never as a witness.** If the gate
   tells you something is wrong, reproduce it on a working-corpus grammar or on
   an authored construct in `research/joinery/specimen/`, fix it there, and
   never look at the holdout witness again.

4. **Never add a grammar here by hand, and never re-run selection.**
   `holdout.py select` refuses to overwrite an existing manifest, because
   re-rolling a holdout is the one thing a holdout may never do. Selection is
   `research/generalize/SELECTION.md`, and that document was written before it
   ran.

## What is tracked, and what is not

| Path | Tracked | What |
|---|---|---|
| `README.md` | yes | this file — the seal |
| `holdout.toml` | yes | the pins: repo, commit, path, sha256, size, for every grammar and every source file |
| `ledger.json` | yes | every unsealing, and what it cost |
| `eligibility.json` | yes | every roster entry the selection rule looked at, and which condition dropped it |
| `oracle.json` | yes | which copy of each oracle answered, by digest — written by every `gate` run |
| `vendor/` | **no** | the bytes. Gitignored, re-fetchable from the pins with `holdout.py fetch`, hash-checked on the way in. |

The seal is **procedural, and the tool enforces the part a tool can**. The bytes
are not secret and could not usefully be — anyone can fetch them from the pins.
What the tool enforces is that the *gate* cannot hand you a diagnosis, and that
taking one anyway leaves a record that costs a grammar. That is the honest
description of what is and is not guaranteed here, and stating it is better than
implying a stronger seal than exists.

## Provenance is the other half

Without a pin the holdout drifts and a later comparison measures the drift. This
tree has already paid for that lesson: the same script read one grammar at 1,278
crooked in one run and 9,087 in the next off a byte-identical stamp, because
other lanes rebuilt the oracle libraries underneath it. So every grammar and
every source file here carries a repository, a commit, a path, a sha256 and a
size, `holdout.py verify` re-hashes rather than trusting, and every `gate` run
closes by naming which oracle answered.

### A grammar is not one thing on this disk

`tool/attest.py` seats an oracle on its **sources**, and most grammars exist as
several source trees at once — css's two differ in 62.3% of their bytes. A path
is not a version, so the gate records the **digest**: `oracle.json` carries, per
row, the oracle's `src/` tree digest, its home, and how many distinct copies of
it exist here. The gate prints the same in its footer and flags `FORKED` rows.

For this holdout the multiplicity is **entirely on the corpus comparator**:
all 20 holdout grammars have exactly one oracle source tree, because theirs is
generated from `vendor/`, which no other lane writes to. 14 of the 27 measured
corpus rows have two or more.

`holdout.py forked <grammar>` reads one file against every copy in turn, each in
its own seat. On this disk exactly one copy per grammar can answer — the rest
are trees with no generated `parser.c` — so no measured number here depends on
which was found. That verb stands `differential.oracle_build` down while it
runs, and **that is the whole of its correctness**: left in, it overwrites each
copy's `grammar.json` with the one it was handed, and then reports that the
copies agree. They do, after being made identical. Its first version did exactly
that on fourteen grammars.

`told()` digests each row's oracle at the instant that row is read and again at
the foot of the run; if a sibling rebuilds something in between, the gate says
`MOVED MID-RUN` and names the rows instead of attributing a two-parser
aggregate to one identity.

## The dossier

`research/generalize/` — the predictions written before either tier ran, the
selection rule written before selection, and the results.
