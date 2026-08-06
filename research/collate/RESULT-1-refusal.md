# Result 1 — the bytes tree-sitter refuses, adjudicated

**The candidate win is 30,959 bytes, it is one file, and hand adjudication
splits it almost down the middle.** Of the verilog constructs I read against the
language's own grammar, outliner is right on 8 and wrong on 6, and the two
widest disputed spans are ones where **both parsers are confidently wrong**.

The brief's strongest sentence about this lane — "tree-sitter produces nothing
usable for that file" — is **wrong**. Inside its root `ERROR` on `picorv32.v`,
tree-sitter still hands back 59,611 bytes under named nodes, 63% of the file. It
is not refusing to parse. It is parsing and telling you not to trust it.

Measured on pin `collate` (tree `735a2c2ee2e8`, binary `a01fcb3448c4`), oracle
tree-sitter 0.26.11 generated from the same pinned `grammar.json` the press
reads, 2026-08-05.

## The census

Two files of thirty carry an oracle `ERROR`. Not five.

```
verilog  picorv32.v   94,657B   ERROR = the root, 100% of the file
sql      ledger.sql    6,390B   ERROR spans 554B, 8.7%
                                ─────────
             ERROR bytes  95,211    of which one file is 99.4%
   outliner builds inside     30,959    ← the candidate win, before adjudication
```

`yaml` is not in that count and is not a refusal: tree-sitter cannot **build**
its scanner here at all. Its `scanner.c` does `#include _file(YAML_SCHEMA)`, a
macro-constructed include, and the compile dies with `fatal error:
'schema.core.c' file not found`. That is a tree-sitter installation failure and
it is priced on the installation axis in Result 2, not here.

**The inherited 34,687 is not the same number as this 30,959, and neither is
wrong.** `plumb`'s `unjudged` folds two things: bytes under a recovery region,
and bytes tree-sitter's tree does not cover at all. Only the first is a refusal.
sql contributes 3,967 to `plumb`'s figure and 239 to this one, because
tree-sitter's `ERROR` there is 554 bytes rather than the file.

## Prediction 1, scored

| | | |
|---|---|---|
| P1 | ERROR on ≥5 of thirty | **FALSIFIED** — 2. The candidate win is not a corpus phenomenon; it is verilog |
| P2 | named descendants under the root ERROR cover ≥50% of `picorv32.v` | **held** — 59,611B, 63.0% |
| P3 | fewer than half the adjudicated sample is right | **split** — 8 of 14 by count (57%, falsified); 1,343 of 2,724 bytes (49.3%, held) |
| P4 | outliner's self-report recall over its own misreadings is 0.00 by construction | **held, as an identity** — see below |
| P5 | tree-sitter flags 0 bytes of php | **held** — 0 ERROR, 0 MISSING on all 67,845 |
| P6 | ≥1 adjudicated-right outliner construct inside an oracle ERROR | **held** — 8 of them, 1,343 bytes |
| P7 | my instrument lies first, flatteringly | **held twice** — see "the instrument I trust least" |
| P8 | the top two ERROR files are ≥80% of the total | **held** — verilog alone is 99.4% |

P1 failing is the finding. I built this lane expecting a corpus-wide seam of
bytes tree-sitter gives up on, and there is no seam. There is verilog.

## What the hand adjudication says

Twenty spans, each written out in `verdicts.toml` with what both trees said and
why I decided as I did. `collate.py adjudicated` re-derives both from the live
binary and the live oracle and excludes any row that no longer matches. **20 of
20 still describe both trees** on this pin.

```
ours        8 verdicts    1,343B   outliner is right
theirs      7 verdicts      166B   tree-sitter is right
neither     2 verdicts    1,215B   both are wrong
agree       3 verdicts    1,163B   both say the same thing (controls)
```

By count outliner wins the sample. By bytes it does not, because one 1,188-byte
row is `neither`: the two module instantiations in `picorv32.v`, which **both
parsers call a class type**. That is the widest built root outliner has on the
file and it is wrong, and it is equally wrong in tree-sitter.

The sample is hand-picked, not random — I walked outliner's widest roots and the
commonest disagreement pairs. Treat 8-of-14 as "what a careful reader found",
not as an estimate of the population.

## Improvement — outliner sees verilog's module structure and tree-sitter does not

**Consumer: an outline view, a symbol index, and go-to-definition.**

Inside the root `ERROR`, tree-sitter's recovery has no node for the second
module's header, its parameter port list, or its ports. Outliner names all
three. Concretely, on `picorv32.v`:

| span | bytes | outliner | tree-sitter | what a consumer gains |
|---|---|---|---|---|
| `[80092,81099)` | 1,007 | `parameter_port_list` | root `ERROR [0,94657)` | expand-selection from one parameter stops at the list, not the file |
| `[80072,80091)` | 19 | `module_header` | `ERROR [79903,80128)` | `picorv32_axi` appears in the outline at all |
| `[81177,81206)` | 29 | `ansi_port_declaration` | `list_of_param_assignments` | a port list reads as ports, not as 29 parameter assignments |
| `[6321,6509)` | 188 | `task_declaration` | loose inside `seq_block` | go-to-definition for `empty_statement` resolves |
| `[1418,1438)` | 20 | `text_macro_definition` ending at the newline | runs to 1447, swallowing the `` `endif`` | deleting the macro does not unbalance the conditional |
| 27 sites | 243 | `"parameter"`, a keyword | `simple_identifier` | a highlighter paints keywords as keywords |

That last row generalises: `wire` (53 sites), `output` (17), `input` (11),
`reg` (5) and `endtask` (1) are read the same way, **610 bytes of keyword that
tree-sitter's recovery lexes as identifiers**. `simple_identifier` is a real
PATTERN rule in the grammar, not a hidden wrapper, so this is a genuine
disagreement about what the token is and outliner has it right.

Tracked by `collate.py adjudicated`, which exits 1 the moment any of those spans
stops reading the way this table says.

## Gap — where outliner is confidently wrong inside the same region

Same file, same instrument, other direction. Each is a smallest-failing-input
handover.

| span | outliner | tree-sitter | mechanism | owner |
|---|---|---|---|---|
| `[14341,14359)` | `variable_decl_assignment` | `variable_lvalue` | the LHS of a nonblocking assignment read as a declaration with an initialiser; "find every write to this signal" reads it as a declaration site | verilog grammar lane |
| `[16323,16328)` | `unpacked_dimension` | `select1` | a part-select inside an expression read as an array bound in a declaration — and outliner gets the *same shape* right at `[17707,17712)`, so this is an inconsistency, not a missing rule | verilog grammar lane |
| `[12060,12155)` | `net_declaration`, extent dropping the `assign` | `continuous_assign [11928,12155)` | `continuous_assign` is not reachable from `package_or_generate_item_declaration`; wrong name and wrong extent | verilog grammar lane |
| `[4654,4676)` | `simple_identifier` starting one byte late | `simple_identifier [4653,4676)` | outliner cuts the leading `r` off `rvfi_csr_minstret_wmask`; a rename refactor driven by these extents corrupts the identifier | `src/kernel/lex/` |

And two where nobody wins: `[83841,85029)` (1,188B, module instantiation read as
a class type by both) and `[8996,9023)` (a continuous assignment at module
scope, called a declaration by outliner and a procedural statement by
tree-sitter — both illegal there). 123 of outliner's roots on this file sit in
the second pairing.

## Gap — the honesty axis, and it is not close

The amendment's question: when a file does not parse cleanly, which system tells
a consumer more truthfully *where* and *how much* is untrustworthy?

`collate.py honesty` measures it as **flag recall** — of the bytes we know a
parser reads wrong, how many lie inside something it marks untrustworthy.

```
26,203 bytes outliner reads wrong where the oracle is sound
     0 of them are flagged                              recall 0.00
```

**That is an identity, not a score, and it is the worst possible answer.**
Misread bytes are inside `built`; `damage` is everything outside `built`; the
two sets cannot intersect. So outliner's structural channel can never mark a
misreading, on any grammar, at any time, for as long as the board is defined
this way. `collate.py prove` asserts the intersection is empty rather than
assuming it, so if the buckets ever overlap this lane says so instead of
quietly reporting a better number.

php is the exhibit. Tree-sitter flags **0 bytes** of `Str.php` — it does not
need to, it parses the file. Outliner misreads **25,338** of them, marks none,
and the board reports **87.2% standing**. A consumer handed that tree has no
signal at all that 37% of the file is fiction.

The one place outliner is more honest is a channel no tree walker reads. On the
nine-byte specimen `double-quoted-string.php` it says, on stderr:

```
php: blind to 12 externally scanned terminal(s)
unexpected (?:\\?[^'\\]+) at 12 in state 68, 5 roots, mended 1 over 1B
php: lexer on (?:\\?[^'\\]+) in state 68 [no stand-in for encapsed_string_chars,
     admitted by shift]: ...
```

That is a better diagnosis than an `ERROR` node — it names the terminal, the
state, the offset, and which half of the row admitted it. It goes to stderr, and
it names 16 of 29 files. An editor drawing a selection reads the tree.

**Labelled: gap on the tree channel (the one consumers read), improvement on the
diagnostic channel (the one a grammar author reads).** The two are not
interchangeable and folding them into one row would be flattery.

## The instrument I trust least, with the demonstration

Mine. `collate.py disputed` compares the two trees byte by byte over the deepest
node covering each byte, and on `picorv32.v` it reports:

```
built 30,720   agree 20,138   regrouped 180   relabelled 634   interstice 8,996
               → 96.1% agreement over what it could judge
```

96.1% agreement, on the file both parsers get badly wrong. Here is the same
instrument run over the exact spans the hand adjudication scored `neither`:

```
[83841,85029)  1188B  module instantiation — BOTH call it class_type
   agree 686   regrouped 0   relabelled 0   interstice 502   silent 0
   → the byte comparison calls 57.7% of it agreement, and 0% disagreement

[8996,9023)      27B  continuous assign — BOTH wrong, in different ways
   agree 16    regrouped 0   relabelled 0   interstice 11    silent 0
   → 59.3% agreement, 0% disagreement
```

**A byte-indexed deepest-node comparison inside a recovery region measures the
two lexers, not the two trees.** Both parsers tokenise `picorv32.v` almost
identically; they disagree about every construct built on top of those tokens,
and the widest construct they *agree* on is one they are both wrong about. Any
headline built on that 96.1% is a claim about agreement between two wrong
answers.

This is P7 firing, on the first numeric run, in the flattering direction, on my
own instrument. It fired a second time on the cost lane — see Result 2, Q8.

So: **`disputed` is evidence for a hand adjudication and is never a verdict.**
The only correctness claims in this lane that count are the twenty in
`verdicts.toml`, because those were read against the language's grammar by a
human who can be disagreed with, span by span.

## Reproducing

```bash
python3 tool/pin.py build collate                 # or use the pin recorded above
export OUTLINER_BIN=.local/pin/collate/bin/outliner
python3 tool/collate.py refusal                   # the census, all thirty
python3 tool/collate.py honesty                   # flag recall, both sides
python3 tool/collate.py disputed --grammar=verilog --top=8
python3 tool/collate.py adjudicated               # exits 1 on any drifted verdict
python3 tool/collate.py prove                     # every check, asked to say no
python3 tool/collate.py probe --grammar=verilog --span=83841:85029
```

`prove` is the anti-vacuity: it corrupts a verdict in memory and requires the
drift check to catch it, requires the P4 identity to hold, requires the honesty
verb to find php's misreadings at all, and requires the noise guard in Result 2
to refuse a sub-millisecond slope. All seven pass, and each was watched failing
first.

## Limits

- **The oracle is one pin.** Every "tree-sitter is right" verdict is a claim
  about tree-sitter 0.26.11 generated from *our* copy of the grammar. Where
  upstream ships a different `grammar.json`, the oracle differs.
- **20 verdicts is a sample, chosen by me**, weighted toward wide roots and
  frequent pairs. It is not a rate.
- **`misread` here is lower than `plumb`'s `regrouped`** (26,203 against 33,634)
  because this instrument reads each grammar's own rules to tell a real terminal
  from a childless wrapper node and scores the latter as node shaping. That
  makes it a tighter floor, not a different opinion.
- **yaml is absent from every table** because tree-sitter cannot build it here.
  Twenty-nine grammars, not thirty.
