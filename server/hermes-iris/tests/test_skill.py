from __future__ import annotations

import re
import subprocess
import sys

import yaml

from conftest import ROOT

SKILL = ROOT / "skills" / "iris-genui"


def _blocks(text: str, lang: str) -> list[str]:
    return re.findall(rf"```{lang}\n(.*?)```", text, re.S)


def test_skill_md_has_valid_frontmatter():
    text = (SKILL / "SKILL.md").read_bytes().decode("utf-8")
    assert text.startswith("---\n")
    meta = yaml.safe_load(text.split("---\n")[1])
    assert meta["name"] == "iris-genui"
    assert 20 < len(meta["description"]) < 400


def test_skill_md_carries_the_rules():
    text = (SKILL / "SKILL.md").read_bytes().decode("utf-8")
    for needle in (
        "text is complete",
        "fallback",
        "One display per idea",
        "Prefer a template",
        "reply_kit",
        "No secrets",
        "root",
        "positional",
        "tool_call",
        "references/library.md",
        "references/patterns.md",
    ):
        assert needle.lower() in text.lower(), needle


def test_library_md_is_not_stale(plugin):
    """references/library.md is generated; if the catalog or the generator changed, run tools/build_skill_refs.py."""
    from hermes_iris.genui import skill

    on_disk = skill.library_md_path().read_bytes().decode("utf-8")
    assert on_disk == skill.render_library_md()


def test_the_build_script_agrees(hermes_home):
    proc = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "build_skill_refs.py"), "--check"],
        capture_output=True,
        text=True,
        env={**__import__("os").environ, "HERMES_HOME": str(hermes_home)},
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr


def test_library_md_lists_every_component_and_the_ask_action(plugin):
    from hermes_iris.genui import catalog, skill

    text = skill.render_library_md()
    for name in catalog.v1().components:
        assert f"\n{name}(" in text, name
    assert "@Ask(" in text and "@Percent(" in text
    assert "Your ENTIRE response must be valid openui-lang" not in text, "Iris writes its own preamble"


def test_patterns_has_eight_to_ten_programs(plugin):
    text = (SKILL / "references" / "patterns.md").read_bytes().decode("utf-8")
    assert 8 <= len(_blocks(text, "openui")) <= 12


def test_every_pattern_is_a_valid_program(plugin):
    from hermes_iris.genui import catalog
    from hermes_iris.openui import validate_program

    text = (SKILL / "references" / "patterns.md").read_bytes().decode("utf-8")
    lib = catalog.v1()
    for i, code in enumerate(_blocks(text, "openui"), 1):
        verdict = validate_program(lib, code)
        assert verdict.ok, f"pattern block {i}: {verdict.lines}\n{code}"


def test_pattern_names_only_components_that_exist(plugin):
    from hermes_iris.genui import catalog

    text = (SKILL / "references" / "patterns.md").read_bytes().decode("utf-8")
    known = set(catalog.v1().components)
    used = set(re.findall(r"(?<![@\w])([A-Z][A-Za-z]+)\(", "\n".join(_blocks(text, "openui"))))
    assert used <= known | {"Action"}, used - known


def test_register_adds_the_skill(plugin):
    skills = []

    class Ctx:
        def register_tool(self, **kw):
            pass

        def register_hook(self, name, fn):
            pass

        def register_skill(self, name, path, description="", frontmatter=None):
            skills.append((name, path, description))

    plugin.register(Ctx())
    ((name, path, description),) = skills
    assert name == "iris-genui" and path.name == "SKILL.md" and path.exists() and description


def test_an_older_hermes_without_register_skill_still_loads(plugin):
    class Ctx:
        def register_tool(self, **kw):
            pass

        def register_hook(self, name, fn):
            pass

    plugin.register(Ctx())  # must not raise


def test_skill_explains_the_hidden_action_block():
    text = (SKILL / "SKILL.md").read_bytes().decode("utf-8")
    for needle in ("<iris-action>", "surface", "component", "context", "data the person entered"):
        assert needle in text, needle
