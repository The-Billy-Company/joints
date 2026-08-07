ocaml could not lex a byte, and no board could see it.

Treatment `joints aece1211e` · tree `a9353c78b` (pin) · oracle `d85e736fa`
(30 of 30 live, 30 attributed), against control `joints d95f68e4a` · tree
`b8757cdcc` on the same oracle. `still against --inert` reads comparable: one
file differs and this lane claims it.

`joints lex upstream/grammars/ocaml.json` returned 0 tokens over 16,878 bytes,
and 0 tokens over anything else, while ocaml parsed normally at 167 roots. Both
can be true because the scanner keeps two slates and only the state-free one was
empty. Its filter drops terminals reachable only through an extra the parser
never reduces - without it rust's `line_comment` eats the first line of every
rust file - and it decided "only" by complement: keep a terminal if some
production outside the extra's closure spells it. That holds while the closure
is small, which is true of every extra that motivated it and false of ocaml's
`attribute`, whose payload is `_structure`, the whole language. No production is
left outside, nothing is kept, every terminal is orphaned.

The cost was not the verb. `blame`'s second tier is a state-free ask, and it is
what separates "no terminal lexes here" from "one lexes and no reading can use
it". It returned nothing for ocaml every time, so every ocaml wall filed as a
stray byte and took the path that deletes a word instead of the one that runs
`absorb` and then `supply`. Byte 1996 of `list.ml` is the `@` of
`let[@tail_mod_cons]`, and `let x = [1] @ [2]` parses fine - it was never a
stray.

Now the closure from the start symbol is computed rather than inferred from a
complement, so a nonterminal the parse reaches on its own keeps its terminals
whatever an extra also does with it. The narrowing stays one: `/\[@/` opens the
attribute and nothing else, so it is still dropped.

Ocaml goes 0 -> 60 tokens covering all 16,878 bytes and its verdict goes from
`stray byte at 1996` to `unexpected … at 1996 in state 155`. Php's cut, wrong
the same way, gets its real slate back. All 30 audit rows are byte-identical and
every corpus bucket is unchanged - this buys no bytes, and the equivalence is
the finding: a wall reported as a lexer defect for the life of this board is a
state defect, and the census routes work by that name.

`research/joinery/ocaml/RESULT-1-cuts.md` has the arm comparison, the mechanism,
ocaml's real remaining wall (`attribute` is a nonterminal extra no seat can step
over), and what I trust least - chiefly that php's coarser state-free lex is a
judgement call no board in this repo can contradict.
