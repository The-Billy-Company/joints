# cpp - the grammar that looks finished and is wrong

C++ reads **411 bytes of damage over 36 roots** on the live board, which is one
of the healthiest columns in the corpus, and **59.5% crooked with 29.4% bracket
recall** against the tree-sitter oracle, which is the worst row on it. Both are
true of the same parse.

**One token explains the whole gap.** `ledger.cpp` contains exactly one call
whose callee is a bare identifier; at that call we take the *declaration*
reading, wall on its first argument, and every one of the 698 judged bytes after
byte 690 is charged. Not one byte after the wall is square, on either arm
measured.

**The mechanism is arity, not ranking.** Three readings of a bare `identifier`
complete at once in state 2572 - `_declarator`, `type_specifier`, `expression` -
and a contested cell records one loser. The runtime forks correctly into the two
readings it is given; both are declarations. The reading tree-sitter takes was
never a strand, which is also why the lane that made the runtime consult dynamic
precedence moved cpp zero bytes.

Full diagnosis, evidence, price and the corpus scan: **[`RESULT-1-crooked.md`](RESULT-1-crooked.md)**.
Predictions written before measuring: [`PREDICTION-1-crooked.md`](PREDICTION-1-crooked.md), scored 4 of 9 in the result.

## What is here

| file | what it does |
|---|---|
| `PREDICTION-1-crooked.md` | nine falsifiable claims, written before any parse was run |
| `RESULT-1-crooked.md` | the diagnosis, the attribution, the price, and the honest scoring |
| `vexing.py` | fourteen minimal pairs, each about one token from its neighbour - locates *which token* forks the parse. `--tree N` prints one probe's forest beside the oracle's |
| `confuse.py` | the confusion matrix, the unbuilt frames, an independent recall, the charge split at a byte (`--verb where --cut N`), and what the fork is worth (`--verb price`) |
| `blind.py` | one row per grammar with `damage` and `square` side by side, plus each grammar's declared-conflict census - the scan for other rows with this signature |

Every script is read-only on `src/` and on `tool/`, writes nothing outside
stdout and `.local/`, and drives `plumb.read` so its population is the population
`rack.py` judges rather than a second one that agrees today.

## Running them

```sh
eval "$(python3 tool/pin.py arm <name>)"     # read the `oracle: N of N` line first
python3 research/joinery/cpp/vexing.py
python3 research/joinery/cpp/vexing.py --tree 0        # the nineteen-byte exhibit
python3 research/joinery/cpp/confuse.py --verb price
python3 tool/rack.py run --json > board.json && python3 research/joinery/cpp/blind.py board.json
```

## What this lane did not do

Nothing under `src/press/`, `src/kernel/quire/` or `src/kernel/lex/` was touched.
The recommended repair - letting a contested cell carry more than one dropped
reading, so a three-way declared conflict forks three ways - is written down in
the result with its evidence, its blast radius (17 of 30 board rows are provably
bit-identical afterwards, and only thirteen can move at all) and the two things
to measure before shipping it. It belongs to whoever owns `settle.Conflict`.
