`picorv32.v` carries the corpus's largest damage - 63,937 bytes, 49,446 of them
in one module, 92.1% inside procedural blocks - and until now nobody had a
mechanism for any of it. It is **four grammar defects, two of which carry 98.4%
of the refused bytes**, and each now has a smallest failing module beside a
control that stands:

| defect | witness | control | wall | bytes |
|---|---|---|---|---|
| a directive in statement position | `` `assert(a); `` | `` x = `WIDTH; `` | `` ` `` in 1108 | 21,535 |
| a select inside a concatenation | `x = {a[3], b};` | `{a, b}` and `a[3]` each stand | `;` in 701 | 19,928 |
| `$signed` on both sides of an operator | `lt = $signed(a) < $signed(b);` | `$signed(a) < b` | `(` in 3772 | 360 |
| an indexed lvalue under a **blocking** assignment | `c[i] = 0;` | `c[i] <= 0;` stands | `=` in 2394 | 93 |

The first is **not ours and never will be**. `_directives` is referenced by
exactly three rules in `upstream/grammars/verilog.json` - `_description`,
`_non_port_module_item`, `class_item` - and neither statement position nor a
port list is one of them, so there is no derivation to find and no table work
that can seat it. The same gap at the port-list position is the wall previously
reported as worth 6,935 honest bytes. That makes the honest split of this file
roughly half an upstream grammar gap and half a press conflict, and only the
second half is work anyone here can do.

Three of the four survive the length-preserving control: `{a, b}` stands and
`a[3]` stands and `{a[3], b}` does not, which is a composition failure rather
than a missing rule, and `c[i] <= 0;` stands while `c[i] = 0;` does not, which
narrows a whole family to one assignment form.

**The method changed, because the old one cannot work here.** Ablation - blank a
construct to same-length filler and read what moves - cannot separate a grammar
gap from a productive construct, because blanking something that *partly*
parses takes away the bytes it was contributing. Every arm of a statement-form
sweep on this file moves `built` down and none of them can be read. What
replaced it builds the smallest module that fails from nothing, where `built`
has a known ceiling and there is nothing else in the file to confuse it.

**The instruments that lied were all in the new sweep, and all mine.** A fixed
scratch path let two runs overlap and one read the other's 3,328-byte statement
as its own 90-byte control frame. Splitting statements on `;` cut `for (i = 0; i
< n; i = i+1)` into three fragments and `if (a) x; else y;` into two, which
arrived on the first board as five distinct grammar defects that do not exist -
16 clusters where there are 13. And the automatic shrink was *green* while being
destructive: deleting any token while the wall held turned `$signed(a) <
$signed(b)` into `$signed < $signed(b)`, a different defect sharing a state
number, and all sixteen shrunk witnesses named the state their parent named. The
reported witnesses are authored and checked, not shrunk.

**Frequency is not cost.** Ranked by statements stopped, `` ` `` in 1108 leads
with nine; ranked by bytes, `` ` `` in 1953 leads with one statement and 16,289
bytes. In the warm peel the most repetitive wall on this file, state 2394, costs
−167 bytes and lands twelfth of thirteen here. Any ranking built from wall
counts - including `walls.py`'s own peel and the `voice` derived from it - is
ranking the wrong thing, so the sweep sorts by bytes and prints on every run
which wall the count ordering would have put first.
