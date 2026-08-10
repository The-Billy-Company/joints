`tool/bench.baseline.json` gains the eight-scanner grammars, so the numbers
rung 5 moved cannot silently move back.

Before this the baseline guarded eleven grammars, and every one of them was a
grammar where *neither* side runs an external scanner. The case the customaries
exist for was the one case the tracked bench could not see - which is how
markdown sat at 954 ns/byte without anything going red.

Now guarded, on top of what was there: four throughput rows (elixir, html,
markdown, scala), the same four on `startup` and `memory`, seven more on
`artifact` and `press`, and two on `incremental` - including
`elixir @quoted_content`, the keystroke inside a heredoc, at 1,541 us and 0.65x.

`record` rewrites every row rather than merging, so a regression in an existing
row would be laundered into the new baseline by the act of recording it. The
nine that were already there were therefore held to the *old* baseline first,
with the new code in place - all nine passed, the widest at +2.4% - and only
then re-recorded. Recording before verifying would have proved nothing.

`install` moves from `x11` to `x18` for the same reason the rest of this
changed: the folio these axes are measured over now holds the eight as well.

yaml is still absent from every axis. Its oracle does not build - `scanner.c`
reaches `schema.core.c` through a macro that the include follower in
`differential.beside` cannot see - so there is nothing to hold it against.
