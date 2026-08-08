The scanner's troupe test opened `upstream/grammars` with a bare `try`, and the
corpus is fetched rather than committed. Every other corpus test in the suite skips
when it is absent; this one turned a tree that had not fetched yet into a red
suite - which is what a fresh CI checkout is, and what a first clone is.
