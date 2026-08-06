# semi — the statement separator three languages hand to a scanner

Swift, kotlin and scala each give their statement or member separator to an
external scanner, and outliner could not read any of them. Together that was
16,809 unbound bytes, 12.5% of the board. This folder is the lane that seated
two of the three and wrote down why the third could not be.

The short version: swift went **27.4% -> 81.2% standing**, kotlin's unbound fell
67%, scala is byte-identical and declined on purpose, and the board's unbound
fell 134,630 -> 121,918. Nodes described rose 2,881 and bare leaves fell 1,642,
which is how you tell this from a policy that reads less.

## Read in this order

| File | What it holds |
|---|---|
| `PREDICTION-1-cohort.md` -> `RESULT-1-cohort.md` | Whether `outside.Provision` really refuses a partial cohort. It does not, and that reframed the lane before any code was written. |
| `PREDICTION-2-mechanism.md` -> `CLASSIFICATION.md` | All 68 externals (swift 33, kotlin 10, scala 25) classified by mechanism. The axis is real; the place to ask it is `serialize`, not `grammar.json`. Its third section also holds prediction 3, on the co-admission population - the one that got falsified by the test it named for itself. |
| `RESULT-2-seated.md` | What was built, the board read as the brief demands, the predictions that failed, and the instrument trusted least. |

## The instruments here

| Script | Question |
|---|---|
| `mechanism.py` -> `mechanism.json` | Per-external derivation: what memory would a stand-in need, and is the spelling reachable from the grammar? |
| `population.py` -> `population.json` | What company a terminal keeps in an LR row, **split into the expected set and the shiftable subset** - those differ by 85x and conflating them is what went wrong the first time. |
| `coadmit.py` -> `coadmit.json` | Superseded by `population.py`, kept only as the record of that wrong answer. |
| `probe/` | Minimum-scale swift files. One member versus two, one statement versus two, a written `;`, a `!`. Four-line files discriminate where a 28 KB file cannot. |
| `baseline-board.json` / `treatment-board.json` | `standing.py --json` either side of the change, same commit, so the diff is attributable. |

## What is still open

Swift keeps 12 blind terminals - the raw-string family and nesting comments need
memory, `_custom_operator` is a whole-match filter, `_bang_custom` is a question
about the parse table that is wrong in exactly one of 3,416 states. Kotlin's
string troupe is carried state. Scala wants a layout troupe, because Scala 3
infers a newline against the indentation region it sits in, and a region is a
stack. None of those is a table row, and each fails closed already: a blind
external is in no action row, so the parse stops with a located wall instead of
accepting a plausible tree.
