# Result 1 — the 40,995-byte `text` node, explained

**Prediction 1 held on all three falsifiers, with one correction to its
wording that turns out to be the interesting part.**

## What the node is

`Str.php` is 67,845 bytes. Byte 26,848 is the `"` opening the first
double-quoted string in the file. php's grammar hands that string's interior
to an external scanner as `encapsed_string_chars`, this tree seated none of
php's twelve externals, so the token the state was waiting for could not be
made by any lexer here. The mend fired once, over one byte, and the parser
re-entered at `program`.

`program`'s other production is `text` — php's node for inline HTML *outside*
`<?php`. Its pattern is `[^\s<][^<]*` repeated, which matches essentially
anything. So the remaining 40,995 bytes of a PHP source file were read as raw
HTML, under a top-level node with a child, and every one of them was counted
`built`. That is the whole of the 87.2%-standing-over-its-own-failure shape:
the recovery does not orphan the remainder, it **claims** it.

## The correction, and it is the brief's own warning coming true

Prediction 1 said the node "stems from a single un-lexable `\"` at 26848".
The refusal outliner actually prints is:

```
unexpected / at 26849 in state 68
[no stand-in for encapsed_string_chars, admitted by shift]
```

The **refused** terminal is `(?:\\?[^'\\]+)` — `string_content`'s pattern,
which belongs to *single*-quoted strings — and the byte named is 26,849, the
`/` **after** the quote. The token that is actually missing is
`encapsed_string_chars`, and it appears only in the bracketed stand-in clause.

That is exactly the adjudication lane's warning arriving in my own file: *the
wall's terminal is probably not the token that failed.* Anyone reading the
first line of that message and going to look at php's `string_content` rule
would have spent the day in the wrong production. `inquest`'s `admitted by
shift` half was the trustworthy part, as its own header claims.

## The three falsifiers

**Locality.** I copied `Str.php` and replaced only the first double-quoted
string with a single-quoted one of identical length. The `text` node did not
shrink or vanish — it *moved*, to the next double-quoted string. So the defect
is per-occurrence and the 40,995 bytes are the tail after the first one, not a
property of that particular string.

**Miniature.** Six lines of php reproduce it whole:

```php
<?php
$x = f("a");
```

Before: `text [15, 19)`, 7 roots, 1 mend. After: `accepted, 1 root`.

**Innocence.** The same file with `'a'` instead of `"a"` parsed clean on both
arms and is unchanged by the fix. A single-quoted string's interior is a
pattern php lexes itself, so it never asks the scanner anything.

## What it cost, in the corpus's own terms

The whole file now reads `accepted, 1 root`, 100.0% standing, and — measured
against tree-sitter's derivation — **67,845 of 67,845 bytes square**. The
`text` node does not shrink. It is gone.
