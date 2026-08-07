# encapsed — php's 40,995-byte `text` node

php was the largest crooked row in the corpus and the ugliest shape on the
board: 40,995 of its 67,845 bytes sat under a single `text` node while
`standing.py` read the grammar at **87.2%**. A system claiming success over its
own failure.

**It is gone.** `Str.php` reads `accepted, 1 root`, php stands at 100.0%, and
against tree-sitter's derivation all 67,845 bytes are square — the row goes
from the worst on the board (67.8% crooked) to 0.0%, and nothing else moves.

The fix seats four of php's twelve externals as a `marrow.Family`:
`encapsed_string_chars`, `execution_string_chars`, and each one's
`_after_variable` twin. They are four rows of data behind one walk, because
php's `scan_encapsed_part_string` serves them all and the two parameters that
vary — `is_after_variable`, `is_execution_string` — are never carried. The
parse state supplies both by naming one terminal rather than another.

**The mechanism is php's; the seam is shared.** One change, one grammar — see
RESULT-4 and RESULT-5 for the two candidate pairings, one of which was proposed
mid-lane as 66,700 bytes and is not real.

Predictions were written before the measurement that judges them, each naming
the number that would kill it; results are in the matching `RESULT-n-*.md`.

| # | Prediction | Verdict | Result |
|---|---|---|---|
| 1 | The `text` node is one un-lexable `"` and the mend behind it | held, with a correction that matters | [RESULT-1](RESULT-1-mechanism.md) |
| 2 | The seam is a `marrow` roster, not a `fence` | held | [RESULT-2](RESULT-2-seam.md) |
| 3 | What the board and `rack` do either side | **3 of 5 held, 2 failed** | [RESULT-3](RESULT-3-numbers.md) |
| 4 | Whether one change moves four grammars | shape right, **two of three legs wrong** | [RESULT-4](RESULT-4-shared.md) |
| 5 | elixir's 25,704 bytes are not this fix | held | [RESULT-5](RESULT-5-elixir.md) |
| — | the instrument I trust least, broken on purpose | — | [RESULT-6](RESULT-6-instrument.md) |

## What is deliberately not here

Two of the six terminals that C function serves — the heredoc pair — are still
blind. With `is_heredoc` true its first statement reads `scanner->heredocs`, a
stack of tags one token pushes and another spends. That is carried state,
which is `fence`'s animal, and seating it on a stateless walk would be the
`marrow/kotlin_block` defect again. `research/joinery/specimen/php/
heredoc-still-blind.php` is the handover, and RESULT-6 is the story of that
specimen failing to be the guard I claimed it was.

## The pins every number here was taken against

A path is not a version in this tree, and two pinned binaries sharing an
`JOINTS_WORK` will measure one side twice — always flatteringly. So: both
halves named, and each arm given its own work directory from empty.

| Half | What | Digest |
|---|---|---|
| before | `.local/pin/php-before/bin/joints` | `93513d7c8`, tree `986eb8ece` |
| after | `.local/pin/php-after/bin/joints` | `3aeaca700`, tree `c34fdd082` |
| falsifier | `.local/pin/php-widened/bin/joints` | `17dda9b57`, tree `ccfefc0bc` — deliberately wrong, see RESULT-6 |
| oracle | `attest.py freeze encapsed` | php `db2f75824`, tree-sitter 0.26.11 |

The oracle is frozen with `tool/attest.py`, which landed mid-lane and replaces
the hand-recorded dylib digests this file used to carry. `rack` now prints
which oracle answered on every report.

**Folio check.** Both arms minted their own folios into
`.local/work-php-{before,after}`; all 30 came out byte-identical, including
php's. So the seating lives in the binary and not the pressed table, and the
shared-work-directory hazard could not have laundered this particular
before/after. Obeying the rule cost nothing and turned "no collateral" from an
assumption into a measurement.
