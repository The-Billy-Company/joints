#!/usr/bin/env python3
"""Record the working specimens against an already frozen private Zig binary.

Keep desired .expect claims intact, including claims the reference fails. This
record distinguishes an existing defect from a migration regression.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import migration as m
import specimen


def evaluate(claim, tree: dict) -> dict:
    pending = list(tree["tree"])
    nodes = []
    while pending:
        node = pending.pop()
        nodes.append(node)
        pending.extend(node["kids"])
    verb, args = claim.verb, claim.args
    if verb in ("roots", "mends"):
        held = tree[verb] == int(args[0])
    elif verb in ("holds", "lacks"):
        present = any(node["name"] == args[0] for node in nodes)
        held = present if verb == "holds" else not present
    elif verb == "spans":
        held = any((node["name"], node["start"], node["end"]) ==
                   (args[0], int(args[1]), int(args[2])) for node in nodes)
    else:
        raise ValueError(f"unknown claim {verb}")
    return {"line": claim.line, "claim": " ".join((verb, *args)), "holds": held}


def capture(reference: Path, out: Path) -> None:
    if out.exists():
        raise ValueError(f"refusing to replace existing evidence: {out}")
    attestation = m.checked(reference)
    stored = attestation["binary"]["stored"]
    if not stored:
        raise ValueError("specimen capture requires the frozen executable, not a portable export")
    binary = reference / stored
    binary_hash = m.sha(binary.read_bytes())
    if binary_hash != attestation["binary"]["sha256"]:
        raise ValueError("frozen reference binary changed")
    paths = sorted((m.ROOT / "research/joinery/specimen").glob("*/*.expect"))
    if len(paths) != 66:
        raise ValueError(f"expected 66 working specimens, found {len(paths)}")
    records = []
    inputs = {}
    for expect in paths:
        source = expect.with_suffix("")
        name = source.parent.name
        grammar = m.ROOT / "upstream/grammars" / f"{name}.json"
        book = m.ROOT / "customary" / f"{name}.json"
        files = [source, expect, grammar] + ([book] if book.exists() else [])
        hashes = {str(path.relative_to(m.ROOT)): m.sha(path.read_bytes()) for path in files}
        for path, digest in hashes.items():
            if path in inputs and inputs[path] != digest:
                raise ValueError(f"input changed during capture: {path}")
            inputs[path] = digest
        argv = ["parse", str(grammar.relative_to(m.ROOT)), str(source.relative_to(m.ROOT)),
                "--all", "--json"]
        result = m.run([str(binary), *argv], m.ROOT, 600)
        value, strict = m.answer(result)
        checks = [evaluate(claim, value) for claim in specimen.claims(source)]
        if not checks:
            raise ValueError(f"specimen has no claims: {source}")
        relative = str(source.relative_to(m.ROOT / "research/joinery/specimen"))
        output = f"outputs/{relative}.json"
        m.write(out, output, m.encoded(value))
        records.append({"case": relative, "argv": argv, "exit": result["exit"],
                        "strict": strict, "output": output,
                        "output_sha256": m.sha((out / output).read_bytes()),
                        "inputs": hashes, "claims": checks})
        print(f"{relative}: {sum(c['holds'] for c in checks)}/{len(checks)}", flush=True)
    if m.sha(binary.read_bytes()) != binary_hash:
        raise ValueError("reference executable changed during capture")
    for path, digest in inputs.items():
        if m.sha((m.ROOT / path).read_bytes()) != digest:
            raise ValueError(f"input changed during capture: {path}")
    m.write(out, "manifest.json", m.encoded({
        "schema": 1, "population": "66 pinned working specimens; holdout seal untouched",
        "reference_binary_sha256": binary_hash,
        "reference_manifest_sha256": m.sha((reference / "manifest.json").read_bytes()),
        "reference_commit": attestation["repositories"]["joints"]["commit"],
        "command": "capture_migration_specimens.py --reference REFERENCE --out OUTPUT",
        "cases": records,
    }))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    capture(args.reference.resolve(), args.out.resolve())
