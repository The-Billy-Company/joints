`sole.py` has been failing for a while, and it was right to. It found **nine
second copies** of rules that already have an owner, across three instruments,
and the whole point of that gate is that this exact shape cost 28 points of byte
coverage the last time nobody fixed it. All nine are gone; the gate reads
`10 rules, one copy each` and exits 0, and `--probe` still catches 4/4 of the
shapes it claims to.

Three of them were `specimen.py` reading verdicts for itself: its own `ROOTS` and
`MENDED` regexes, its own `parse --ranges --all`, and its own `parse --quiet`.
`stamp.ask` is the door for exactly that - its docstring says four instruments
each wrote their own reader and three of them got a different answer out of the
same bytes - so `forest` and `stop` go through it now and the two regexes are
deleted. **Every measured line of `specimen run` is byte-identical**, including
the yaml row whose whole job is to prove a refusal doesn't read as a clean parse
(`roots 1 - REFUSED: yaml has no lexable terminal at all`, same before and
after). One line is new, and it is the reason to do it this way: `generation: 21
artifact(s) over 240 read(s), one generation each`. Going through `ask` means the
provenance ledger sees those reads, so specimen can now say every row was
measured against what the tree holds now. It could not say that before.

Three were the oracle, and one of them wasn't fixable by calling the owner:
`collate` publishes generate and parse latencies as a table, so it can't call
`oracle_full` - the owner's exchange folds in a digest and a copy that a
cold-build measurement has to exclude. What it actually needed was never the
answer, it was the argv. So `differential` hands one out now (`oracle_argv`,
`builder_argv`), `oracle_full` and `oracle_build` are defined in terms of them,
and `collate` times the owner's command instead of its own spelling of it. A flag
added there reaches the measurement too, which is the part a `# sole:` waiver
would not have bought. Both argvs are asserted identical to the lists they
replaced.

`collate`'s third copy was its own blank-stdout check, and that one taught me
something: it cannot call `oracle_full`, because it cross-checks the damage in
the tree against the exit status and an exception carries no status. So the thing
to share was the *rule*, not the wrapper - `d.refused(got)` says why no tree came
back, or `""`, and `oracle_full` is now that predicate plus a raise. **Exit 1 is
not a refusal**: it means the file has an `ERROR` in it, which is an answer, and
that is the distinction both readers now get from one place. Checked on all four
arms including the two that must return `""`. The refusal text is also uncapped
now, and that is not cosmetic - the sentence telling you which commit's external
scanner to fetch is 116 characters, so the old `[:90]` cut it mid-instruction.

The last three were `attest`, and fixing them turned up two more copies **inside
the owner**: the rule for which `#include` belongs to a grammar and which is the
runtime's own was spelled three times, twice in `differential` itself. It is
`d.includes` once now, used by the upstream fetch, the containment check, and
attest's digest closure. Proven over the populated sandbox rather than argued:
118 C/H files, 28 includes kept and 59 runtime headers skipped - both arms
exercised - and **0 disagreements** with the implementation it replaced. Same for
`d.rooted`, the inverse of `oracle_root` that `attest` had been spelling itself:
23 real homes plus one outside `lang/`, all 3 monorepo-deep ones included, 0
disagreements. `differential sandbox` still reports every include resolving
inside its own grammar.

Two honest notes. `specimen`'s forest used to raise on a timeout and now comes
back empty, which surfaces as claims failing rather than as a traceback - louder
in the right direction, but different. And the gate's remaining blind spots have
not moved: it still cannot witness the tree reader, and its corpus is still
`tool/*.py`, so the 99 `.zig` files under `src/` are somewhere it has never
looked. Nine were in the half it can see.
