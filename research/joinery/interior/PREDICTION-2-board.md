# Prediction 2 — what the board does, established before it is moved

Written before any seating existed. The baseline is
`.local/lane-strings/board-before.json`, taken 2026-08-05T19:34Z, binary
`joints 9e422a351`.

## The baseline rows, as read

| grammar | bytes | cover | stand | built | strewn | orphan | rubble | spoil | unbound | roots | leaves |
|---|---|---|---|---|---|---|---|---|---|---|---|
| julia | 27,360 | 68.6% | 39.0% | 10,679 | 8,087 | 2,374 | 5,713 | 8,594 | **14,307** | 2,477 | 1,539 |
| kotlin | 35,815 | 97.4% | 41.4% | 14,841 | 20,038 | 19,705 | 333 | 936 | 1,269 | 419 | 237 |
| swift | 28,468 | 96.3% | 81.3% | 23,131 | 4,297 | 3,997 | 300 | 1,040 | 1,340 | 308 | 179 |
| scala | 20,107 | 99.8% | 79.4% | 15,957 | 4,108 | 4,046 | 62 | 42 | 104 | 26 | 19 |

Board totals: `349,259 built + 57,005 orphan + 29,868 rubble + 90,666 spoil =
526,798`, `unbound 120,534`, **66.3% standing / 82.8% covered**, `describes
97,280 nodes`, 12 of 30 whole.

Walls, as `inquest` names them (the **owner** word and the **item** are
trustworthy; the stand-in **name** is a guess and one of these is the known
lie):

- julia — `lexer on _word_identifier in state 45 [no stand-in for _content_str_3]`
- kotlin — `lexer on (?:[^\r\n]*) in state 433 [no stand-in for _string_start]`
- swift — `lexer? on ) in state 141 [no stand-in for multiline_comment]` — the
  `lexer?` prefix and the "best reading rather than a proof" clause are the
  cure the inquest lane shipped; `multiline_comment` is the declared extra that
  wins every stand-in scan in swift, so this name says almost nothing.
- scala — `lexer on " in state 610 [no stand-in for _simple_string_start]`

## P2a — julia moves spoil, not rubble

`covered` is **68.6%**, so 8,594 bytes were never reached at all. That is the
haskell case, not the swift case: seating a wall the parse never got past
lets the parse *reach* bytes it had not reached, and reached-but-misattributed
bytes are rubble. So I predict **spoil falls by more than 4,000 and rubble
does not fall below 4,000** — it may well rise.

**Falsifier:** rubble falling toward zero while spoil stays put. That would
mean julia's bytes were already reached and I read the wrong case off
`covered`.

## P2b — julia's `strewn` and `roots` fall hard

2,477 top-level roots over 1,539 leaves in a 27 KB file is a shredded parse:
the mend put the stack down 2,477 times. A working string interior should
collapse most of that. I predict **roots below 500 and leaves below 400**.

**Falsifier:** `built` rising while `roots` stays above 2,000 — that is
`covered` inflating under bare leaves, which is the watermark
`tool/standing.py`'s own docstring warns about and the reason `strewn` exists.

## P2c — julia's `describes` rises, and by more than `built` does in ratio

Scala's +12.8% nodes for +94.5% `built` was correctly called *re-parenting*.
Julia is the opposite shape: the bytes are not reached at all today, so
reading them should mint genuinely new nodes. I predict julia's node count
rises by **more than 20%** while `built` rises.

**Falsifier:** `built` rising while `describes` falls. That is the verilog
`keep` trap — a metric improving by reading less — and it invalidates the
result outright.

## P2d — orphan will move the wrong way somewhere, and I expect kotlin

Kotlin's `built` *fell* 1,075 bytes on the last seating even as unbound fell
67%, because KDoc the parse now recognises sits as top-level leaf roots.
Kotlin's orphan today is **19,705 of 35,815 bytes — 55% of the file**. If I
touch kotlin at all, I expect the same interaction, and I will report it as a
movement rather than as an artifact.

For julia, orphan is 2,374 and the file's two comment forms are already
seated (`_block_comment_rest` is a `marrow` row today). I predict julia's
orphan **rises**, because comments currently buried inside unparsed regions
become top-level leaf roots the moment the surrounding parse gets further and
then stops somewhere else.

**Falsifier:** julia's orphan unchanged. Then the comments were already
top-level and I have mis-modelled where they sit.

## P2e — nothing else on the board moves

Twenty-nine other grammars must be byte-identical **in tree**, not in folio.
The press is currently not byte-reproducible for nine of thirty, so a folio
digest comparison is not evidence — and the previous lane's folio parity check
passed *and could not have failed*. The check I will run has to be able to
fail: same binary, thirty grammars, tree render compared before and after,
with the control being that I can make it red on purpose.

**Falsifier:** any of the other twenty-nine grammars' trees differing.
