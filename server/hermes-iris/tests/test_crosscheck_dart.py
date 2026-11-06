"""Dart and Python must agree on every prefix of every fixture program (spec risk: "Dart <-> Python divergence").

The fixtures test whole programs. Truncated programs reach the parser all the time in real use, so this runs the Dart
package over every prefix (``packages/openui_lang/tool/dump_parse.dart``) and compares the structural results with the
Python port: the error multiset, ``unresolved``, ``orphans``, ``incomplete`` and, where neither side needs an
evaluator, the whole tree. Skipped when the ``dart`` executable is not on PATH.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from collections import Counter

import pytest

from conftest import ROOT

PACKAGE = ROOT.parent.parent / "packages" / "openui_lang"
DART = shutil.which("dart") or shutil.which("dart.bat")


@pytest.mark.skipif(DART is None, reason="dart is not installed")
def test_python_agrees_with_dart_on_every_fixture_prefix(plugin):
    from hermes_iris.openui import Library, parse_program
    from hermes_iris.openui.validate import HasDeferred, summarize

    proc = subprocess.run(
        [DART, "run", "tool/dump_parse.dart"], cwd=PACKAGE, capture_output=True, text=True, encoding="utf-8", timeout=300
    )
    assert proc.returncode == 0, proc.stderr[-2000:]
    rows = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
    assert len(rows) > 2000

    lib = Library.load(PACKAGE / "test" / "fixtures" / "library.json")
    texts: dict[str, str] = {}
    for d in (PACKAGE / "test" / "fixtures").glob("*/*"):
        chunks, inp = d / "chunks.json", d / "input.oui"
        if chunks.exists():
            texts[f"{d.parent.name}/{d.name}"] = "".join(json.loads(chunks.read_bytes().decode("utf-8")))
        elif inp.exists():
            texts[f"{d.parent.name}/{d.name}"] = inp.read_bytes().decode("utf-8")  # keep CRLF: offsets must match Dart

    mismatches = []
    compared_trees = 0
    for row in rows:
        text = texts[row["id"]]
        prefix = "".join(list(text)[: row["i"]])  # by code point, like the Dart side's runes
        r = parse_program(lib, prefix)
        got = {
            "errors": sorted(f"{e.code}|{e.statement_id or '*'}" for e in r.errors),
            "unresolved": sorted(r.unresolved),
            "orphans": sorted(r.orphans),
            "incomplete": r.incomplete,
        }
        want = {k: row[k] for k in got}
        if got != want:
            mismatches.append((row["id"], row["i"], prefix[-40:], got, want))
            continue
        if row["tree"] is not None:
            try:
                tree = summarize(r.tree)
            except HasDeferred:
                mismatches.append((row["id"], row["i"], prefix[-40:], "python has a deferred value", "dart does not"))
                continue
            compared_trees += 1
            if tree != row["tree"]:
                mismatches.append((row["id"], row["i"], prefix[-40:], tree, row["tree"]))

    assert not mismatches, f"{len(mismatches)} of {len(rows)} prefixes differ; first: {mismatches[:3]}"
    assert compared_trees > 500, compared_trees
