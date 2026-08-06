`differential.oracle_build` overwrites `lang/<name>/src/grammar.json`, deletes
`src/tree_sitter/`, deletes `parser.c`, and runs `tree-sitter generate` — in the
directory `differential.py`'s own comment calls *"shared, and locked."* It held
no lock. The lock was the caller's job, and of **twelve call sites nine did
it**: `recover.py` (three), `research/joinery/adjudicate/prepare`, and this
file's own `graft_fields` did not.

Raced deliberately — two processes, one language, different grammar bytes, six
rounds each, lock stood down:

```
5   B grammar=B parser=B ok
3   A grammar=B parser=B ok      ← lane A measured lane B's grammar and called it its own
3   A grammar=A parser=A ok
1   B grammar=A parser=B TORN    ← a grammar.json from A beside a parser.c from B
```

The `TORN` row is the loud one. **The three flattering rows are the defect**:
internally consistent, silent, and about somebody else's grammar. With the lock
inside the function that writes: twelve of twelve consistent, one lane queued
once.

`alone()` is **re-entrant within a process** now, which is what lets the lock
live in the writer instead of in each caller that remembers. `flock` is per open
file description, so a nested acquire on a fresh fd would otherwise wait on a
lock the same process is holding — that is why this was a convention, and why
three callers were able to skip it. A *writer* nested inside a *reader* refuses
instead of deadlocking, because that one is a genuine lock-order fault and is
the deadlock the readers-writer split exists to avoid.

**And a refresh only writes when the bytes differ.** `fetch_scanners` wrote
every scanner with `write_bytes` unconditionally and unlinked the generated
`parser.c` beside it to force a relink; `beside()` did the same to companion
headers without the unlink. Since `attest` digests an oracle by its whole `src/`
and reads its newest mtime to decide whether the library predates it, copying a
file onto its own bytes gives one parser **two identities** and reports every
oracle on the machine as about to change. Every run used to print **28 of 28
`wrote`**, eleven of them unlinking a parser. It now prints `28 same`, and a
`wrote` where nothing changed is a bug visible from the terminal.

That was the whole of the source divergence on this machine. Measured across
**159 oracle source trees over 30 grammars**: two disagree under
`attest.survey` — css over 8 copies, toml over 7 — and **zero disagree on
authored bytes**. Every `grammar.json`, `scanner.c` and companion header is
singular; css's eight of each are one digest apiece.

Four instruments now share one failure mode — `specimen.py`'s defaulted stop
line, `order.py::miss`'s mtime key, `fetch_scanners`' unconditional write, and
this. The shape is **the comparison's setup writes to the thing being
compared**, and what makes it dangerous rather than merely wrong is that
afterwards the two arms are *more alike than they were*, so the error is always
in the direction of agreement and the instrument's own falsifier runs after the
setup that broke it.
