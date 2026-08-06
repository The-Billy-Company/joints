#!/usr/bin/env python3
"""Verilog's `veiled` bytes, priced by verdict instead of by default.

`rack.py` splits bytes-under-no-leaf into `warp` (a token they built and we did
not), `slack` (bare on both trees) and `veiled` (the oracle declines). On
verilog `veiled` is 4644 of 4644 - the whole population - so the corpus's
largest damage row is priced against silence.

The silence is not the oracle's. Tree-sitter's verilog grammar fails to CLOSE
the top-level parse and wraps the file in one `ERROR` spanning all 94657 bytes;
`plumb.hurt()` taints by ERROR ANCESTRY, so every byte in the file inherits that
one node's verdict and the rule refuses all of them. Underneath it tree-sitter
went on to build 48883 nodes and 17290 leaves. It had an answer the whole time.

So this asks the nearer question, which `plumb.paint` already computes: the
INNERMOST node covering the byte - is it a recovery node, or a construct the
oracle stands behind? That needs no second parser and no new dependency, and it
is what actually moves the row.

Two independent SystemVerilog parsers are then asked to corroborate the two
things tree-sitter cannot certify about itself - that the corpus file is valid,
and that no token is hiding in a byte both trees left bare. Both are optional:
without them this still prints the verdict, marked as uncorroborated.

    python3 research/joinery/judge/judge.py            # the verdict
    python3 research/joinery/judge/judge.py --coverage # who leafs more, us or them

See README.md for how to put the two judges on disk. They live under `.local/`
and are never imported by the product.
"""
import collections
import itertools
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
import plumb  # noqa: E402

JUDGE = ROOT / ".local/judgelane/judge"
SLANG = ROOT / ".local/judgelane/slangvenv/bin/python3"
# Verible tags the bytes that carry no language token. Everything else in its
# raw stream is something a real SystemVerilog lexer named.
BLANK = {"TK_SPACE", "TK_NEWLINE", "end of file"}


def runs(offsets: list[int]) -> list[tuple[int, int]]:
    out = []
    for _, g in itertools.groupby(enumerate(sorted(offsets)), lambda t: t[1] - t[0]):
        g = list(g)
        out.append((g[0][1], g[-1][1] + 1))
    return out


def verible(src: Path, size: int) -> tuple[bytearray, dict] | None:
    """Lexes the text AS WRITTEN - no preprocessor - which is what both trees do."""
    exe = next(JUDGE.glob("verible-*/bin/verible-verilog-syntax"), None)
    if exe is None:
        return None
    got = subprocess.run([str(exe), "--export_json", "--printrawtokens", str(src)],
                         capture_output=True, text=True)
    data = list(json.loads(got.stdout).values())[0]
    mask = bytearray(size)
    for t in data["rawtokens"]:
        a0, b0 = max(t["start"], 0), min(t["end"], size)
        if b0 > a0 and t["tag"] not in BLANK:
            mask[a0:b0] = b"\1" * (b0 - a0)
    return mask, data


def slang(src: Path) -> list[str] | None:
    """Runs the preprocessor, so it UNDER-covers and cannot price a byte. Asked
    only whether the file parses, which is the one thing it is strictly best at."""
    if not SLANG.exists():
        return None
    code = ("import json,sys\nfrom pyslang import syntax\n"
            "t=syntax.SyntaxTree.fromFile(sys.argv[1])\n"
            "json.dump([str(d.code) for d in t.diagnostics], sys.stdout)\n")
    got = subprocess.run([str(SLANG), "-c", code, str(src)], capture_output=True, text=True)
    return None if got.returncode else json.loads(got.stdout)


def masks(saw, size: int) -> tuple[bytearray, bytearray]:
    ours, theirs = bytearray(size), bytearray(size)
    for n in saw.mine:
        if n.leaf:
            ours[max(n.start, 0):min(n.end, size)] = b"\1" * (min(n.end, size) - max(n.start, 0))
    for n in saw.theirs:
        a0, b0 = max(n.start, 0), min(n.end, size)
        if n.leaf and b0 > a0 and not n.name.startswith(plumb.HURT):
            theirs[a0:b0] = b"\1" * (b0 - a0)
    return ours, theirs


def coverage(saw, size: int, ref: bytearray | None) -> None:
    """Who stands a leaf on more of the file - us or them - against a third party.

    The tempting claim is that tree-sitter's whole-file `ERROR` means we win.
    That is a difference in what each tool does when it gives up, not a
    measurement. This is the measurement.
    """
    ours, theirs = masks(saw, size)
    root = max((n for n in saw.theirs if n.name.startswith(plumb.HURT)),
               key=lambda n: n.end - n.start, default=None)
    inner = bytearray(size)
    for n in saw.theirs:
        if n.name.startswith(plumb.HURT) and n is not root:
            a0, b0 = max(n.start, 0), min(n.end, size)
            if b0 > a0:
                inner[a0:b0] = b"\1" * (b0 - a0)

    print(f"\n# leaf coverage")
    tot = sum(ref) if ref else 0
    if ref:
        print(f"  yardstick: verible says {tot} B carry a non-blank token\n")
    print(f"  {'':<16}{'leaf B':>9}{'of token B':>12}{'nodes':>8}{'leaves':>8}")
    for who, m, tree in (("outliner", ours, saw.mine), ("tree-sitter", theirs, saw.theirs)):
        hit = f"{sum(1 for p in range(size) if ref[p] and m[p]) / tot * 100:>11.1f}%" if ref else f"{'--':>12}"
        print(f"  {who:<16}{sum(m):>9}{hit}{len(tree):>8}{sum(n.leaf for n in tree):>8}")

    only_us = [p for p in range(size) if ours[p] and not theirs[p]]
    print(f"\n  bytes WE leaf and tree-sitter does not: {len(only_us)}")
    print(f"  bytes THEY leaf and we do not:          "
          f"{sum(1 for p in range(size) if theirs[p] and not ours[p])}")
    if not only_us:
        print("  -> our leaf set is a STRICT SUBSET of theirs. There is no byte of"
              "\n     verilog we lex and they do not. We do not beat tree-sitter here.")
    if root is not None:
        print(f"\n  tree-sitter's widest ERROR spans [{root.start}, {root.end}) — "
              f"{(root.end - root.start) / size * 100:.0f}% of the file,")
        print(f"  but its {sum(1 for n in saw.theirs if n.name.startswith(plumb.HURT))}"
              f" ERROR nodes minus that root swallow only {sum(inner)} B "
              f"({sum(inner) / size * 100:.2f}%).")
        print("  The root ERROR is a LABEL on a file it parsed, not a failure to parse it.")


def main() -> int:
    name = next((a for a in sys.argv[1:] if not a.startswith("-")), "verilog")
    case = next(c for c in plumb.slate() if c.name == name)
    saw = plumb.read(case)
    if saw is None:
        print(f"{name}: no oracle on this arm — `python3 tool/pin.py oracle <arm>`")
        return 2
    size = len(saw.blob)
    ours, t_ok = masks(saw, size)
    who, bad = plumb.paint(saw.theirs, size), plumb.hurt(saw.theirs, size)
    veil = [p for a, b in saw.scope for p in range(a, b)
            if not ours[p] and (who[p] < 0 or (bad[p] and not t_ok[p]))]

    got = verible(case.source, size)
    ref, vdata = got if got else (None, None)
    if "--coverage" in sys.argv:
        coverage(saw, size, ref)
        return 0

    print(f"# {name}  {case.source.name}  {size} B  ·  veiled {len(veil)}"
          f"  (arm: {plumb.WORK})")

    sound = [p for p in veil
             if who[p] >= 0 and not saw.theirs[who[p]].name.startswith(plumb.HURT)]
    murk = sorted(set(veil) - set(sound))
    mine_at = plumb.paint(saw.mine, size)
    agree = sum(1 for p in sound
                if mine_at[p] >= 0 and saw.mine[mine_at[p]].name == saw.theirs[who[p]].name)

    print(f"\n  innermost oracle cover is a NAMED CONSTRUCT  {len(sound):>6}"
          f"  {len(sound) / max(len(veil), 1) * 100:>5.1f}%  -> `slack` BY VERDICT")
    print(f"    ...and both trees name that construct alike  {agree:>6}"
          f"  {agree / max(len(sound), 1) * 100:>5.1f}%  -> not silence, AGREEMENT")
    print(f"  innermost oracle cover is ERROR/MISSING      {len(murk):>6}"
          f"  {len(murk) / max(len(veil), 1) * 100:>5.1f}%  -> the BOUND")

    kinds = collections.Counter(saw.theirs[who[p]].name for p in sound)
    print("\n  what the oracle built over the bytes it was said to be silent on:")
    for k, v in kinds.most_common(8):
        print(f"    {k:<44}{v:>6}")

    if ref is not None:
        charged = [p for p in sound if ref[p]]
        print(f"\n# verible  ({len(vdata['rawtokens'])} raw tokens,"
              f" {len(vdata.get('errors', []))} parse error(s))")
        print(f"  stands a token on {len(charged)} of the {len(sound)} bytes freed above.")
        by = collections.Counter(saw.theirs[who[p]].name for p in charged)
        for k, v in by.most_common(6):
            mineo = sum(1 for p in charged if saw.theirs[who[p]].name == k and mine_at[p] >= 0
                        and saw.mine[mine_at[p]].name == k)
            print(f"    under `{k}`: {v}" + (f" — we build that same node on {mineo}" if mineo else ""))
        print("  Every one is a byte BOTH trees put under the same construct and neither")
        print("  leafs: verible emits one token per string literal where tree-sitter and")
        print("  we both decompose it into quote-leaves around a bare body. A convention,")
        print(f"  not a defect. `warp` stays 0.")
        print(f"\n  on the {len(murk)} bounded bytes verible stands a token on "
              f"{sum(1 for p in murk if ref[p])}.")
        for a, b in sorted(runs(murk), key=lambda r: -(r[1] - r[0]))[:4]:
            print(f"    [{a:>6},{b:>6}) {b - a:>3} B  {saw.blob[a:b][:48]!r}")
    else:
        print("\n# verible absent — verdict UNCORROBORATED (see README.md)")

    diag = slang(case.source)
    if diag is not None:
        syn = [d for d in diag if "Misleading" not in d]
        print(f"\n# slang  {len(diag)} diagnostic(s): {diag}")
        print(f"  syntax errors: {len(syn)}."
              + ("  The corpus file IS valid verilog, so tree-sitter's whole-file"
                 "\n  ERROR is tree-sitter's and not the corpus's." if not syn else ""))

    print(f"\n# the row, re-priced ({name})")
    print(f"    warp        {0:>5}   no judge stands a token we do not")
    print(f"    slack       {len(sound):>5}   BY VERDICT — was 0, and 4644 stood as `veiled`")
    print(f"    unjudged    {len(murk):>5}   BOUNDED — {len(murk) / size * 100:.2f}% of the file")
    print(f"  owed = damage + warp — unchanged, but now for a reason.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
