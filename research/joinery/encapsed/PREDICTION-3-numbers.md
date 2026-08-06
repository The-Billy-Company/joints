# Prediction 3 — what the board and `rack` should do either side

Written before the change compiles. Every number below is from the pin named in
this folder's README, so a reader can re-take them.

## Before

`tool/standing.py --set=all`, php row:

```
php  held-out  67845  99.1% cover  87.2% stand  59146 built  8120 strewn
                8091 orphan  29 rubble  579 spoil  8699 damage  119 roots  50 leaves
```

`tool/rack.py run php`:

```
662 square + 0 renamed + 40130 askew + 0 racked + 18354 unframed + 0 unjudged = 59146 built
bracket recall 29.5%
```

Note that `rack` has already moved under me: the brief was written when php
read 25,394 crooked, and the `unframed` split the rack lane added since then
re-priced it. **40,130 + 18,354 is the number I am measuring against**, and if
rack moves again mid-lane I will re-take the before arm rather than compare
across two rack builds.

## Predictions

1. **The `text` node goes to zero.** Not "shrinks" — the production is only
   reachable at the top of `program` or after a `?>`, and `Str.php` contains no
   `?>`. Falsifier: any `text` node survives in the after tree.

2. **`square` rises by more than 30,000 bytes and `askew` falls by more than
   30,000.** The 40,995 bytes under `text` are today one flat run of
   anonymous tokens under one wrong parent, so every one of them is askew at
   the deepest node. Falsifier: `askew` falls by less than 30,000, which would
   mean most of those bytes were being adjudicated some other way.

3. **`built` falls while `square` rises**, and that is the *correct* direction.
   php's 40,995 text bytes are counted `built` today, and a real parse of the
   same region will not put every byte under a construct — comments and
   whitespace between statements become `orphan` and `spoil` the way they are
   in every other working grammar. So php's headline `standing` may *drop* from
   87.2%. Falsifier for the change being good: `square` fails to rise. Falsifier
   for this prediction specifically: `built` rises, which would mean the new
   parse is claiming even more than the text node did.

   This is the trap `rack --square` was built for, run in reverse: the guard
   catches a policy that buys `built` and pays `square`, and I am predicting a
   change that pays `built` and buys `square`. If I reported `standing` alone
   this change would look like a regression, and if I reported `square` alone I
   would be hiding the cost.

4. **`bracket recall` rises above 90%.** Recall is node-weighted, so the single
   wide `text` node costs almost nothing there today; 29.5% means the *nodes*
   are missing too, not just mis-parented.

5. **The board's `unbound` for php stays small and `spoil` grows.** php's spoil
   is 579 bytes today because one root covers everything. After the change the
   file is a forest again and the gaps between roots are honest.

## What I predict will NOT move

`execution_string_chars` and `execution_string_chars_after_variable` will be
seated and **never once exercised by the board**: `Str.php` contains zero
backticks. Likewise both heredoc members are left blind and `Str.php` contains
zero `<<<`. So two of the four rows I am adding are, on the corpus, unfalsifiable
— which is exactly the case `research/joinery/specimen/` exists for, and they
get witnesses there or they do not ship as claims.
