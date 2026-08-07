`Str.php` built **119 roots** and read 40,995 of its 67,845 bytes as a single
`text` node - php's node for inline HTML *outside* `<?php` - while the board
called the grammar **87.2% standing**. It now reads `accepted, 1 root` at
**100.0%**, and against tree-sitter's derivation all 67,845 bytes are square:
the worst row on the board, **67.8% crooked**, is **0.0%**.

One question nobody answered. Byte 26,848 opens the file's first double-quoted
string, whose interior php hands to an external scanner as
`encapsed_string_chars`. This tree seated none of php's twelve externals, the
mend fired once over one byte, and the parser re-entered at `program` - whose
other production matches `[^\s<][^<]*` and swallowed the rest of the file. The
recovery does not orphan the remainder, it **claims** it, so every one of those
bytes scored `built`.

Four of the six terminals `scan_encapsed_part_string` serves are now seated as
a `marrow.Family`: `encapsed_string_chars`, `execution_string_chars`, and each
one's `_after_variable` twin. They are four rows of data behind one walk
because the two parameters that vary are never carried - the parse state
supplies `is_after_variable` and `is_execution_string` by naming one terminal
rather than another, which is what `Part` is for. The other two are the heredoc
pair, whose first statement reads a stack of tags one token pushes and another
spends; that is `fence`'s animal and they stay blind on purpose.

Five decisions in the walk are the specification's and none reads off the
shape: a `\xZ` is consumed *before* it is judged, so a malformed hex escape
leaves two bytes of matter and not one; `\{` is eaten ahead of the escape test
so its brace can never open an interpolation; `$1` is text, not a variable,
which is why every `preg_replace` replacement string in the corpus is content;
the delimiter that ends a run is the one *that member* opened with, so a
backtick inside `"…"` is ordinary; and end of input refuses outright, julia's
rule rather than elixir's.

Corpus-wide: square **205,583 -> 272,766**, crooked as a share of `built`
**21.62% -> 10.94%**, board **73.0% -> 74.7%**, and php off the widest-by-damage
list. No other grammar's row moves by a byte - `rack`'s own without-php split
reads 204,921 square identically on both arms, each arm measured with its own
`JOINTS_WORK` against a frozen oracle.

**The corpus can only see half of it.** `Str.php` holds zero backticks and zero
`<<<`, so the execution-string pair is seated and never exercised. Five php
specimens carry the rest, claims taken from tree-sitter's tree: the two
handover specimens a previous lane left deliberately red go 0/6 and 0/4 to 6/6
and 4/4, and three new ones pin the decisions the corpus cannot reach -
`$b[0]-$c->d` reading two ways from one parameter, `"\n$1x"`, and a backtick
command. A sixth stays red on purpose at the heredoc boundary.

That sixth one is also the finding that cost the most to admit. Its comment
claimed to be the guard against a hand widening the marrow roster onto the
heredoc pair. Run as a falsifier - roster widened, binary rebuilt - **nothing
in the tree turned red**: not the corpus row, not the specimen tier (41/51 both,
byte-identical), and not the specimen itself, which stops at `heredoc_start`
before either content terminal is asked for and so reads 0/7 either way. A
failing specimen is a to-do list entry, not a guard; there is no number below
zero for it to fall to. `scanner: a row claims the terminals it is pinned to
and no others` is the check that was missing - it pins the ordered terminal
list of every roster-shaped row and fails naming the intruders, and it exists
because a comment made a claim nothing could check.
