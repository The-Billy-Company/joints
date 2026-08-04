# spans - the shapes tree-sitter's printers change shape on

Every file here is one span shape. They exist because two different readers of
tree-sitter's own output have now broken at a newline, three weeks apart, and
both times nothing in the corpus could catch it.

- `cst_tree` broke first: `--cst` renders a token that crosses a newline as one
  indented piece per row, where the XML has a single leaf. Sixteen of nineteen
  held-out grammars were being skipped and the reason looked like the grammars.
- `graft_fields` broke second: their `query` printer drops a capture's index and
  its `text:` tail for any capture with `end.row > start.row`. The reader
  demanded the index, so every multi-row **parent** line was dropped on the
  floor, and a dropped parent is a field that never gets grafted. That one cost
  javascript and typescript their byte-exactness and nobody could see it.

Both bugs have the same cause and it is not a coincidence: their renderers
branch on `end.row > start.row` in at least two places, so the honest assumption
is that the third one exists and has not been found yet.

## What is here

Eighteen javascript files, one shape each. javascript hosts them because it is
the one grammar with all three weak points at once - a multi-row block comment,
a multi-row template literal, and a field on an anonymous child (`kind` on
`const`) - and because it is byte-exact against tree-sitter, so a difference
here is the reader and never the parser.

The shapes were not invented. They came from driving their printers across spans
of one, two, three, four and twenty rows, a blank row inside, a 300-column
single row, a backtick in the text, and a node ending at column zero of the next
row; that last one has no characters on its final row and still takes the short
form, which is how the rule turned out to be the row numbers rather than the
bytes.

## How they are used

Two ways, and only one of them can fail.

```
python3 tool/differential.py run     # each fixture is a case; a wrong tree fails
python3 tool/differential.py spans   # which reader, on which shape
```

`run` compares each fixture against tree-sitter like any other case, so a reader
that drops a field leaves the oracle's tree short a label and the case reports
it. That is the gate. `spans` runs the three readers and says `ok` or the
refusal per shape; it diagnoses, it does not assert.

The set was checked against the bug it was built for: with the pre-fix
`QCAPTURE` restored, five fixtures fail with ten findings between them
(`03-three-rows`, `07-ends-at-column-0`, `11-nested-in-a-multi-row-node`,
`14-field-on-a-multi-row-node`, `16-multi-row-inside-multi-row`), and with the
reader as it stands all eighteen are byte-exact. A gate that cannot fail is
decoration, so that check is worth re-running before trusting this directory.

## Adding one

Write the file, name it for the shape, and run `differential.py run`. If a shape
you add fails, do not adjust the fixture; that is the third bug arriving on
schedule.
