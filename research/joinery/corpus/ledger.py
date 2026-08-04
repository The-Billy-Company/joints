"""The corpus program: a ledger that caches its own total."""

from __future__ import annotations

import sys


class Ledger:
    def __init__(self, seed: list[int] | None = None) -> None:
        self.rows: list[int] = []
        self.tags: dict[str, int] = {}
        self._total: int | None = None
        for v in seed or []:
            self.push(f"seed{len(self.rows)}", v)

    def push(self, tag: str, v: int) -> int:
        at = len(self.rows)
        self.rows.append(v)
        self.tags[tag] = at
        self._total = None
        return at

    @property
    def total(self) -> int:
        if self._total is None:
            self._total = sum(r for r in self.rows if r > 0)
        return self._total

    def merge(self, other: Ledger) -> Ledger:
        for tag, at in other.tags.items():
            self.push(tag, other.rows[at])
        return self


def main(argv: list[str]) -> int:
    led = Ledger([1, 2, 3])
    for i, arg in enumerate(argv):
        try:
            led.push(f"arg{i}", int(arg))
        except ValueError as e:
            print(f"skipping {arg}: {e}", file=sys.stderr)
    print(f"total={led.total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
