# Result 3 — toml: neither a gap nor a conflict, and `rack` is what's wrong

Scores `PREDICTION-3-toml.md` (P7–P9). Pin `tenon` (`4d7074db7`, tree
`fa7fcaee5`, repo `f7ba40004+106`). The lane that reported these 29 bytes said
it thought `rack` decided wrong on them. It did, and not for the reason either
of us guessed.

## The witness

```toml
v = "1"  # c
```

13 bytes, seated as `specimen/toml/comment-after-pair.toml`.

```
  joints                          tree-sitter
  document [0, 13)                  document [0, 13)
    pair [0, 7)      <- 7             pair [0, 12)     <- 12
      bare_key [0, 1)                   bare_key [0, 1)
      "=" [2, 3)
      string [4, 7)                     string [4, 7)
      comment [9, 12)                   comment [9, 12)
```

Read the indentation and then read the extents. **The comment is a child of
`pair` on both sides.** Every name agrees, every nesting agrees, every leaf
agrees. One number differs: joints's `pair` ends at 7, and it has a child
that starts at 9.

The control is the same line without the comment: `pair [0, 7)`, identical
trees, sound.

## The verdict: neither GAP nor CONFLICT

`joints grammar upstream/grammars/toml.json` reports **0 declared
conflicts**. `survey` reports **0 contested cells over all 175 states**. There
was never a second derivation for the press to prefer, so there is no choice
here to have made wrongly — and there is no missing rule either, since both
parsers derive the same tree. The GAP/CONFLICT axis has no answer for this
defect because this defect is not a parse decision. It is one node's recorded
extent failing to grow over a child the parser already adopted.

## P7 — `rack soft` attributes the majority to extras placement. **FAILS.**

`rack soft` gives toml **44.8%** — 4 blank + 9 extra of 29. Under half, which
is exactly the falsifier. And the reason it fails is the finding: `soft` can
only see the comment's own 9 bytes. The other 20 are `v`, `=`, `"1"` and the
whitespace between them — bytes whose parent both parsers name `pair` — charged
because the *parent's* right edge moved. `rack.py`'s own docstring says the
quiet part:

> `rack soft` cannot catch it either, because the bytes it charges are not the
> extra's — they are the siblings'.

So the soft/hard split, which is `rack`'s honest self-audit and the best thing
about it, structurally cannot reach this class.

## P8 — there is a real toml defect `rack` is not reporting. **HOLDS.**

> **Falsifier.** toml no longer reports UNSOUND, or the unsoundness turns out
> to be the same comment **and therefore the same soft finding.**

`tool/standing.py`, on the same run, on a grammar it scores 100.0% standing and
`whole`:

```
sound  1 of 30 UNSOUND — toml: 1 loose, 0 disorder, 0 torn
  [child outside its parent: comment [47, 56) in pair [27, 45)]
```

It is the same comment. It is emphatically **not** the same finding, so the
conjunction does not fire. A child outside its parent is not a soft attachment
preference — it is not a tree. Anything that walks the structure by extent is
walking a shape that cannot exist, and `rack.py`'s `cover()` is exactly such a
walker; its docstring cites this very `UNSOUND` line as the reason it filters
by extent instead of popping a stack, and then charges the bytes anyway.

Two instruments have been looking at the same 13 bytes all along. `standing`
says *this tree is malformed*, which is true and serious. `rack` says *these
parsers disagree about derivation*, which is false. The board reads `whole`.

## P9 — the GAP/CONFLICT axis separates nothing. **HOLDS for three, and toml is off it.**

elixir, go and python are all CONFLICT and the axis does not distinguish them —
the mechanism had to be earned from the tables (`RESULT-1`, `RESULT-2`). toml is
stronger than P9 allowed: it is neither, and asking the closure produces a
category error rather than a weak answer.

## What the 29 bytes actually are

`extent.py` re-sorts `rack`'s own charge without changing its total:

```
grammar   crooked  span  soft  shape  soft  DISPUTED
toml           29    18     2     11    11         0
```

18 bytes are a right parent measured wrong. 11 are shape, and all 11 are soft by
`rack soft`'s own test (the comment's 9 plus 2 of whitespace). **Zero bytes are
a parent in dispute.** toml belongs on the clean list, and the reason it is not
on the clean list is a defect in the instrument, not in the parser — though the
parser does have a real bug here, and it is the one `standing` has been printing
without anyone acting on it.
