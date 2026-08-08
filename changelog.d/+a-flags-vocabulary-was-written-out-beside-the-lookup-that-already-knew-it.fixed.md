Two flags take an enum's members by name, and both already resolved them with
`std.meta.stringToEnum` — so both already accepted exactly the right set. The
*spellings* were then written out by hand next to that lookup, and the two halves
had drifted in opposite directions:

- `--mend` carried `"none, keep, fell or relent"` as a string literal in its own
  refusal, and a third copy inside `main.zig`'s usage block. A policy added to
  `quire.Mend` would have been **accepted by a CLI that denied it existed**.
- `--policy` had the mirrored half: `"joints: no such re-mint policy: X"`. It
  refused correctly and **never said what it would have taken**.

The lists are the enums now. `intake.spellings(E, dflt)` renders a vocabulary two
ways from `@typeInfo` — `fell (default), none, keep, relent` for a usage line,
`none, keep, fell or relent` for a refusal — and `intake.choice` is the one door a
`--flag=member` goes through, in the file that exists because five verbs once read
a file five ways.

**Byte-identical where it was already right.** `--mend`'s usage line and its
refusal both render exactly the strings they hardcoded. `--policy` gains the
vocabulary it never printed, and `prove (default)` in the usage line where the
default had been unmarked.

The defaults moved to `intake.default` for the same reason. `main.zig` named
`fell` as a word inside a sentence while `parse.zig` applied `.fell` as a value:
two copies, free to disagree, with nothing to say which one was the behaviour.
They are one comptime-checked member each now.

**Measured, not asserted.** A `zzprobe` member added to `quire.Mend` reaches the
usage block *and* the refusal with no edit to `main.zig`, `parse.zig`, or
`intake.zig` — and the exhaustive `switch` in `gather.zig` refuses to compile
until the policy is actually implemented, so the freed path cannot be used to ship
a name with nothing behind it. The pinned property is over a local three-member
enum rather than `Mend`, because asserting the live members would pin today's
policies and fail the day one is legitimately added, which is the exact change
this makes free.

What stays hand-written is the per-policy prose in `parse.zig`'s header — `fell`
closes the stack, `keep` drops the token, `relent` keeps once then fells. That is
not a list, and deriving it would only relocate it.
