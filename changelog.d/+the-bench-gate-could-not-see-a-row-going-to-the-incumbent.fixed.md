`bench.py verify` held every timing axis with one rule: a percentage band on the
ratio to tree-sitter, 25% wide for throughput because an absolute duration on a
shared laptop is not portable between two afternoons. The band is right and it is
also blind to the only thing the ratio exists to say. cpp went **0.986 to 1.112**
- a row joints held, now tree-sitter's - and `verify` printed `ok` against it and
closed with "14 guarded number(s) held". rust did the same thing on the same run.

Which side of 1.0 a row lands on is a different kind of fact from how far it
moved. Both numbers in a ratio come from the same run on the same machine under
the same load, so the sign survives noise the magnitude does not. `verify` now
watches it separately: a row that was ours and is now the incumbent's fails on
its own, whatever the band says, and a row taken back from tree-sitter is called
out rather than passing silently as an unremarkable `ok`.

**The dead zone is 10% and the first number I picked was wrong.** I took 5% from
the `±` column each run already prints, then noticed that is the spread of
replicates *inside* one run, and the ratio is noisier than that because its two
sides are separate program invocations the OS schedules independently. Two
`verify` runs over one unchanged tree six minutes apart moved python 8.1%, html
6.7%, elixir 5.9% and rust 3.8%. So 5% would have failed on noise, which is how a
gate teaches people to ignore it.

What 10% costs, stated rather than buried: cpp lands at 1.11/1.12/1.13 over three
runs and is called; rust lands at 1.07/1.03/1.02 and is not. rust really did fall
off 0.876 and really is no longer a win, and this gate cannot say so without
flapping. It prints `at parity, was ours` against that row instead of a verdict
it cannot support. Deciding a row that lives within a few percent of parity needs
replicates across runs, which is a different instrument than this one.

The finding it was built on stands on its own: throughput is now **seven rows to
joints and seven to tree-sitter**, and the losses are not scattered - every one
of the five measured grammars whose external scanner keeps state in C is a loss,
and six of the eight without one are wins. cpp is the row that fits neither and
is the cheapest place to start.
