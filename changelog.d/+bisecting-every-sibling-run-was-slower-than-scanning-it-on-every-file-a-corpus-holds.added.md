`bench/rungs/cursor` prices the ten neighbourhood accessors against the slow
walks they were, the same questions asked of `vellum`'s settled sheet, the two
lifted helpers spelled both ways, and a bare parse and keystroke underneath all
of it. Four sections, every column printed. It earned itself twice on the way in.

**`descendantForByteRange` bisects each sibling run, and unconditional bisection
lost to the scan on every corpus file** - about 1.4x - because a real file's
widest parent is a few dozen children and an unpredictable branch per halving
costs more than walking the whole run. With the scan kept below 48 children and
the bisection above it, every row wins: 0.96x on the 163-node file (which is
noise on a 50 ns op), **2.12x** on big-json, **1.38x** on huge-json, and
**122x** on a twenty-thousand-element array. That last shape is not in the
corpus, so without it on the slate the board would have reported the bisection
bought nothing - true of the corpus and false of the structure.

**`subtreeSize` was 1.8x slower than the same walk with a caller-held buffer**,
entirely because it allocated its frontier per call. `std.heap.stackFallback`
over 64 refs closed it to 0.94-1.02x on the real files without putting a scratch
buffer in the signature, which is what most nodes being leaves buys you.

The sibling walks came out 1.1-1.5x faster than the oracle for free, and 5-8x on
the wide shape, because `std.mem.indexOfScalar` vectorises the search for a
node's own seat where a `for (among, 0..)` loop does not. Same algorithm.

Where it wins least, both printed: `parent` reads 0.87-0.96x, which is one load
either way and the `?Ref` wrapping showing at a scale where nothing else happens;
and `subtreeSize` reads 0.67x on the wide shape, where every subtree is one node
and the stack setup is pure overhead against an oracle handed a live buffer.
Neither is worth an API change - a caller doing millions of those in a row is
describing `vellum`, not this.

The published vellum trade reproduces from the other side, which is the check
that the harness is honest: `Sheet.parent` is 25-33x slower than a stored
back-pointer and `Sheet.depth` is 5-7x faster than a climb. A board where both
favoured one representation would have meant the rung was wrong.

(`repo f3d3b84bc+21`, M-series laptop with a sibling lane compiling, min-of-7 per
row, both arms over one shuffled tour interleaved within a round. The rung prints
and does not assert on time - a wall-clock floor on a shared machine cries
wolf - but every op is cross-checked against its oracle on every node of every
file before a single trial is timed, and a disagreement exits nonzero.)
