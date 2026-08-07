# Prediction 1 — what a top-level orphan is actually a measure of

Written before any corpus-wide measurement was taken, after reading
`gather.zig` and before running anything but the baseline board of
2026-08-05 and a census of `Maps.kt`'s roots and gaps.

## The claim I am about to test

The brief hands me 19,705 orphan bytes of KDoc and asks which wall demoted
them. Reading `gather.zig` I think the question has a sharper form, and that
the answer is not a property of KDoc, of the comment hand, or of anything
standing near a comment.

Three facts out of the source, each citable:

1. **A top-level extra can only ever be claimed by `crown`.** Rule 2 of the
   extras contract (`gather.zig` header) is that a reduction takes the extras
   lying *between* its first and last symbol — the leads of its second symbol
   onwards. An extra sitting before a top-level declaration's first token is
   that declaration's *first* lead, so no reduction of it can own the comment.
   And the start production is never reduced: `close` says so outright, accept
   fires in its place. So the file's top-level extras reach the end of the
   parse unclaimed by construction, in every grammar, and Rule 5 (`crown`) is
   the single operation that adopts them.

2. **`crown` is gated on the whole file having mended zero times.**

   ```zig
   if (won.ok and x.mends == 0) try x.crown(won.top, @intCast(bytes.len));
   ```

   Not "this segment mended zero times" — the file. One mend at byte 270 is
   enough to keep `crown` from firing over a comment at byte 30,000.

3. **What runs instead is `unwind`, which carries the unclaimed leads straight
   into `roots`**: `try x.carry(&x.roots, x.borne.at(x.lead, x.leads))`. A
   lead nobody claimed becomes a top-level root of its own. Which is exactly
   the shape `standing.py` scores as `orphan` when the leaf is a declared
   extra.

So my claim is that `orphan` is not a graded measure of how badly a file was
read. It is a **one-bit gate wearing a byte count**: zero mends and the file's
top-level extras are the root's children, one mend anywhere and every one of
them is a root.

## P1a — orphan is binary in the mends, corpus-wide

For every (grammar, file) pair in the corpus: `orphan > 0` **iff** the parse
mended at least once and the file has at least one top-level extra.

**Falsifier:** a file with `mends == 0` and `orphan > 0`, or a file with
`mends > 0`, top-level comments outside every declaration, and `orphan == 0`.
Either one means something other than the crown gate is deciding, and the
whole reframe is wrong.

**Measurement:** `joints parse` per corpus file for the mend count, joined
against `standing.py --json`'s per-file orphan.

## P1b — Kotlin's 19,705 is therefore all-or-nothing, and no string fix alone moves it

If P1a holds, then the number cannot be reduced. `Maps.kt` mends 142 times;
taking 141 of them away leaves `crown` refusing exactly as hard, and the
orphan bucket unchanged at 19,705. The only edit that moves the number is one
that takes `Maps.kt` to **zero** mends.

This is the prediction I most expect to be told I am wrong about, because it
means the brief's framing — "find the wall that demotes the KDoc" — has no
single referent. Every wall in the file is that wall, jointly.

**Falsifier:** any change that lowers Kotlin's mend count without reaching
zero and moves `orphan` off 19,705 by even one byte.

## P1c — the string family is necessary and not sufficient

`Maps.kt` holds 90 `"` characters, 45 string literals, and — this is the trap
the brief already named, so I checked before predicting — **zero** triple
quotes, **zero** `$` interpolation, **zero** backslash escapes. The corpus
does not exercise the constructs that make kotlin's strings a `fence`.

Kotlin declares ten externals. Two are seated (`multiline_comment` on the
`kotlin_block` marrow vein, `_automatic_semicolon` on the kotlin caesura
tongue). Eight are blind, five of them the string family. I predict the
non-space gaps left by mends are *mostly* but **not entirely** string, and
that at least `_import_dot` fires too — the `.` in `import kotlin.contracts.*`
sits in a gap in the census I already have.

So: a kotlin string fence removes most mends, `orphan` does not move, and the
board moves in `rubble`/`spoil` instead.

**Falsifier:** every non-space gap in `Maps.kt` is attributable to the string
family. Then the string fence alone reaches zero mends, `orphan` collapses,
P1b is confirmed by the same stroke, and P1c is the failure.

## P1d — what I nearly concluded and am recording so I can be caught

Before reading `crown` I had written down that the mends "reset the stack and
promote the intermediate nodes", which is true but reads as though the damage
is local to each mend — as though 142 mends orphan the comments *near* them.
That is wrong in a way that would have produced a plausible, flattering
report: I would have fixed the strings, watched most mends vanish, and claimed
a proportional share of 19,705 that I never earned. The measurement that
catches it is P1b's, and it is the one I am running next.
