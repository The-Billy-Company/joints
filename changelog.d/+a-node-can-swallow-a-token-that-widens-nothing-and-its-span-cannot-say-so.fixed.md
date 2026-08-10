A lift hands a subtree over and resumes scanning at the end of its span, so the
old parse's answer standing at that offset is the one the resumed parse is about
to be handed. If that answer covered no bytes, the tree cannot say whose it was.

A hidden zero-width terminal at the tail of a production widens no span. So a
node that already swallowed one looks exactly like a node that stops in front of
one the enclosing production is still owed, and the two want opposite things: the
first must not be offered it again, the second must. yaml's block scalar is the
first. `_r_blk_str -> … _bl` folds the blank line into the value, the value's
span stops nine bytes short of it, and a lift resuming at the span's end offered
the `_bl` a second time to a state already holding the whole scalar:

    lift _r_blk_str_val spread 5466..5661 kids=1 here=411 to=791
    tok 5670..5670 sym 110 from 791 -> 482
    joints: unexpected _b_sgl_pln_str_blk at 5670 in state 545

Where a cold parse reads the same `_bl` from state 550 and goes to 551.

`Graft.Stance` already recorded, per ask, where the scan stood; it now records
whether the answer had extent, and a lift is refused when the answer resuming at
its end had none. One bit per ask, no new pass, and it is in the stance ledger
rather than the tree because the ledger is the only place the fact survives - a
span is a visible extent by construction.

It reads as a fifth refusal (`edge=`) beside the four already in the weave line,
and it should be the whole story on grammars whose hidden terminals are
zero-width - 248 of yaml's refusals, 5 of python's, 3 of markdown's - and exactly
zero on grammars with none, which is what html and latex report.

The cost is real and it is one ordinary re-read: yaml declines a lift it cannot
prove and lexes those nine bytes again. The alternative was a parse error nine
bytes later, so this is not a trade I had to think about.

The same span/derivation gap is why a renamed node over a *hidden* symbol is now
spread rather than lifted whole (`Verdict.spread`): the node in the old tree is a
wrapper the rename built, and whether there should be one here is the new
parent's call, so the parent gets the run and decides again. Lifting the wrapper
gets it wrapped twice. Together the two took markdown from zero lifts to 12 over
1,402 bytes - `gain` 1x to 8x - and yaml from zero to five.

`research/keystroke/abide.py` reads 17 of 30 grammars agreeing element-for-element
with a cold parse after all 24 edits, and it is the same 17, grammar for grammar
and count for count, with the spread stood down - so the 13 that disagree are
somebody else's lane and were before this change. Of the eight books, five
(markdown, yaml, scala, html, swift) are in the 17; elixir, haskell and kotlin are
three of the 13.
