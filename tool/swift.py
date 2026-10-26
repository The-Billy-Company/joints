#!/usr/bin/env python3
"""Check the production Swift scanner against frozen independent source trees.

Run after `tool/grammars.py fetch` and a native build. Both the CLI and the
Python binding use that build's embedded scanner; no consumer book is supplied.
The four malformed sources stay refusals. The comment/directive case keeps its
separately adjudicated grammar structure and never rewrites its recovered oracle.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import stamp

ROOT = Path(__file__).resolve().parent.parent
EVIDENCE = ROOT / "test/migration/regulator/evidence/swift-directive-protocol.json"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def cases(evidence: dict) -> list[dict]:
    rows = evidence["cases"]
    require(len(rows) == 19, "the frozen source roster changed")
    require(len({row["case"] for row in rows}) == len(rows), "duplicate source case")
    require(
        sum(row["oracle"]["strict"] is True for row in rows) == 14,
        "the positive oracle population changed",
    )
    require(
        {row["case"] for row in rows if not row["oracle"]["strict"]}
        == {
            "comments",
            "missing-if-condition",
            "incomplete-elseif",
            "incomplete-hash",
            "unterminated-raw",
        },
        "the adjudicated comment and malformed source population changed",
    )
    for row in rows:
        require(
            digest(row["source"].encode()) == row["source_sha256"],
            f"{row['case']}: source bytes drifted",
        )
    return rows


def profile(evidence: dict, base: bytes) -> bytes:
    pin = evidence["profile"]
    require(
        digest(base) == pin["base_sha256"],
        "the pinned Swift working grammar is missing or drifted",
    )
    recipe = pin["recipe"]
    require(
        digest((json.dumps(recipe, indent=2) + "\n").encode()) == pin["recipe_sha256"],
        "the authored profile recipe drifted",
    )
    grammar = json.loads(base)
    grammar["rules"].update(recipe["rules"])
    grammar["conflicts"].extend(recipe["added_conflicts"])
    grammar["externals"].extend(recipe.get("added_externals", []))
    if "extras" in recipe:
        grammar["extras"] = recipe["extras"]
    prepared = (json.dumps(grammar, indent=2) + "\n").encode()
    require(
        digest(prepared) == pin["derived_sha256"],
        "the prepared grammar differs from the frozen profile",
    )
    return prepared


def check(row: dict, answer: dict) -> None:
    name = row["case"]
    require(
        stamp.strict(answer) == (row["oracle"]["strict"] or name == "comments"),
        f"{name}: strict confidence differs",
    )
    if row["oracle"]["strict"]:
        require(
            answer["tree"] == row["oracle"]["tree"],
            f"{name}: independent full tree differs",
        )
    elif name == "comments":
        root = answer["tree"][0]
        require(root["name"] == "source_file", "comments: missing source file")
        require(
            [node["name"] for node in root["kids"]]
            == [
                "comment",
                "directive",
                "multiline_comment",
                "property_declaration",
                "directive",
            ],
            "comments: direct grammar structure differs from the adjudication",
        )
        source = row["source"].encode()
        require(
            [source[node["start"] : node["end"]] for node in root["kids"]]
            == [
                b"// leading",
                b"#if FLAG",
                b"/* branch */",
                b"let value = 1",
                b"#endif",
            ],
            "comments: direct child spans differ",
        )


def native_image(node, field: str | None = None) -> dict:
    children = node.children
    image = {
        "name": node.type,
        "named": node.is_named,
        "start": node.start_byte,
        "end": node.end_byte,
        "kids": [],
    }
    if field is not None:
        image["field"] = field
    first_fields: set[str] = set()
    for index, child in enumerate(children):
        require(child.parent == node, "the C ABI lost a child's actual parent")
        name = node.field_name_for_child(index)
        if name is not None and name not in first_fields:
            require(
                node.child_by_field_name(name) == child,
                f"the C ABI cannot navigate field {name!r}",
            )
            first_fields.add(name)
        image["kids"].append(native_image(child, name))
    return image


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", type=Path, default=ROOT / "zig-out")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    require(
        "JOINTS_CUSTOMARY" not in os.environ,
        "the production scanner gate refuses a custom book override",
    )
    prefix = args.prefix.resolve()
    executable = prefix / "bin/joints"
    library = (
        prefix / "lib" / ("libjnt.dylib" if sys.platform == "darwin" else "libjnt.so")
    )
    require(
        executable.is_file() and library.is_file(),
        "build the native CLI and shared library first",
    )
    args.output.mkdir(parents=True, exist_ok=False)
    evidence_bytes = EVIDENCE.read_bytes()
    evidence = json.loads(evidence_bytes)
    roster = cases(evidence)
    prepared = profile(evidence, (ROOT / "upstream/grammars/swift.json").read_bytes())
    grammar = args.output / "swift.json"
    grammar.write_bytes(prepared)
    inputs = {}
    for row in roster:
        source = args.output / (row["case"] + ".swift")
        source.write_bytes(row["source"].encode())
        inputs[str(source)] = row
    report = {
        "evidence_sha256": digest(evidence_bytes),
        "profile_sha256": digest(prepared),
        "native_before": {
            str(path): digest(path.read_bytes()) for path in (executable, library)
        },
        "cli": [],
        "abi": [],
    }
    (args.output / "inputs.json").write_text(json.dumps(report, indent=2) + "\n")
    folio = args.output / "swift.folio"
    result = subprocess.run(
        [str(executable), "mint", str(grammar), "-o", str(folio)],
        capture_output=True,
        text=True,
        timeout=180,
        check=False,
    )
    (args.output / "mint.stdout").write_text(result.stdout)
    (args.output / "mint.stderr").write_text(result.stderr)
    require(
        result.returncode == 0,
        f"mint refused the exact frozen profile: {result.stderr}",
    )
    for name, options in (
        ("strict", ["--mend=none", "--no-supply"]),
        ("recovery", ["--mend=fell"]),
    ):
        result = subprocess.run(
            [
                str(executable),
                "parse",
                str(folio),
                *inputs,
                "--json",
                "--all",
                *options,
            ],
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        (args.output / (name + ".stdout")).write_text(result.stdout)
        (args.output / (name + ".stderr")).write_text(result.stderr)
        require(
            result.returncode in (0, 1),
            f"{name}: CLI operation failed: {result.stderr}",
        )
        answers = [json.loads(line) for line in result.stdout.splitlines()]
        require(len(answers) == len(inputs), f"{name}: source rows are missing")
        require(
            {answer["path"] for answer in answers} == inputs.keys(),
            f"{name}: selected source paths differ",
        )
        for answer in answers:
            row = inputs[answer["path"]]
            check(row, answer)
        report["cli"].append(
            {
                "mode": name,
                "rows": len(answers),
                "independent_positive_trees": 14,
                "malformed_refusals": 4,
            }
        )

    # Importing the existing source binding exercises the same public C ABI the
    # packaged binding calls. The library path is this build's artifact only.
    sys.path.insert(0, str(ROOT / "bindings/python"))
    from joints import Bank

    with Bank(folio, library=library) as bank, bank.parser() as reader:
        for row in roster:
            with reader.parse(row["source"], strict=False) as tree:
                answer = {
                    "stop": {"kind": tree.stop},
                    "roots": len(tree.roots),
                    "mends": tree.mends,
                    "skipped": tree.skipped,
                    "supplied": tree.supplied,
                    "survey": {"sound": tree.sound},
                    "tree": [native_image(root) for root in tree.roots],
                }
                check(row, answer)
                report["abi"].append({"case": row["case"], "strict": stamp.strict(answer)})
    report["native_after"] = {
        str(path): digest(path.read_bytes()) for path in (executable, library)
    }
    require(
        report["native_before"] == report["native_after"],
        "native artifacts changed during qualification",
    )
    require(
        EVIDENCE.read_bytes() == evidence_bytes,
        "frozen evidence changed during qualification",
    )
    (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print(f"Swift contract: {error}", file=sys.stderr)
        raise SystemExit(1) from error
