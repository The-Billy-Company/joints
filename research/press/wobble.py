#!/usr/bin/env python3
"""Where two mints of one grammar differ, section by section and byte by byte.

The question `RESULT-1-identity.md` left open is whether a press that is not
reproducible produces **different tables** or the same tables written down
differently. A digest over the whole file cannot tell those apart, so this
reads the sealed directory, compares every section on its own, and — for the one
section that turns out to move — inflates the block on both sides and reports
where the *decompressed* images differ.

That last step is the whole measurement. A deflate stream can differ for
reasons that are not in its input; its inflation cannot.

  python3 research/press/wobble.py                 every grammar, twice each
  python3 research/press/wobble.py cpp verilog     just these
  python3 research/press/wobble.py --reps 4 sql    four mints, all compared
  python3 research/press/wobble.py --audit         and place every byte by name

Exit 0 every grammar byte-identical; 1 a table section or a read field moved,
which is semantic; 2 reproducible tables written down two ways.

`--reps` is a sampling knob and not a detail. Against the writer this dossier
fixed, two mints called nine of thirty unstable, six called eleven, and the
population was never a fixed set - it is whichever grammars' padding garbage
happened to differ between the runs you took. So a low `--reps` understates,
and a gate should not economise here.
"""

from __future__ import annotations

import argparse
import re
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

import os

ROOT = Path(__file__).resolve().parents[2]
GRAMMARS = ROOT / "upstream" / "grammars"
# Ten agents share one `zig-out`, so a lane measuring its own fix points this
# at a prefix of its own (`zig build -p …`) rather than racing the shared one.
BIN = Path(os.environ.get("JOINTS_BIN") or ROOT / "zig-out" / "bin" / "joints")

HEADER_LEN = 96
ENTRY_LEN = 16
LEAF = ROOT / "src" / "folio" / "leaf.zig"


def roster() -> tuple[str, ...]:
    """`leaf.Kind`, in directory order, read from `leaf.zig`.

    This used to be a tuple written out here, and the tuple went stale the day
    `rival` was added: twenty-seven names against twenty-eight sections, so every
    run died on an index error the moment it reached the last row. Nothing could
    have caught that, because a second copy of a roster is exactly the shape that
    has nobody to check it — the same argument `impose.ledger` makes on the Zig
    side, where the compiler can make it. Here it cannot, so read the one copy.
    """
    body = LEAF.read_text()
    at = body.index("pub const Kind = enum(u16) {")
    block = body[at:body.index("\n};", at)]
    return tuple(re.findall(r"^ {4}([a-z_]+),$", block, re.M))


KINDS = roster()
# Sections that are the parse table proper. A difference in any of these is
# semantic on its face and there is nothing further to work out. Not every kind
# is in here and it is not meant to be: `lexicon` is an answer *about* the
# grammar and gets the inflate treatment below, and the reserved kinds are always
# empty, so a difference in one is not a thing that can happen.
TABLE = {
    "production", "rhs", "stepref", "step", "row", "row_span", "groupref",
    "group", "set_span", "setsym", "odd", "complete_span", "complete",
    "conflict", "party", "frayed", "name", "pattern", "lexis", "shape",
    "owner", "supertype", "extra", "alias", "field", "text",
}

# `lexicon.Head`: thirteen u32 and one u64, in an extern struct aligned to 8.
# Sixty bytes of fields in a type `@sizeOf` rounds to sixty-four.
HEAD_FIELDS = 60
HEAD_SIZE = 64
# `Dfa.PatRun` is `struct { hi: u32, mask: u64 }` — auto layout, so Zig seats
# the `u64` first and the `u32` after it, and rounds sixteen. The last four
# bytes of every element are padding nobody assigns.
RUN_FIELDS = 12
RUN_SIZE = 16
GRAIN = 8


def sections(path: Path) -> dict[str, bytes]:
    """Every section of a folio, cut out by its own sealed directory row."""
    raw = path.read_bytes()
    assert raw[:8] == b"OTLFOLIO", f"{path} is not a folio"
    count = struct.unpack_from("<H", raw, 10)[0]
    if count != len(KINDS):
        raise SystemExit(
            f"{path.name} carries {count} sections and {LEAF.name} names "
            f"{len(KINDS)}. One of them is not the tree this binary was built "
            f"from — rebuild, or check what moved in `leaf.Kind`.")
    out = {}
    for i in range(count):
        kind, stride, n, off = struct.unpack_from(
            "<HHIQ", raw, HEADER_LEN + i * ENTRY_LEN)
        out[KINDS[kind]] = raw[off:off + n * stride]
    return out


def press(grammar: Path, out: Path, binary: Path | None = None) -> None:
    got = subprocess.run([str(binary or BIN), "mint", str(grammar), "-o", str(out)],
                         capture_output=True, text=True)
    if got.returncode != 0:
        raise SystemExit(f"mint failed for {grammar.name}: {got.stderr[-400:]}")


def inflate(block: bytes) -> bytes:
    """The lexicon image behind a block: a u64 length, then a raw deflate."""
    want = struct.unpack_from("<Q", block, 0)[0]
    image = zlib.decompressobj(-15).decompress(block[8:])
    assert len(image) == want, f"inflated {len(image)}, block claims {want}"
    return image


def padding(image: bytes) -> set[int]:
    """Every byte of the image no field of any record assigns.

    Walked exactly the way `thaw`'s cursor walks it, so a wrong step trips the
    sanity check below rather than quietly excusing a real difference. Two
    sources: the four bytes `@sizeOf` adds past `Head`'s sixty, and the four
    past every `PatRun`'s twelve.
    """
    magic, nvoices, _npat, declined, _digest = struct.unpack_from("<IIIIQ", image, 0)
    assert magic == 0x4c584e32, f"lexicon magic {magic:#x}"
    at = seat(24) + declined * 4
    dead: set[int] = set()
    for _ in range(nvoices):
        at = seat(at)
        (ncls, nstates, match_hi, _start, _start_w, _dead, _empty,
         trans_in, trans_fin, trans_in_w, pat_runs, reach, ordinals,
         _flags) = struct.unpack_from("<IIIIIIQIIIIIII", image, at)
        # The two invariants `thaw` re-checks. If the walk has drifted these
        # are the arithmetic that says so, before any byte is excused.
        assert 0 < ncls <= 256, f"ncls {ncls} at {at}"
        assert trans_in == nstates * ncls == trans_fin, f"tables at {at}"
        assert match_hi <= trans_in, f"match_hi at {at}"
        dead |= set(range(at + HEAD_FIELDS, at + HEAD_SIZE))
        at = seat(at + HEAD_SIZE)
        at = seat(at + 256)                 # class
        for n, w in ((trans_in, 4), (trans_fin, 4), (trans_in_w, 4)):
            at = seat(at + n * w)
        at = seat(at)
        for i in range(pat_runs):
            dead |= set(range(at + i * RUN_SIZE + RUN_FIELDS,
                              at + (i + 1) * RUN_SIZE))
        at = seat(at + pat_runs * RUN_SIZE)
        for n, w in ((reach, 8), (ordinals, 4)):
            at = seat(at + n * w)
    assert seat(at) == len(image), f"walk ended at {at}, image is {len(image)}"
    return dead


def seat(at: int) -> int:
    return (at + GRAIN - 1) & ~(GRAIN - 1)


def where(a: bytes, b: bytes) -> list[int]:
    return [i for i in range(min(len(a), len(b))) if a[i] != b[i]]


def account(paths: list[Path]) -> tuple[int, int, list[str]]:
    """Every differing byte of the whole file, placed by name.

    A section-wise comparison already implies where the differences are, but
    "every differing run sits at or past the lexicon" is a claim about raw
    offsets and deserves to be checked as one - exhaustively, with the header,
    the directory and the seal in scope rather than skipped past. Returns the
    number of differing bytes, how many of them are accounted for, and the
    names of the regions that moved.
    """
    raw = [p.read_bytes() for p in paths]
    n = min(len(r) for r in raw)
    diff = {i for r in raw[1:] for i in where(raw[0], r)}
    # A file that is longer than its twin differs everywhere past the short
    # one's end, and those bytes are as real as any other.
    diff |= set(range(n, max(len(r) for r in raw)))

    # The map is built from **every** file rather than the first, and an offset
    # is placed if it lands in a named region of any of them. Using one file's
    # directory to explain a pair of different lengths leaves the longer one's
    # tail unaccounted for and reads as a mystery - which is what it did on the
    # first run of this, and the mystery was the instrument's, not the press's.
    named: list[tuple[int, int, str]] = []
    for r in raw:
        named += [(88, 96, "header.file_len"), (len(r) - 32, len(r), "the seal")]
        end = 0
        for i in range(struct.unpack_from("<H", r, 10)[0]):
            kind, stride, cells, off = struct.unpack_from(
                "<HHIQ", r, HEADER_LEN + i * ENTRY_LEN)
            row = HEADER_LEN + i * ENTRY_LEN
            named.append((row + 4, row + 8, f"directory[{KINDS[kind]}].count"))
            named.append((row + 8, row + 16, f"directory[{KINDS[kind]}].offset"))
            named.append((off, off + cells * stride, f"section {KINDS[kind]}"))
            end = max(end, off + cells * stride)
        # Sections are eight-aligned, so up to seven zero bytes sit between the
        # last one and the seal. They are zero in every mint; they read as
        # differing only because a section whose length moves moves the slack
        # with it, and then one file's payload offset is another's padding.
        named.append((end, len(r) - 32, "the alignment slack before the seal"))

    moved, placed = set(), set()
    for lo, hi, what in named:
        hit = {d for d in diff if lo <= d < hi}
        if hit:
            moved.add(what)
            placed |= hit
    return len(diff), len(placed), sorted(moved)


def report(name: str, folios: list[Path], audit: bool = False) -> tuple[bool, bool]:
    """Compare every mint of one grammar. Returns (wobbled, semantic)."""
    cut = [sections(f) for f in folios]
    if audit:
        total, seen, moved = account(folios)
        if total:
            print(f"  {name:<14}{total} differing byte(s) in the whole file,"
                  f" {seen} of them placed")
            print(f"    {', '.join(moved)}")
            if seen != total:
                print(f"    UNPLACED — {total - seen} byte(s) fall in no header"
                      f" field, directory row, section, or seal")
    moved = sorted({k for k in KINDS
                    for c in cut[1:] if c.get(k) != cut[0].get(k)})
    if not moved:
        print(f"  {name:<14}reproducible over {len(folios)} mints")
        return False, False

    tables = [m for m in moved if m in TABLE]
    print(f"  {name:<14}{len(moved)} section(s) differ: {', '.join(moved)}")
    if tables:
        print(f"    SEMANTIC — a parse table section moved: {', '.join(tables)}")
        for k in tables:
            print(f"      {k}: lengths {sorted({len(c[k]) for c in cut})}")
        return True, True

    # Only `lexicon`. Inflate both sides and ask the question again of the
    # bytes the deflater was given, which is where an answer actually lives.
    images = [inflate(c["lexicon"]) for c in cut]
    lens = sorted({len(i) for i in images})
    if len(lens) > 1:
        print(f"    SEMANTIC — inflated images differ in length: {lens}")
        return True, True

    diff = where(images[0], images[-1])
    for other in images[1:-1]:
        diff = sorted(set(diff) | set(where(images[0], other)))
    if not diff:
        print(f"    representational — the deflate stream differs,"
              f" the {lens[0]}-byte image behind it is byte-identical")
        return True, False

    # Same length, some bytes differ. Attribute each one: padding, or payload.
    pads = padding(images[0])
    stray = [d for d in diff if d not in pads]
    print(f"    inflated images are all {lens[0]} bytes and differ at"
          f" {len(diff)} byte(s)")
    print(f"      in record padding nothing assigns: {len(diff) - len(stray)}")
    print(f"      in a field a reader reads:         {len(stray)}"
          + ("" if stray else "   ← none"))
    if stray:
        print(f"      SEMANTIC — first strays at {stray[:8]}")
        return True, True
    return True, False


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("names", nargs="*")
    ap.add_argument("--reps", type=int, default=2)
    # The same comparison across two builds rather than two runs. A fix to the
    # writer has to be shown to move the bytes it claims and no others, and
    # "every section but `lexicon` is byte-identical, and the inflated lexicon
    # differs only where nothing reads" is that claim exactly.
    ap.add_argument("--against", type=Path, metavar="BIN",
                    help="press once with each binary instead of twice with one")
    ap.add_argument("--audit", action="store_true",
                    help="also place every differing byte of the whole file by name")
    args = ap.parse_args(argv)

    names = args.names or sorted(p.stem for p in GRAMMARS.glob("*.json"))
    reps = 2 if args.against else args.reps
    print(f"\n  {len(names)} grammar(s), " + (
        f"{BIN} against {args.against}" if args.against
        else f"{reps} mints each") + ", compared section by section\n")
    wobbled, semantic = [], []
    with tempfile.TemporaryDirectory(prefix="wobble-") as tmp:
        for name in names:
            paths = [Path(tmp) / f"{name}.{i}.folio" for i in range(reps)]
            for i, p in enumerate(paths):
                press(GRAMMARS / f"{name}.json", p,
                      args.against if (args.against and i) else BIN)
            w, s = report(name, paths, args.audit)
            for p in paths:
                p.unlink()
            if w:
                wobbled.append(name)
            if s:
                semantic.append(name)

    print(f"\n  {len(names) - len(wobbled)} of {len(names)} reproducible byte for byte")
    print(f"  {len(wobbled)} wobbled: {', '.join(wobbled) or '—'}")
    print(f"  of those, semantically different: {', '.join(semantic) or 'none'}")
    # Graded, because the two failures are different news and a gate that
    # spells them the same way invites the wrong repair. 1 is a press that
    # decides differently twice and every claim resting on a folio is void; 2 is
    # a press that decides the same and writes it down differently, which is
    # today's fixed bug returning and is a bad artifact rather than a bad parse.
    return 1 if semantic else (2 if wobbled else 0)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
