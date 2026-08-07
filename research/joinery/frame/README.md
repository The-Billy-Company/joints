# frame — a node nobody built, and a spelling nobody spoke

Two instruments, each shipped with a hole its own author demonstrated and did
not close, plus one hole neither author knew about.

## The hole neither knew about: the oracle had no name

`rack` stamped fourteen fields and all fourteen were about joints. The oracle
is half of every number it prints. A sibling lane caught the cost — **scala read
1,278 crooked in one run and 9,087 in the next, same pin, same unedited script,
stamp byte-identical** — because three oracle libraries were rebuilt mid-session
by other lanes and nothing recorded it.

`tool/attest.py` seats the oracle by digesting the **sources** each grammar is
built from rather than the library, and `rack` and `absent` both print the seat
on every run. Twenty-eight of twenty-nine grammars currently exist as several
different files at once, and a library digest cannot tell that apart from a
plain rebuild — `attest.py verify` measures both and says so.

Every number below is on pin `frame` (`cf697da9f`) against oracle `800ede524`,
tree-sitter 0.26.11.

## rack: the frame

`<p>x</q>`, nine bytes. tree-sitter reads one `element [0, 8)`. joints reads
two roots and no `element`, and the rule `rack` shipped with scored that **7
square, 0 crooked — a perfect row**, because `rack` compares spines inside built
windows and a node we never built is in no window.

A frame is now missing when the oracle has a bracket, other than its own root,
wholly containing two or more of our roots and we have no node with that extent.
Its bytes go to a new `unframed` column, taken only from `square` and `renamed`,
never added to `crooked`.

**60,067 bytes, 15.61% of built** — and **56,715 of them (94.4%) are ONE frame
per file.** Elixir's whole 26,756 is a single file-wide `do_block`. Where a file
is one construct that is the forest-versus-tree difference wearing a new name,
already priced by `orphan`/`rubble`/`spoil`. The seam charge — every other
missing frame — is **3,352 bytes, 0.87% of built**, and that is the part worth
defending. The board prints the split rather than the total alone.

Full working, the three failed predictions and the wrapper problem I named in
advance and then found: [`RESULT-1-frame.md`](RESULT-1-frame.md). Written first:
[`PREDICTION-1-frame.md`](PREDICTION-1-frame.md).

## rack: the over-charge, going the other way

A parent **both sides agree on** whose right edge moved is a real defect and is
not "a shape tree-sitter does not build". `soft` now subtracts **12,439** such
bytes, behind whitespace and extras so the columns partition:

| | crooked | soft | **HARD** |
| --- | --- | --- | --- |
| before | 83,169 | 27.7% | **60,138** |
| after | 83,169 | 42.6% | **47,699** |

toml is the whole class: **29 crooked, 100.0% soft, 0 HARD.** A sibling
adjudicated toml properly — zero declared conflicts, zero contested cells across
175 states — and the verdict was against this instrument. It now agrees.

## rack: the diagnostic nobody read

`standing.py` has been printing `UNSOUND — child outside its parent` on the toml
row the whole time, on a grammar the board scores 100.0% and `whole`.
`rack board` now reprints every such row under the table. **One row carries one
today.** It is the moved-edge defect arrived at from the other side: joints
said so about its own forest before any oracle was consulted. The note for that
lane is [`HANDOVER-standing.md`](HANDOVER-standing.md).

## absent: presence as a node

A spelling counted present if its bytes occurred anywhere, comments included.
Now a second reading asks whether the oracle ever produced that token, and the
test is not "is it inside a comment" but **"is it inside the thing that declares
it"** — so lua `--` stays present and scala's `true` comes back a mention
`inside block_comment`.

Of the 1,767 spellings the byte reading calls present over the 27 oracled
grammars, 506 are sealed inside a `token(...)` and unanswerable, and of the
1,261 that remain **288 are never tokenised at all — 22.8%, the overcount**.
Corpus present goes **39.4% → 33.9%**.

`impossible` becomes a range: **903 floor, 1,089 ceiling** over the oracled
grammars (the ceiling minus its own five countable errors). The published 1,319
is the lower end of a range, not a measurement.

Full working: [`RESULT-2-presence.md`](RESULT-2-presence.md). Written first:
[`PREDICTION-2-presence.md`](PREDICTION-2-presence.md).

## The least trusted instrument

`absent.py`'s node reading, and it is the one this lane built. It is blind on
506 spellings by construction, blind on three whole grammars, and its ceiling is
demonstrably wrong on five rules. The byte reading beside it is blind in the
other direction. Neither covers the other's half, and any single percentage
quoted from either without the other is a mention read as a construct or a
`token(...)` read as an absence.

## Verbs

```sh
python3 tool/attest.py show                    # each grammar's oracle and seat
python3 tool/attest.py verify                  # why sources, not libraries
python3 tool/rack.py   board  --oracle=frame   # the split + unread complaints
python3 tool/rack.py   soft   --oracle=frame   # blank / extra / edge / HARD
python3 tool/rack.py   verify                  # 19 tripwires
python3 tool/absent.py oracle --oracle=frame   # both readings, and the gap
python3 tool/absent.py verify                  # 18 tripwires
```

`--oracle=` without a seat runs against the shared tree four lanes write to, and
says so on stderr rather than pretending it is pinned.
