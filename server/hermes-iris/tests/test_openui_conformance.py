"""Runs the OpenUI 1.0 conformance fixtures vendored for the Dart package (one copy, shared) through the Python port.

The Python side parses and validates; it never evaluates. So per fixture it compares what that can know:

* the error multiset (code and statement id), ``unresolved``, ``orphans`` and ``incomplete``, always;
* the validated tree, when it holds no expression only the client can evaluate (see ``HasDeferred``).

What is not compared, and why, is written down in ``openui/FIXTURES_SKIPPED.md``. ``SKIPPED`` below is empty: every
runnable fixture passes its structural checks.
"""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

import pytest

from conftest import ROOT

FIXTURES = ROOT.parent.parent / "packages" / "openui_lang" / "test" / "fixtures"

#: fixture -> reason. Everything else must pass in full.
SKIPPED: dict[str, str] = {}


def _cases() -> list[Path]:
    return sorted(
        d
        for area in FIXTURES.iterdir()
        if area.is_dir()
        for d in area.iterdir()
        if d.is_dir() and (d / "expected.json").exists() and area.name != "editing"
    )


def _name(d: Path) -> str:
    return f"{d.parent.name}/{d.name}"


def _load():
    from hermes_iris.openui import Library

    return Library.load(FIXTURES / "library.json")


def _code_and_id(e: dict) -> str:
    return f"{e.get('code')}|{e.get('statementId') or '*'}"


@pytest.fixture
def library(plugin):
    return _load()


def test_the_fixtures_are_where_we_expect():
    assert (FIXTURES / "library.json").is_file(), FIXTURES
    assert len(_cases()) >= 40


@pytest.mark.parametrize("case", _cases(), ids=_name)
def test_fixture(case: Path, library, plugin):
    from hermes_iris.openui import parse_program
    from hermes_iris.openui.validate import HasDeferred, summarize

    name = _name(case)
    if name in SKIPPED:
        pytest.skip(SKIPPED[name])

    expected = json.loads((case / "expected.json").read_text("utf-8"))
    chunks = (
        json.loads((case / "chunks.json").read_text("utf-8")) if (case / "chunks.json").exists() else None
    )
    text = "".join(chunks) if chunks is not None else (case / "input.oui").read_text("utf-8")

    result = parse_program(library, text)

    got = Counter(_code_and_id(e.to_json()) for e in result.errors)
    want = Counter(_code_and_id(e) for e in expected.get("errors", []))
    assert got == want, f"errors: got {sorted(got.elements())}, want {sorted(want.elements())}"
    assert result.unresolved == set(expected.get("unresolved", []))
    assert result.orphans == set(expected.get("orphans", []))
    assert result.incomplete == expected.get("incomplete", False)

    try:
        tree = summarize(result.tree)
    except HasDeferred:
        return  # needs the client's evaluator; the structural checks above are what the server can verify
    assert tree == expected["root"]


def test_enough_trees_are_compared_in_full(library, plugin):
    """The Python side cannot evaluate, so it skips the tree comparison for programs with computed values. Pin how many
    it still compares so that the check cannot quietly rot."""
    from hermes_iris.openui import parse_program
    from hermes_iris.openui.validate import HasDeferred, summarize

    compared = 0
    for case in _cases():
        chunks = case / "chunks.json"
        text = "".join(json.loads(chunks.read_text("utf-8"))) if chunks.exists() else (case / "input.oui").read_text("utf-8")
        try:
            summarize(parse_program(library, text).tree)
            compared += 1
        except HasDeferred:
            pass
    assert compared >= 24
