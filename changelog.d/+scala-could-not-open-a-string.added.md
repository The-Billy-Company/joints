scala could not open a string.

Treatment outliner `beb695b5d` · tree `e973ce73c` (pin) · oracle `d85e736fa`
(30 of 30 live, 30 attributed), against control outliner `aece1211e` · tree
`a9353c78b` on the same oracle. `still against` reads comparable: two files
differ and this lane claims both.

Scala walled on byte 20093, the opening quote of
`throw new NoSuchElementException("None.get")` - the only string in code in the
whole file, since the other 31 a regex finds sit inside scaladoc comments. It is
14 bytes from the end, so scala parsed 20,093 of 20,107 bytes and then had
nowhere to put a quote. `_simple_string_start` was one of 21 externals it hands
to a C scanner we do not link.

I was about to infer the spelling from the grammar rule, which is what the
kotlin lane did and what its dossier names as the thing it trusted least. No
need: the differential harness builds each grammar with its real scanner, so
every upstream `scanner.c` is already on this machine and nineteen of the thirty
have one. Reading scala's settles what the rule leaves open - the opener marks
its end after the *first* quote, so `"""` is a different terminal rather than a
longer reading of the same one; the body ends on a `"` it consumes and on a `\`
it stops before; a newline ends the scan, and `$` is ordinary in simple mode.
Three patterns fall out, and the `string_mode` that C function carries is memory
the state already has, so this is a spelling and not a fence.

The first version guarded the opener with `never` so a `"""` would refuse. The
regression test failed and was right to: a stand-in that refuses does not take
the position. `refusing` is a priority pass, and a failed trailing context
returns null and falls through to the ordinary slate, where the same row matches
the bare quote anyway. So `"""` loses the position to the longer opener instead -
`_simple_multiline_string_start` gets a row and longest-match settles it, the way
the C settles it by looking for two more quotes before committing. Its end stays
blind on purpose, because it closes on three-or-more quotes not followed by a
quote and a longest-match engine with no lazy repeat cannot spell a body that
stops at the first of them. A multiline string refuses, which is what it did
before. Blind goes 21 -> 17.

Scala now reads `accepted, 1 root`, its `damage` goes 4,150 -> 0, and the
board's `reached whole` goes 18 -> 19 with corpus `trued` 63.9% -> 64.7%. One
row of thirty moved: built +4,150, square **+4,281** - more than built, because
131 unframed bytes got a frame too - and crooked +0. Not one newly built byte is
judged wrong, which is the opposite of the haskell brackets commit that built
6,008 bytes for zero square and 3,080 crooked.

`research/joinery/scala/RESULT-1-strings.md` has the arm comparison, the scanner
excerpt, the guard that turned out not to guard, the split of the remaining
eight orphan rows into blind-terminal walls and table defects, and what I trust
least - chiefly that one string with no escape in it proves two of the four rows
and nothing here exercises the other two at all.
