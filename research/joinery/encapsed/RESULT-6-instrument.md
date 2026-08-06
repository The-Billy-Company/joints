# Result 6 — the instrument I trust least is the one I wrote today

The brief asks for the instrument I trust least, with a demonstration. The
honest answer is not `rack`, whose oracle got attributed and frozen under me
mid-lane, and not `standing`, whose blind spot is documented in its own header.
It is **`research/joinery/specimen/php/heredoc-still-blind.php`**, which I
authored four hours ago as the guard on my own seating, and which cannot do the
job its comment claimed.

## What it claimed

The roster in `outside.zig` seats **four** of the six terminals
`scan_encapsed_part_string` serves. The two it refuses are the heredoc pair,
which read a tag stack and belong on a `fence`. I wrote a specimen for that
boundary and wrote this in it:

> a later hand widening it onto the heredoc pair without giving them a tag
> stack would make THIS file's `heredoc_body` come out wrong rather than
> absent, and a green run here with the marrow roster widened is the outcome
> nobody should be able to reach quietly.

An argument in a comment. This tree has caught that exact species before — the
`marrow/kotlin_block` pin whose prose asserted two rows could never be handed
each other's grammars, which was true and was not a check.

## The demonstration

I widened my own roster onto the two heredoc members, gave them the wrong mark
(`shut = '"'`, no tag stack), rebuilt as pin `php-widened`, and asked every
tier in the tree whether anything was wrong.

| instrument | correct roster (4) | widened roster (6) |
|---|---|---|
| `Str.php` corpus row | `accepted, 1 root` | `accepted, 1 root` |
| specimen tier | 41/51 sound | **41/51 sound** |
| `php/heredoc-still-blind.php` | 0/7 FAIL | **0/7 FAIL** |
| seating pin, `every troupe seats…` | green | **green** |

**Nothing turned red.** Byte-identical output on every tier.

The corpus cannot see it because `Str.php` contains zero `<<<` and zero
backticks — the Swift-`/*` story again, and I had predicted that half. The
seating pin cannot see it because its key is `mechanism#anchor` and its value
is a grammar list: widening a roster changes neither.

And **my specimen cannot see it for a reason worse than either**: those bytes
stop at `heredoc_start`, a *third* unseated external, before either content
terminal is ever asked for. So the widened build's forest over the file is
identical to the correct build's. A red specimen has no number below zero to
fall to — it was already failing, so it reports the same failure whether the
code beneath it is right or wrong. **A failing specimen is a to-do list entry,
not a guard**, and I filed one as a guard.

## What I did about it

Two things, and the second is the one that matters.

I corrected the specimen's prose to say what it does and does not prove,
including that its first draft was wrong. A comment that overclaims is worse
than no comment, because the next lane reads it as coverage.

Then I added the check that was missing —
`scanner: a row claims the terminals it is pinned to and no others` in
`scanner_test.zig`. It pins, per troupe key, the exact ordered list of
terminal names the row claims, for the three rows whose surface is a *roster*
(php's four, julia's ten, abut's five) — because a roster is the thing a hand
extends by one line. Re-run against the widened build it fails and names the
intruders:

```
marrow/php_encapsed#encapsed_string_chars: claims 6 terminal(s), pinned at 4
  … claims encapsed_string_chars_after_variable_heredoc
  … claims encapsed_string_chars_heredoc
expected 4, found 6
```

It also asserts that all three pinned keys were actually found, so a renamed
key cannot silently check nothing — the same failure one level down.

## The part that is still true after the repair

The new gate catches a **widening**, which is one edit. It does not catch a
wrong *mark* on a correctly-named member: swapping `'"'` for `` '`' `` in a
roster row is invisible to it, and — because `Str.php` has no backticks —
invisible to the corpus too. The four unit tests over `walk(.php_encapsed, …)`
are what stand there, and unit tests written by the same hand as the walk are
the weakest evidence in this folder. If someone wants the next hole, that is
where I would look.

## Bookkeeping

The `php-widened` pin was built, measured, and the roster reverted; the tree
carries the four-member roster. The falsifier build was run in a scratch tree
rsynced out of the live one (`../lane-check`), because a sibling's in-flight
`weave.zig` edit was breaking the test build at the time and I was not going to
touch their file — the same cheap control that lane recommended for exactly
this situation. In that scratch tree, carrying my full change: **376 tests
passed, 0 failed.**
