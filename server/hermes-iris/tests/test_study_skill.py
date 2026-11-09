from __future__ import annotations

import json
import re

import yaml

from conftest import ROOT

SKILL = ROOT / "skills" / "iris-study"


def _read(rel: str) -> str:
    return (SKILL / rel).read_bytes().decode("utf-8")


def test_skill_md_has_valid_frontmatter():
    text = _read("SKILL.md")
    assert text.startswith("---\n")
    meta = yaml.safe_load(text.split("---\n")[1])
    assert meta["name"] == "iris-study"
    assert 20 < len(meta["description"]) < 400
    assert "study" in meta["description"].lower()


def test_skill_md_points_at_the_tools_and_the_reference():
    text = _read("SKILL.md")
    for needle in (
        "iris_profile_propose",
        "iris_template_propose",
        "iris_template_list",
        "references/study.md",
        "iris:iris-genui",
        "approve",
    ):
        assert needle in text, needle


def test_study_md_covers_the_procedure_and_the_anti_patterns():
    text = " ".join(_read("references/study.md").lower().split())
    for needle in (
        "gather",
        "session_search",
        "memory",
        "cron",
        "kanban",
        "toolset",
        "90 days",
        "3",
        "8 templates",
        "reply kit",
        "made-up",
        "redact",
        "secret",
        "one-off",
        "duplicate",
        "never fabricate",
        "if a source is not available",
    ):
        assert needle in text, needle


def test_the_worked_example_is_a_valid_proposal(plugin, hermes_home):
    """The example calls in study.md are real arguments: the plugin accepts every one of them."""
    from hermes_iris.genui import catalog, personal
    from hermes_iris.genui.store import Store

    blocks = re.findall(r"```json\n(.*?)```", _read("references/study.md"), re.S)
    assert len(blocks) >= 2, "one display and one reply kit"
    p = Store(hermes_home / "iris").profile("default")
    kinds = set()
    for i, block in enumerate(blocks, 1):
        args = json.loads(block)
        result = personal.propose_template(p, catalog.v1(), args)
        assert result["ok"], f"example {i}: {result}"
        kinds.add(args.get("kind", "display"))
    assert kinds == {"display", "reply_kit"}


def test_the_profile_example_is_valid(plugin, hermes_home):
    from hermes_iris.genui import personal
    from hermes_iris.genui.store import Store

    blocks = re.findall(r"```json profile\n(.*?)```", _read("references/study.md"), re.S)
    assert len(blocks) == 1
    p = Store(hermes_home / "iris").profile("default")
    assert personal.propose_profile(p, json.loads(blocks[0]))["ok"]


def test_register_adds_the_study_skill(plugin):
    skills = []

    class Ctx:
        def register_tool(self, **kw):
            pass

        def register_hook(self, name, fn):
            pass

        def register_skill(self, name, path, description="", frontmatter=None):
            skills.append((name, path, description))

    plugin.register(Ctx())
    by = {name: (path, description) for name, path, description in skills}
    assert {"iris-genui", "iris-study"} <= set(by)
    path, description = by["iris-study"]
    assert path.name == "SKILL.md" and path.exists() and description
