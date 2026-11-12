"""The Python prompt generator must reproduce, byte for byte, the goldens the Dart generator is tested against
(``packages/openui_lang/test/golden/prompt/``, produced by OpenUI's own TypeScript generator)."""

from __future__ import annotations

import pytest

from conftest import ROOT

GOLDEN = ROOT.parent.parent / "packages" / "openui_lang" / "test" / "golden" / "prompt"


def _lib(name: str):
    from hermes_iris.openui import Library

    return Library.load(GOLDEN / f"{name}.library.json")


def _golden(name: str) -> str:
    # bytes, not read_text: a CRLF checkout must not change what we compare against
    return (GOLDEN / f"{name}.txt").read_bytes().decode("utf-8")


def _cases():
    from hermes_iris.openui.prompt import PromptOptions

    return {
        "fixture-plain": ("fixture", PromptOptions()),
        "fixture-bindings": ("fixture", PromptOptions(bindings=True)),
        "fixture-builtins-only": ("fixture", PromptOptions(builtin_functions=True)),
        "fixture-options": (
            "fixture",
            PromptOptions(
                bindings=True,
                preamble="You write Iris displays.",
                examples=['root = Stack([t])\nt = Text("Hello")'],
                additional_rules=["Keep it short.", "British English."],
            ),
        ),
        "grouped-bindings": ("grouped", PromptOptions(bindings=True)),
        "mini-plain": ("mini", PromptOptions()),
        "mini-bindings": ("mini", PromptOptions(bindings=True)),
    }


NAMES = [
    "fixture-plain",
    "fixture-bindings",
    "fixture-builtins-only",
    "fixture-options",
    "grouped-bindings",
    "mini-plain",
    "mini-bindings",
]


@pytest.mark.parametrize("case", NAMES)
def test_matches_the_golden(plugin, case):
    from hermes_iris.openui.prompt import generate_system_prompt

    library, options = _cases()[case]
    assert generate_system_prompt(_lib(library), options) == _golden(case)


def test_is_deterministic(plugin):
    from hermes_iris.openui.prompt import PromptOptions, generate_system_prompt

    options = PromptOptions(bindings=True, examples=["root = Stack([])"])
    lib = _lib("fixture")
    assert generate_system_prompt(lib, options) == generate_system_prompt(lib, options)


def test_teaches_only_what_the_client_supports(plugin):
    from hermes_iris.openui.prompt import PromptOptions, generate_system_prompt

    prompt = generate_system_prompt(_lib("fixture"), PromptOptions(bindings=True))
    for word in ("Query(", "Mutation(", "@Run", "Edit Mode", "Inline Mode"):
        assert word not in prompt, word


def test_the_goldens_are_present(plugin):
    assert len(list(GOLDEN.glob("*.txt"))) >= 7
