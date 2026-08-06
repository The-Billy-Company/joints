# Prediction 1 — why the gain is 1x

Written **before any measurement**, 2026-08-06T00:20Z, from reading
`src/kernel/quire/{gather,bough,graft}.zig` and `src/kernel/weave/weave.zig`
only. Each row names what falsifies it.

The finding I am acting on: `research/collate/RESULT-2-cost.md` measures
outliner's median keystroke gain over re-opening the file at **1x on 17 of 29
grammars**, and php at **65x**. php is the innocent control.

## What I knew when I wrote this

Read out of the source, not measured:

- Reuse has **two independent halves** and the report prints both. The prefix
  half is a resume onto a kept stack snapshot (`Bough.Ring`, taken every
  `stride = 32` tokens); the suffix half is lifting finished subtrees out of the
  old tree (`Graft.stoop` → `absorb .lifted`). `Cost.read` charges only what
  this run moved over; `Cost.stood` says where it stood up.
- `graft.stoop` opens with **`if (q.roots.len != 1) return gr.chain.items;`** —
  an empty candidate chain. A previous parse that mended carries a forest, so
  **a mended file gets zero lifts, by construction, at every offset.**
- The resume is gated on `gr.seamed(ring.at)`: the ring's byte offset must be a
  start of the old tiling. A mend turns the bytes it stepped over into one hole
  leaf, so token boundaries inside a hole stop being seams.
- `weave.amend` only offers a graft at all when `old != null and w.spun`. A
  parse that clears `spun` (`unspun = off | seam | win`) drops its whole tiling,
  so the **next** edit runs with no graft — cold, both halves.
- `torn` is now dead: it is set false in two places and true in none, so the
  per-limb-trail repair really did land and `spun == aligned`.
- `alight` gives itself **`tries = 4`** rings and then declines.
- php seats **0 of 12** declared externals (Result 2) and is the grammar whose
  *tree* is worst (25,338 misread bytes, Result 1). So whatever php has, it is
  not "a better lexer" and it is not "a more correct tree".

## The predictions

| | prediction | falsified by |
|---|---|---|
| D1 | The 1x is **both halves failing at once**, not one. A grammar at gain 1x will show `lifts = 0` **and** `stood = 0` on the median edit | either half working on a 1x grammar — `lifts > 0`, or `stood > 0` with `read` materially under the file's token count |
| D2 | The single fact that separates php from the 17 is that **php's corpus parse mends zero times and yields one root**, and theirs do not. Gain correlates with `mends == 0` better than with file size, grammar size, or externals seated | php mends, or any grammar at gain 1x parses its file to a single root with no mends, or a clean-parsing grammar sits at 1x |
| D3 | Therefore this is **a policy, not a property of php.** The gating code says "clean" nowhere on purpose — `roots.len != 1` and `seamed` are both stand-ins for "the old parse was clean", and neither is load-bearing for soundness in the multi-root case | the multi-root refusal in `stoop` turns out to be soundness-critical rather than a conservatism, i.e. a lift over a forest cannot be made safe by a local test |
| D4 | **swift is a mended grammar** — its 30,740 us/key is the whole file being re-read every keystroke because its own previous parse was a forest. So a policy that lifts over a forest moves swift, and it is not a median-only change | swift parses `Chunked.swift` cleanly and is slow for some other reason |
| D5 | At least **12 of the 17** will be mended, so the ceiling of a forest-aware policy is most of the 17 rather than a handful | fewer than 12 of the 17 mend |
| D6 | The **prefix** half will turn out to be in better shape than the suffix half: on a clean file `stood > 0` will hold at nearly every edit, because every token boundary is a seam while a parse runs clean | `stood = 0` on most edits of a clean file too |
| D7 | php's 65x is **not** explained by php's parse dying early and doing little work. Its `read` per edit will be a small fraction of its cold `read`, with the tree still covering the file | php's warm rows are cheap because the parse truncates near the resume, i.e. cold `read` is itself tiny relative to 67,845 bytes |
| D8 | **My own instrument will flatter the change.** The first number I get for a policy win will be measuring something other than what I changed — most likely a run where the *old* row was paying two cold parses per edit (`spun` cleared, then no graft) and the new row pays one, which halves the time without any reuse happening | the first policy measurement is like-for-like on the first reading |

## Why each

**D1/D6.** The arithmetic is the argument. If the prefix worked and only the
suffix failed, an edit at the middle of the file would re-read half of it and the
gain would be about 2x — and `html` is reported at exactly 2x, which is what one
working half looks like. A gain of **1x** is too cheap to be one half; it has to
be both, or it has to be the graft never being offered at all.

**D2/D5.** Three separate gates in three files all key on properties only a
clean parse has (`roots.len == 1`, a seam where the ring stands, a composable
head). Nothing coordinates them, which is exactly the shape of an invariant
nobody wrote down: *reuse assumes the old parse succeeded*. The corpus is 73%
standing, so most files are not clean, so most files get no reuse. php would then
be innocent for the dullest possible reason — it is one of the few big files that
parses to one root — and that is a policy, not a gift.

**D3.** The soundness argument in `graft.zig`'s header is about a **node**, not
about a tree: a subtree is liftable when nothing outside it can still name it,
and the number of roots the old parse ended with has no bearing on that. The
descent in `stoop` starts at `roots[0]` because it is written as a walk down from
*the* root; over a forest it needs to pick the root containing the offset. That
is a lookup, not a proof obligation.

**D4.** This is the row that matters. A change that moves the median and not
swift is worth less than a plain statement that the ceiling is low, so I am
predicting swift's membership out loud in order to be caught if it is wrong.

**D7.** The trap this whole result could be. A parse that gives up 300 bytes past
the resume point is fast and worthless, and it would show up as a spectacular
gain. If D7 fails, php is not a control, the 65x is an artefact, and the honest
report is that the machinery has never been demonstrated to work at all.

**D8.** The named failure of every timing lane in this tree. A sibling reported
go 400x faster than tree-sitter on process jitter. Mine will be subtler because
`amend`'s clock is inside the process, so the jitter is gone — which means the
flattery will come from the *denominator*: comparing against a baseline that was
paying a penalty my change removes for reasons unrelated to reuse.

## What I am deliberately not predicting

**That a policy change exists.** If the multi-root refusal is load-bearing, or if
the resume cannot land in a forest without doubling bytes, the answer is that the
ceiling is "clean files only" and Swift stays at 30 ms. That is a result and it
gets written the same way.

**A number.** D1–D7 are about shape. The one number I will commit to before
measuring the policy is in a second prediction file, written after the diagnosis
and before the change — because a predicted magnitude with no mechanism behind it
is a guess dressed as a forecast.
