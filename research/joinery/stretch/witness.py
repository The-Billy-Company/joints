#!/usr/bin/env python3
"""Who the `warp` bytes are, and the cross-tab `airy` cannot see.

Reads both trees through `plumb.read` - the same reader `rack.survey` uses, so
this is a projection of the board's own population and not a second one - and
prints, per grammar:

  ours_bare    bytes of `built` under no leaf of OURS            (= stretch)
  theirs_bare  bytes of `built` under no leaf of THEIRS          (their padding)
  both_bare    under no leaf on either                           (the shared gap)
  warp         bare on ours, a live oracle leaf on theirs        (a token we owe)
  warp_white   ...of those, how many are whitespace BYTES        (`airy` excuses these)
  air_wrong    bare on ours + non-whitespace + no oracle leaf    (`text` charges these)

`warp_white` and `air_wrong` are the two ways the byte-class rule and the oracle
part company, and they are what the adjudication is about. Wants a sighted arm
like anything else that quotes the oracle: `eval "$(python3 tool/pin.py arm
<name>)"` first, or every row reads as a corpus with no second parser in it.
"""
import collections
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tool"))
import plumb  # noqa: E402
import rack  # noqa: E402

WHITE = rack.WHITE
out, tokens = [], collections.Counter()
COLS = ("ours_bare", "theirs_bare", "both_bare", "warp", "warp_white", "air_wrong")

for case in plumb.slate():
    saw = plumb.read(case)
    if saw is None or saw.why:
        continue
    size = len(saw.blob)
    t_who = plumb.paint(saw.theirs, size)
    t_bad = plumb.hurt(saw.theirs, size)
    ours = bytearray(size)
    for n in saw.mine:
        if n.leaf:
            ours[max(n.start, 0):min(n.end, size)] = b"\1" * (min(n.end, size) - max(n.start, 0))
    theirs, live = bytearray(size), bytearray(size)
    for n in saw.theirs:
        a, b = max(n.start, 0), min(n.end, size)
        if n.leaf and b > a:
            theirs[a:b] = b"\1" * (b - a)
            # The one leaf `plumb` will not quote is one inside a recovery region,
            # so it cannot be a token we owe either. Same blind rule, same place.
            if not n.name.startswith(plumb.HURT):
                live[a:b] = b"\1" * (b - a)
    row = collections.Counter()
    for a, b in saw.scope:
        for p in range(a, b):
            row["ours_bare"] += not ours[p]
            row["theirs_bare"] += not theirs[p]
            row["both_bare"] += not ours[p] and not theirs[p]
            if ours[p]:
                continue
            if t_who[p] < 0 or (t_bad[p] and not live[p]):
                continue
            if live[p]:
                row["warp"] += 1
                row["warp_white"] += saw.blob[p] in WHITE
                tokens[(case.name, saw.theirs[t_who[p]].name)] += 1
            elif saw.blob[p] not in WHITE:
                row["air_wrong"] += 1
    out.append({"name": case.name, **row})
    print(f"{case.name:<19}" + "".join(f"{row[k]:>12}" for k in COLS), flush=True)

print(f"\n{'':<19}" + "".join(f"{k:>12}" for k in COLS))
tot = collections.Counter()
for r in out:
    tot.update({k: v for k, v in r.items() if k != "name"})
print(f"{'CORPUS':<19}" + "".join(f"{tot[k]:>12}" for k in COLS))
print("\nthe tokens we owe, by the oracle's own name for them:")
for (g, n), c in tokens.most_common(30):
    print(f"  {g:<19}{n:<28}{c:>7}")
# Output is machine-local: the board it projects is one arm's, and a JSON checked
# in beside the script would be a number the next reader cannot re-derive.
where = ROOT / ".local" / "stretch" / "witness.json"
where.parent.mkdir(parents=True, exist_ok=True)
where.write_text(json.dumps({"row": out, "corpus": dict(tot),
                             "tokens": {f"{g}/{n}": c for (g, n), c in tokens.items()}}, indent=1))
print(f"\nfiled: {where}")
