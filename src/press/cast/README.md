# cast - the automaton, before anybody argues about it

Type is *cast* from a matrix. This casts the automaton from the grammar: the
canonical LR(0) collection, the two set problems it needs, and the machinery for
reading the finished thing backwards. Four files, and they read only `copy/`.

What is deliberately **not** here is the LALR lookahead pass. `lalr.zig` sits at
the area root instead, because it consults the conflict machine in `quarrel/`,
and `quarrel/` in turn needs `first`, `lr0`, and `sets` from here. Putting them
in one directory would make that a cycle across directories, which the charter
forbids; keeping them apart makes the dependency a straight line you can read off
the folder names. The layering is not decoration - it is the reason the tangle
that used to live in one flat directory is now four honest ones.

| File | Role |
|---|---|
| `lr0.zig` | The canonical collection - the automaton's shape, before any question of lookahead. |
| `first.zig` | Nullability and FIRST over the whole symbol space, in one fixpoint because they *are* one fixpoint. |
| `sets.zig` | A flat matrix of equal-width bit sets, because LALR spends nearly all of its time taking unions along a relation. |
| `retrace.zig` | Walking the automaton backwards, for the questions that need to know what could have been on the stack. `retrace.Step` is a path step; `Grammar.Step` is a production step, which is why the door above publishes this one under its own name rather than flattening it. |
