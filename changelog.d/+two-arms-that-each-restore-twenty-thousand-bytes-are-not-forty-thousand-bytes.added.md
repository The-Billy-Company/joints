Single-row ablation is the technique this repo attributes regressions with, and
it cannot see a pair. Scala's standing is two seatings cooperating: with either
row out, scala reads identically on both trees **to the byte**, so both of its
own isolation arms report a 12,733-byte regression as zero.

`ablate.py` and `attribute.py` can now build and price a **set**.

The powerset of fourteen rows is 16,369 subsets and almost all of them are
incoherent. `seated()` refuses a cast unless the grammar declares **every**
terminal the row names, so a row can only ever move a grammar in its **candidate
set**, and that set is computable from the roster and the grammars' own
`externals` with nothing built. `ablate.py guests` prints it: nine grammars
reachable, **five of them by two rows and none by three**, so the population is
five arms rather than 16,369. Its own falsifier runs first - every grammar a row
was *measured* to move must be one it can seat, and **zero of fourteen violate
it**; without that the candidate sets are an assumption, not a bound.

`attribute.py pairs` builds each subset, reuses any pin that already exists, and
prints the residual - joint damage minus the sum of the solo arms, which is
exactly what a single-row family cannot observe:

| grammar | rows | joint | sum of solos | residual | |
|---|---|---:|---:|---:|---|
| kotlin | `_string_start/.fence` + `_automatic_semicolon/.caesura` | +19,678 | +39,966 | **−20,288** | cooperating |
| scala | `_indent/.offside` + `block_comment/.marrow` | −9,796 | −15,296 | **+5,500** | cooperating |
| julia | `_content_str_1/.marrow` + `_immediate_paren/.abut` | +14,728 | +14,565 | +163 | additive |
| elixir | `_quoted_content_double/.marrow` + `_newline_before_do/.caesura` | +12,559 | +12,736 | −177 | additive |
| swift | `multiline_comment/.marrow` + `_implicit_semi/.caesura` | +10,913 | +10,913 | 0 | additive |

**Scala is not the only one, and kotlin is four times worse.** Each kotlin row
alone destroys the grammar - +20,737 and +19,229 - and removing both costs
+19,678. They are two permissions the same walk needs, so the two single-row
arms between them claim 40 KB of a 20 KB defect. The gap between the two
cooperating residuals and the three additive ones is a factor of thirty, so the
1,000-byte threshold that names the verdict column changes nothing today; the
residual is printed on every row because that is luck about this roster.

**No pair is invisible.** The worst available shape - every member reading zero
alone while the pair does not - is tested for by name and no grammar is in it.
Every pair has a member that moves its grammar on its own, so a single-row arm
always notices; what it gets wrong is the size, by up to 20 KB. Swift's
`multiline_comment` moves swift by zero alone, by zero beside `_implicit_semi`,
and by zero in the pair - a seated row that changes nothing in any combination
available to it, which only the pair arm could establish.

`RESULT-5-pairs.md` for the argument, `pairs.json` for the ledger.
