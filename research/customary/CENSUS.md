# Eight scanners, one question: what does `serialize` write?

`research/joinery/semi/CLASSIFICATION.md` established the axis and this document
finishes the sweep over it. The axis is not negotiable and it is not ours:

> tree-sitter requires an external scanner to declare its whole memory through
> `serialize`/`deserialize`, because the runtime snapshots it at every GLR fork.

So a scanner's carried state is exactly what those two functions move, and
anything else it holds is transient within one call. That makes the census
mechanical rather than interpretive: read `serialize`, and the shape it writes is
the shape a stand-in has to hold.

Every C quotation below is from the pinned scanner under
`.local/differential/lang/<name>/src/scanner.c`, read as a specification.
Nothing is linked, nothing is compiled, and nothing here is a paraphrase of a
README - where this document and a scanner disagree the scanner is right.

## The eight, and the correction the census makes to the roster

The README named eight grammars that "keep per-language state in C structs
across calls". Read against `serialize`, **two of the eight do not**:

| grammar | `serialize` writes | externals | blind today |
|---|---|---:|---:|
| yaml | 5 × `int16_t` + a **paired** typed indent stack | 113 | 113 (nothing lexes) |
| haskell | a stack of `{sort, indent}` + a newline block | 48 | 30 |
| markdown | 5 × `uint8_t` + a stack of block kinds | 47 | 47 |
| swift | **one** `uint32_t` | 33 | 10 |
| elixir | **nothing - `return 0`** | 26 | 2 |
| scala | 5 × `int16_t` + a stack of widths | 25 | 17 |
| kotlin | a stack of `(delimiter, prefix_len)` byte pairs | 10 | 1 |
| html | a stack of tags, enum or interned name | 8 | 0 |

310 externals, which is where the README's figure comes from, and 220 of them
blind. But the sentence built on that figure was wrong in both directions:

- **elixir carries no state at all.** Its serialize is three lines and one of
  them is `return 0`. Its 26 externals are a delimiter table
  (`quoted_content_infos`) walked against the bytes at the offset, which is why
  `marrow` already answers 24 of them.
- **html's whole memory is one stack** and joints already holds it
  (`hand/lineage.zig`), which is why html is at zero blind and parses
  `viewer.html` whole - 72,288 bytes, one root.

So the ceiling was never "eight grammars keep state". It is **six**, and the
memory those six keep is smaller and more uniform than the prose suggested.

## The state, grammar by grammar

### yaml - `scanner.c:148-189`

```c
typedef struct {
    int16_t row;  int16_t col;
    int16_t blk_imp_row;  int16_t blk_imp_col;  int16_t blk_imp_tab;
    Array(int16_t) ind_typ_stk;
    Array(int16_t) ind_len_stk;
    // temp
    int16_t end_row, end_col, cur_row, cur_col;  int32_t cur_chr;
    int8_t sch_stt;  ResultSchema rlt_sch;
} Scanner;
```

`serialize` writes the first five scalars and then walks the two arrays **in
lockstep**, one `int16_t` from each per entry. The fields below the `// temp`
comment are not written and are therefore not memory: `rlt_sch` in particular is
recomputed per scan, which is the finding `layout/RESULT-2-yaml.md` turns on.

So: five registers, and one stack whose element is a *pair* - a kind beside a
width. That is one stack of a two-field element, not two stacks; the C keeps two
arrays and pushes to both at once, which is the same object spelled twice.

### haskell - `scanner.c:300-303, 410-425, 3417-3432`

```c
typedef struct { ContextSort sort; uint32_t indent; } Context;
```

`serialize` writes `{.contexts = state->contexts.size, .newline = state->newline}`
followed by the contexts themselves. `state->lookahead` is **not** written, so
haskell's `Lookahead` is transient despite being a struct field. `ContextSort` is
ten values, six of which are layout blocks (`DeclsLayout`, `DoLayout`,
`CaseLayout`, `LetLayout`, `QuoteLayout`, `MultiWayIfLayout`) and three of which
are markers with no indentation meaning at all (`Braces`, `TExp`,
`ModuleHeader`).

That is the same `{kind, width}` element yaml keeps, and joints already encodes
it - `hand/writ.zig` stores the three markers as reserved columns near
`maxInt(u16)` so that one stack carries both. The reserved-column trick is a
correct encoding and it is also the reason the file needs a paragraph explaining
it: a typed element says the same thing without the arithmetic.

`Newline` is the second half and it is registers, not a stack:

```c
typedef struct {
  NewlineState state;   // 4 values
  Lexed end;            // the classified token after the extras
  uint32_t indent;
  bool eof; bool no_semi; bool skip_semi; bool unsafe;
} Newline;
```

One small enum, one width, four flags, and one *classification of the next
lexeme* - which is a function of bytes ahead of the offset, so it is a probe
result rather than a memory.

### markdown - `scanner.c:197-253`

```c
typedef struct {
    struct { size_t size, capacity; Block *items; } open_blocks;
    uint8_t state;      // three flags: MATCHING, WAS_SOFT_LINE_BREAK, CLOSE_BLOCK
    uint8_t matched;
    uint8_t indentation;
    uint8_t column;
    uint8_t fenced_code_block_delimiter_length;
    bool simulate;
} Scanner;
```

`serialize` writes the five `uint8_t`s and then the block stack verbatim.
`simulate` is not written, and it is not state: it is a *mode* one scan runs its
own matching pass in without emitting, which in this design is an interpreter
that scores a rule without committing its actions.

`Block` is twenty values, and sixteen of them are one family with a width folded
into the tag - `LIST_ITEM_1_INDENTATION` through `LIST_ITEM_MAX_INDENTATION`,
which the C itself unfolds arithmetically:

```c
static uint8_t list_item_indentation(Block block) {
    return (uint8_t)(block - LIST_ITEM + 2);
}
```

So markdown's twenty-value enum is really `{kind, width}` too, packed into one
byte because the C had one byte to spend. A typed element carries it as five
kinds and a width, which is the same information without the ladder.

`RESULT-1-stack.md` measured why the parse table cannot break the tie instead:
`_line_ending` and `_soft_line_ending` are co-admitted by shift in **133 of the
201 states** either can shift in, so a forking hand would fork at nearly every
newline in the file. The memory is not avoidable by deferring to GLR.

### swift - `scanner.c:276-301`

```c
struct ScannerState { uint32_t ongoing_raw_str_hash_count; };
```

Four bytes. One number: how many `#` opened the raw string being read.
`CLASSIFICATION.md` already established that 31 of swift's 33 externals never
read it, and the two that do are the raw-string family. `multiline_comment`
needs a nesting depth that swift tracks on the **C stack** through recursion -
memory that `serialize` cannot see, and the one place in the eight where the
axis under-reports. A counter states it without recursion.

### scala - `scanner.c:89-140`

```c
typedef struct {
  Array(int16_t) indents;
  int16_t last_indentation_size;
  int16_t last_newline_count;
  int16_t last_column;
  int16_t last_char;
  int16_t after_colon_eol;
} Scanner;
```

A stack of widths and five registers, and `serialize` refuses outright rather
than truncating when the two together would overflow:

```c
if ((scanner->indents.size + 5) * sizeof(int16_t) > TREE_SITTER_SERIALIZATION_BUFFER_SIZE) {
    return 0;
}
```

which is worth noting because it is tree-sitter's own admission that its
snapshot is lossy at depth. A file nested past that point silently forks from
zero state.

`last_char` carries its own comment - "Two lines can share a column, so the
character keeps the saved newline from being recovered at an unrelated
position" - which is a register holding one byte of the source, not a new organ.

### kotlin - `scanner.c:46-61, 955-979`

```c
typedef char Delimiter;
typedef Array(Delimiter) Stack;

static inline void stack_push(Stack *stack, char chr, bool triple, uint8_t prefix_len) {
  array_push(stack, (Delimiter)(triple ? (chr + 1) : chr));
  array_push(stack, (Delimiter)prefix_len);
}
```

The stack is bytes, pushed two at a time, and `deserialize` says so:
"Stack entries are 2 bytes each (delimiter + prefix_len)". So the element is
`{delimiter, count}` - a mark and how many of a prefix character opened it,
which is `#`-counting under another name. `scan_automatic_semicolon` takes
`payload` and never dereferences it.

### html - `scanner.c:18-101`

```c
typedef struct { Array(Tag) tags; } Scanner;
```

One stack. A `Tag` is an enum value, except for `CUSTOM`, where the element also
carries the uppercased name as bytes - and `serialize` spells that encoding out:
a type byte, then for `CUSTOM` a length byte and the name. Names are compared
case-folded (`towupper` in `scan_tag_name`), the known set is a closed table in
`tag.h`, and the implied-close rules are two predicates over it (`tag_is_void`,
`tag_can_contain`).

So html's element is `{kind, bounded bytes}`, and the per-language part - which
tags are void, which may contain which - is a **table**, which is the whole
point: a table can live in a file.

### elixir - `scanner.c:629-638`

```c
unsigned tree_sitter_elixir_external_scanner_serialize(void *payload, char *buffer) {
  return 0;
}
```

Nothing. Elixir's 26 externals are a walk over `quoted_content_infos`, a table
of `{token_type, supports_interpol, end_delimiter, delimiter_length}`, against
the bytes at the offset. It is in this census only because the README put it
here, and taking it out is the census's first result.

## The organ set the eight actually need

Every element above is one of three things, and nothing in the eight is a
fourth:

| organ | element | who needs it |
|---|---|---|
| **frames** | `{ width: i32, kind: u16 }` | yaml (paired stack), haskell (contexts), markdown (open_blocks), scala (indents), python |
| **marks** | `{ kind: u16, count: u16, tag: bytes ≤ 32 }` | kotlin (delimiter+prefix), html (tag or custom name), ruby/python/rust fences, elixir's delimiters |
| **regs** | `[8] i32` | markdown's 5, scala's 5, yaml's 5, haskell's newline block, swift's hash count and comment depth |

Two stacks and a register bank. The two stacks are not one stack with a wider
element, and the reason is that they nest independently: a file can be inside a
heredoc *and* inside three indentation regions, and the innermost of each is a
different question. joints already keeps exactly this split
(`offside.Columns` · `fence.Spans` · `lineage.Tags`), so the census is mostly a
confirmation - with one merge (`Tags` is a `marks` stack whose element carries
bytes) and one addition (`regs`, which no hand has today and four of the six
stateful scanners need).

## The kill condition, and why it was not met

Rung 0's kill condition was:

> any external whose decision requires an input outside {bytes at/after the
> offset, line-start/indent/column facts, `valid_symbols`, declared organs}.

Every decision in the eight reads only those. Four cases came close enough to
name:

- **markdown's `simulate`** looks like a hidden input and is a control-flow
  device: the same rule body, scored without committing. An interpreter runs a
  rule's guard without applying its actions, which is the same thing spelled as
  the engine's own structure.
- **haskell's `Lexed end`** is the classified identity of the next lexeme after
  extras. It is a probe over bytes ahead of the offset - the widest lookahead in
  the eight, and still bytes.
- **swift's `multiline_comment` depth** lives on the C stack rather than in
  `serialize`, so the axis under-reports it. It is a counter; a register holds
  it.
- **`valid_symbols[ts_builtin_sym_error]`** - markdown reads it, and so do
  several of the thirty. It is the parser telling the scanner it is in error
  recovery. That is not outside the set: it arrives *through* `valid_symbols`,
  and joints has the same fact where `mend` is running. It is a declared test
  rather than a new input.

One genuine addition to the instruction set, from yaml and named in
`layout/RESULT-2-yaml.md`: a rule may need to **rename its own answer** by
running a second pressed table over the text it just matched
(`_r_sgl_pln_{str,int,bol,nul,flt,tms}_blk` are six terminals over one scan,
co-admitted by shift in all 19 of their states). That is a classifier, it is an
action rather than an input, and it is in the frozen set for exactly that
reason.

## Provenance

Baseline measured on the tree this document was written against; re-run rather
than trust it, per the README's own warning about corpus totals.

```text
python3 tool/census.py --set=breadth     -> .local/customary/census-before.txt
python3 tool/plumb.py board --json       -> .local/customary/board-before.json
```

Scanners read at:

```text
.local/differential/lang/{yaml,haskell,swift,elixir,scala,kotlin,html}/src/scanner.c
.local/differential/lang/markdown/tree-sitter-markdown/src/scanner.c
.local/differential/lang/html/src/tag.h
```
