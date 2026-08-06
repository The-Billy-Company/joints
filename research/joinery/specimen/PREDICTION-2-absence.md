# Prediction 2 — what the corpus does not contain

Written before `tool/absent.py` exists and before any absence sweep has been
run. Every claim names the measurement that falsifies it.

## The measurements already taken

Only these, and they are the ground the predictions stand on:

- The coverage gate today, against a pin of this tree
  (`.local/pin/absent`, tree `aa9dd8dc0d5d`): **461 declared, 263 seated, 225
  hidden, 38 visible, 23 exercised.** The brief quotes 252/36/21; a sibling's
  kotlin and swift seating has landed since, so the gap I inherit is **15
  visible externals no file in this tree reaches**, not fifteen of thirty-six.
- The specimen tier today: **22 specimens over 7 grammars, 15 sound.**
- A harvest of every `STRING` and `PATTERN` leaf out of all thirty
  `grammar.json` files: **5,284 distinct literal spellings**, of which 54 (1.0%)
  will not compile as a Python regex and 32 match the empty string. yaml
  declares **zero** — its rules are all externals.

Nothing has been asked of the corpus yet.

## The instrument I am about to build

For each grammar, two independent readings of "the corpus never presents this":

**lexical absence** — a literal spelling the grammar itself declares, whose
bytes never occur in that grammar's corpus file. A substring search for a
`STRING`, a regex search for a `PATTERN`. It needs no parser at all, which is
the point: it is the only reading available on the 34,687 bytes where
tree-sitter itself ERRORs and outliner is being graded by nothing.

**structural absence** — a named rule the oracle's own parse of the corpus
never yields a node for. Needs the oracle, so it is missing exactly where the
lexical half is most needed.

Its error direction is declared up front and is the opposite of `exercised`'s:
lexical absence is a **floor on absence**. `/*` inside a string literal counts
as present, so the instrument will never claim the corpus lacks something it
holds, and will sometimes claim it holds something it only mentions.

## P1 — the corpus presents fewer than half of what the grammars spell

**Falsified by:** the tree-wide `present / judgeable` ratio coming back at 0.50
or above.

If a single real file per language reached most of a language's vocabulary, the
Swift case could not have happened, and thirty found files would be a fair
sample of thirty languages. I do not believe they are. I expect something near
35%.

## P2 — Swift's corpus file contains no match for the multiline-comment opener

**Falsified by:** the pattern `[\/]+[*]+` matching anywhere in
`upstream/sources/Chunked.swift`.

This is a retrodiction and it is here as the instrument's calibration, not as a
finding. The one absence in this tree whose consequence is already known is the
one this tool must reproduce on its first run. If it cannot, nothing else it
says is worth reading.

## P3 — a `whole` grammar sits below the corpus median for literal presence

**Falsified by:** every one of the twelve grammars the board reads at 100.0%
standing coming back at or above the median presence ratio.

The board's twelve perfect rows are the claim under audit. If a grammar can
read 100.0% standing off a file that reaches *less* of its own vocabulary than
average, then "whole" is partly a statement about the file and the board cannot
tell that from correctness. I expect at least one, and I expect it to be one of
the nine nobody has found a defect in.

## P4 — three or more of the fifteen unexercised externals resist an authored input

**Falsified by:** all fifteen becoming exercised once a specimen presents them,
or fewer than three resisting.

A construct that will not produce its node when a file is *built* to contain it
is a defect, not a corpus gap, and separating those two is the whole reason the
specimen tier is worth more than the gate. If every one of the fifteen lights
up on contact, the gap was pure corpus silence and the gate alone was enough.

## P5 — two or more of the fifteen cannot be witnessed even when correct

**Falsified by:** every visible external that parses correctly appearing as a
node in `parse --ranges --all`.

This one contradicts the brief. `visible` is defined as "the external's name
does not start with `_`", and that is a proxy for "tree-sitter will emit a node
for it". The proxy has at least two other ways to fail — a grammar can `inline`
a rule, and a `supertypes` entry is replaced by its member — so I expect the
38-visible denominator to be an overcount and the 23-of-38 ratio to be measuring
partly the instrument. If so the gate needs a third column and the fix is worth
more than the specimens.

## P6 — a specimen finds a real defect in a grammar the board calls whole

**Falsified by:** every specimen authored against the nine unexamined `whole`
grammars holding every claim.

Twelve grammars report zero damage; three are known wrong. The honest position
on the other nine is that nobody has asked. I am predicting the answer is not
nine clean.

## P7 — innocent controls will outnumber guilty ones

**Falsified by:** more than half of the specimens I author failing a claim.

A tier made only of failures proves nothing about the passing rows, and a tier
where most things fail usually means I wrote the claims wrong rather than that
the parser is that broken. I expect roughly the ratio the seventeen-suspect
lane got: about a third guilty.

## What I expect to be wrong about

P3 and P5. P3 asks a ratio to line up with a story and ratios rarely do. P5 is
a claim about tree-sitter's node-emission rules made from reading two fields of
a JSON file, which is the same reasoning that produced `seated 0` for
twenty-three grammars the first time somebody trusted a field here.
