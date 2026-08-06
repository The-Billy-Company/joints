# Result 1 — scala's layout seated, and the two predictions it falsified

Scala 3's optional-brace layout is now an `.offside` troupe. The corpus file
goes from **40.8% standing to 79.4%**, and both of the mechanism predictions I
wrote before building turned out to be wrong in ways that changed what the
change actually is.

> **Re-priced in both directions, and the mechanism holds (2026-08-06).** Every
> column on this page is ours. Sighted, in `consort/RESULT-8-sighted.md`:
>
> **The seating is worth more than the page claims.** Un-seating
> `_indent/.offside/.slashes` costs scala **6,739 `square` — every byte of
> agreement scala has with tree-sitter** — against 7,763 `damage`. The troupe is
> not merely worth +7,753 `built`: without it, scala and tree-sitter agree on
> nothing at all.
>
> **The 79.4% is worth less than it reads.** `standing` is our coverage, not
> the oracle's assent. Scala finishes at **6,739 `square` of 20,107 bytes —
> 33.5% `trued`**, with **9,218 of its 15,957 built bytes uncorroborated**. So
> the "40.8% → 79.4%" is the true delta in bytes we put under structure and is
> *not* a claim that four fifths of `Option.scala` is derived like
> tree-sitter's; less than half of the standing bytes are. The headline should
> be read as reach, and the file's remaining defect is now a derivation defect
> rather than a coverage one.
>
> **What that does to the falsification.** Nothing. "The indent and dedent arms
> are worth 21 nodes and zero bytes; every one of the 7,753 bytes came from the
> separator" is a differential inside our own forest between four cells that were
> all measured the same way, so it neither needs nor gets an oracle — and the
> co-admission count that explains it (2 of 11,602 states) is a table fact. It
> holds as written.
>
> **And scala's pair is a ceiling, not a cooperation.** `block_comment/.marrow`
> alone also costs 6,536 of the same 6,739 square, and the pair's residual is
> +6,547 — two rows each destroying nearly all of one quantity cannot sum. The
> word *cooperating* was withdrawn for scala in `vacuity/RESULT-5-pairs.md`.
>
> Nothing here was re-measured.

## The board, baseline to final

| | before | after | delta |
|---|---|---|---|
| `built` | 8,204 | 15,957 | **+7,753** |
| `strewn` (bytes under bare leaves) | 10,891 | 4,108 | −6,783 |
| `orphan` | 10,415 | 4,046 | **−6,369** |
| `rubble` | 476 | 62 | −414 |
| `spoil` | 1,012 | 42 | −970 |
| `unbound` | 1,488 | 104 | −1,384 |
| `nodes` (describes) | 1,571 | 1,772 | +201 |
| `roots` | 314 | 26 | −288 |
| **bare leaves** | **179** | **19** | **−160** |
| `covered` | 94.97% | 99.79% | +4.82 |
| `standing` | 40.80% | **79.36%** | +38.56 |

Board totals: `built` 341,506 → 349,259, `unbound` 121,918 → **120,534**,
standing 64.83% → **66.30%**, covered 82.61% → 82.79%, nodes 97,079 → 97,280.
No other grammar moved a byte. `built + orphan + rubble + spoil == size` still
holds for all thirty.

**`describes` alongside:** +12.8% nodes bought +94.5% `built`. That ratio is
*not* the shape of reading more the way swift's +54%/+197% was — it is the
shape of the same tokens being re-parented. 288 former top-level roots became
children of something. The parse was already reading these bytes (94.97%
covered before); what it could not do was structure them.

**Rubble and spoil: both fell, and this was established, not predicted.** With
`covered` at 94.97% before the change, scala was swift's case rather than
haskell's — the bytes were already inside the metric's reach, so there were
none to bring in and both buckets could only drain. That is prediction 2c and
it held.

**Nothing escaped into `orphan`.** This is the kotlin trap, where `built` fell
1,075 bytes while unbound fell 67% because recognised-but-unparentable KDoc
became top-level leaf roots. Scala ran the opposite way: `orphan` fell 6,369
bytes, because the scaladoc that was orphaned is now under the definition it
documents. Bare leaves fell 179 → 19.

## Prediction 1a held: scala is python's shape, not haskell's

The brief's hypothesis was that yaml and scala are "the same shape: layout
driven by a stack", and that scala might want haskell's `writ`. The scanner
settles it at the push site — `tree-sitter-scala/src/scanner.c:963`:

```c
bool indent_geometry =
    indentation_size > prev_width ||
    (scanner->after_colon_eol && indentation_size == prev_width);
if (valid_symbols[INDENT] && newline_count > 0 && … indent_geometry) { …
  array_push(&scanner->indents, entry);
```

The push is **measured**. `valid_symbols[INDENT]` is permission, not the
reason. Haskell's `_cmd_layout_start_do` is granted on the parser's say-so with
nothing measured at all, which is why that one needed a new kind. Scala did
not. Classified off the scanner's structure, per the standing rule — the two
mechanisms are indistinguishable from the grammar and opposite in the C.

`serialize` agrees: it writes `Array(int16_t) indents` plus five scalars
(`last_indentation_size`, `last_newline_count`, `last_column`, `last_char`,
`after_colon_eol`). A width stack and a little recent-lexical-context, which is
exactly `offside.Columns`.

## Prediction 2b falsified: the separator alone does the whole thing

I predicted the separator seated alone would drain **less than 1,000 bytes**,
reasoning from the C that the `AUTOMATIC_SEMICOLON` arm (line 1156) is
sequenced *behind* the `INDENT` (963) and `OUTDENT` (910, 1063) arms, so states
wanting a dedent would stay walled. I named the falsifier: build the
separator-only treatment as its own measurement.

I built it. Four cells, one variable pair:

| `indent`/`dedent` | comment rule | `built` | `nodes` |
|---|---|---|---|
| off | `hash` | 15,957 | 1,751 |
| off | `slashes` | 15,957 | 1,751 |
| on | `hash` | 15,957 | 1,772 |
| on | `slashes` | 15,957 | 1,772 |

**The indent and dedent arms are worth 21 nodes and zero bytes on this
corpus.** Every one of the 7,753 bytes came from the separator.

The census had already told me and I did not read it that way. `_indent` and
`_automatic_semicolon` are co-admitted by shift in **2** of 11,602 states;
`_outdent` and `_automatic_semicolon` in **2**. They almost never compete, and
209 of the separator's 493 shift states have it as the *sole* shift. Sequencing
in the C is not competition in the table — the arms are ordered because they
run in one function, not because they contend for the same offsets.

The honest read of this change is therefore: **scala's damage was newline
inference, and its indentation stack is a mechanism `Option.scala` barely
exercises.** The stack is seated and correct, and it is not what paid.

## The comment rule earns nothing measurable here, and I kept it anyway

`offside.lead` was python's, and python spells a comment `#`. 499 of the 628
lines of `Option.scala` open with `//`, `/*` or ` *`, so I expected a `#`-only
measurement to put the wrong column on four lines in five. It does — and the
board cannot tell, because with almost no indentation region in the file there
is nothing for a wrong column to be wrong about.

A field no measurement can falsify is a field that ends up cited in a doc
comment as working. This repo has been bitten by that twice. So `Note` is
falsified by unit test instead of by the board — four tests in `offside.zig`
pin the cases where the two rules diverge, including scala's nesting block
comment, which C's does not have and which a first-`*/` close would hand back
to the parser as code.

I kept it rather than dropping it because the C file is the spec and the C file
has `check_comment_at_layout`. Shipping a knowingly wrong transcription that
this one fixture cannot expose is the worse of the two failures. But the
measurement is what it is and is reported as such: **on the corpus, `.hash` and
`.slashes` are indistinguishable.**

## What is left, and what the wall is now

The verdict moved from
`lexer on (?:[_\p{L}]…) in state 229 [no stand-in for _automatic_semicolon]`
to
`lexer on " in state 610 [no stand-in for _simple_string_start]`, at byte
20,093 of 20,107 — the last string literal in the file. That is a `fence`
question, not a layout one, and it is 104 unbound bytes.

Per the brief: **treat the state id as a symptom.** `_simple_string_start` is
`inquest`'s guess at the name, and that scan favours a declared extra. The
*owner* word is trustworthy; I did not chase the name.

## Folio parity

The brief requires it for a new persisted field. `note` is not one: the folio
stores no troupe at all — a `Cast` holds a `*const Troupe` into the static
`troupes` array and the scanner is recompiled on load. Checked anyway, and the
trees are byte-identical (23,526 bytes, same verdict on stderr).

That check is also blind here for a reason worth writing down: since I *proved*
`.hash` and `.slashes` produce identical trees on this file, a folio that
silently dropped the field would pass this exact test. The parity check is real
and it is not what holds `note`. The unit tests are.
