# Result 1 — ocaml could not lex a byte, and no board could see it

Treatment arm `joints aece1211e` · tree `a9353c78b` (pin) · oracle `d85e736fa`
(30 of 30 live, 30 attributed). Control arm `joints d95f68e4a` · tree
`b8757cdcc` · same oracle `d85e736fa` (30 of 30 live, 30 attributed).
`still against kotlin-dot ocaml-orphan --mine src/kernel/lex/scanner.zig --inert`
reads **comparable**: one file differs and this lane claims it.

This is an equivalence result. It moves no bytes, and the point is which
instrument was lying about that.

## What was wrong

`joints lex upstream/grammars/ocaml.json` returns **0 tokens over 16,878
bytes** on ocaml's own corpus file, in 2 microseconds. It returns 0 tokens on a
Python file too, and on a one-byte file, and on anything else. The other
twenty-nine grammars lex normally. Ocaml lexed nothing at all, ever, and had
been doing so silently.

Meanwhile ocaml *parses* - 167 roots, 7,439 nodes - so no board reading
`built` / `square` / `crooked` could have caught this, and none did.

## The mechanism

The two are consistent because the scanner keeps two different slates, and only
one of them was empty.

`reach` picks the slate on whether the caller brought a state:

```zig
const allow = if (expected) |e| ... else if (fresh) &rank.all else &rank.after;
```

A caller with a state is narrowed by its own permission set. A caller without
one gets the unconditional cuts - `rank.all` / `rank.after`, and `whole` /
`whole_after` for `spot`. Those cuts run a filter the state-directed path does
not: terminals reachable *only* through an extra the parser never reduces, which
therefore no state can name. Without it rust's `line_comment` carries a bare
`.*` and a state-free ask hands back the first line of any rust file as one
token.

The filter decided "reachable only through an extra" by complement. Close over
the extra to get `within`, then keep any terminal spelled by a production whose
left side sits *outside* that closure. That is sound while the closure is small,
which is true of every extra that motivated it - a comment reaches nothing - and
false the moment one is not.

Ocaml spells `attribute` as an extra:

```
attribute         ->  /\[@/ attribute_id attribute_payload? ']'
attribute_payload ->  _structure | ':' … | '?' _pattern …
```

The payload is `_structure`, which is the entire language. So the closure from
that one extra is every nonterminal ocaml has, no production is left outside it,
the complement comes back empty, and **every terminal is orphaned**. Both
state-free cuts end up holding nothing, so every state-free ask returns a stray.

## Why that is not a cosmetic bug

`blame` is a state-free caller, and it is the one that decides what kind of wall
a refusal was. Its own docstring names the distinction:

> `unexpected` is an unshiftable reading, `stray` is a byte nothing in the
> grammar lexes.

Tier one asks with the table's permission. Tier two takes the filter off and
asks the whole grammar - and that tier is a state-free ask, so for ocaml it
returned nothing every time. Every ocaml wall came back as tier two's failure
case, which in `gather` is a different recovery path:

```zig
.stray => |off| x.blame(bytes, off) orelse {
    // No terminal begins here under any state, so there is no token to delete.
    const stop: quire.Stop = .{ .stray = off };
    if (try x.mended(stop, x.first().top, off, word(bytes, off))) continue;
```

A named token goes on to `absorb`, and then to `supply`, which can decide the
token was fine and something in front of it was missing. A `null` skips both and
deletes a whole word on the spot. Ocaml never got the ordinary path at any wall
in any file.

## The fix

"An ordinary rule" is the closure from the start symbol, and it has to be
computed rather than inferred from a complement. A nonterminal the parse reaches
on its own is named by some state whatever an extra also does with it, so
subtracting the reachable set leaves `within` holding only what is genuinely
reachable through an extra and nowhere else. An extra that is *also* spelled in
an ordinary rule keeps its terminals for the same reason, with no case of its
own.

The narrowing stays a narrowing. `/\[@/` opens ocaml's attribute and nothing
else, so it is still orphaned and a file starting with one still reads as a
stray to a caller with no state to admit it.

## What it bought

Two rows moved out of thirty, and they are the only two grammars whose extra
carries a payload that re-enters the main grammar:

| grammar | tokens before | tokens after | covered before | covered after | of bytes |
|---|---:|---:|---:|---:|---:|
| ocaml | 0 | 60 | 0 | 16,878 | 16,878 |
| php | 1,621 | 54 | 67,845 | 67,845 | 67,845 |

Ocaml's verdict changes from a lexer verdict to a state verdict, which is what
it always was:

```
before   stray byte at 1996, 167 roots, mended 28 over 28B
after    unexpected (?:[^\'\r\n]) at 1996 in state 155, 167 roots,
         mended 28 over 28B, supplied 0, spurned 14
```

Byte 1996 is the `@` of `let[@tail_mod_cons] rec init`. It is not a byte nothing
lexes - `let x = [1] @ [2]` parses fine on both arms - so `stray` was the wrong
name for it on every board that has ever been taken here.

Php's count falls because its slate got *bigger*: php's `text` terminal is
greedy, it is genuinely part of the grammar, and a state-free ask has nothing to
stop it. Coverage is 100% either way. That is the honest answer to a question
asked without a state, and it is what the verb's own banner warns about.

## What it did not buy

**Nothing.** All 30 audit rows are byte-identical across the arms:

| bucket | before | after | delta |
|---|---:|---:|---:|
| built | 407,367 | 407,367 | 0 |
| square | 336,717 | 336,717 | 0 |
| crooked | 33,653 | 33,653 | 0 |
| soft | 10,620 | 10,620 | 0 |
| unframed | 25,963 | 25,963 | 0 |
| unaudited | 414 | 414 | 0 |

Ocaml keeps its 167 roots, its 28 mends over 28 bytes, and its 2,182 damage. The
restored `supply` was asked and declined - `supplied 0` - so the degraded path
had been reaching the same tree by a worse route.

I am recording this as a result rather than folding it into a bigger change
because the equivalence is the finding. A wall that was being reported as a
lexer defect for the whole life of this board is a state defect, and the census
routes work by that name.

## The regression guard

`scanner_test.zig` grows one test on ocaml's shape reduced to four rules: a
nonterminal extra whose body re-enters the start rule. Falsified through the CLI
on both arms before it was written, so it fails for the reason claimed:

```
before   t: 0 tokens over 7 bytes (0 covered)   stray byte at 0
after    t: 2 tokens over 7 bytes (6 covered)
```

Suite is 392 passed, 0 skipped, 0 failed, 0 leaked in one process.

## What the next lane inherits

Ocaml's real wall is now visible and it is not a spelling. `attribute` is a
**nonterminal extra** - `unskippable`, in the scanner's word, "a token we can
produce and then cannot get out of the way of". `let[@tail_mod_cons] rec f`
needs the whole `[@…]` subtree stepped over mid-binding, and there is no seat
that steps over a rule. That is a feature, not a row in a table, and it is
shared with php's `text_interpolation`.

The four grammars from `kotlin/RESULT-1-dot.md` are all still open and none of
them is this: scala `_simple_string_start`, ruby `heredoc_beginning`, bash
`_concat`, haskell `_cond_qual_dot`.

## What I trust least

**The php row is a judgement call I made on one file.** Php's state-free lex got
coarser - 1,621 tokens to 54 - and I am calling that more honest rather than
worse, on the argument that the terminals now in its cut are ones php's states
genuinely name. Php parses whole, so `blame` never runs there and nothing in its
tree can contradict me. If someone is using `joints lex` on php as a
tokenizer, this lane made their day worse and the board cannot see that either.

**"Only two grammars moved" is measured, "only two grammars *could* move" is
argued.** I checked reachability from the start symbol for php and ocaml and
swept the lex output for all thirty. I did not enumerate which of the thirty
have an unskippable extra at all, because no surface reports one - the `grammar`
verb prints an extras count and not this. So the blast radius is bounded by
measurement on this corpus, not by a property.

**No byte moved, so nothing downstream corroborates the fix.** The whole
evidence that the new cut is *right* rather than merely non-empty is the 60
tokens covering ocaml's file and the minimal fixture. A wrong-but-populated cut
would look identical on every board in this repo, because the only in-tree
consumer that reads it is a diagnostic.
