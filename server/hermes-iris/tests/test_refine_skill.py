from __future__ import annotations

import json
import re

import yaml

from conftest import ROOT

SKILL = ROOT / "skills" / "iris-refine"
STUDY = ROOT / "skills" / "iris-study"


def _read(rel: str, base=SKILL) -> str:
    return (base / rel).read_bytes().decode("utf-8")


def test_skill_md_has_valid_frontmatter():
    text = _read("SKILL.md")
    assert text.startswith("---\n")
    meta = yaml.safe_load(text.split("---\n")[1])
    assert meta["name"] == "iris-refine"
    assert 20 < len(meta["description"]) < 400
    assert "refine" in meta["description"].lower()


def test_skill_md_points_at_the_tools_and_the_reference():
    text = _read("SKILL.md")
    for needle in (
        "iris_usage_summary",
        "iris_template_refine",
        "iris_template_propose",
        "iris_template_list",
        "references/refine.md",
        "iris:iris-genui",
        "approve",
    ):
        assert needle in text, needle


def test_refine_md_covers_the_procedure_and_the_restraint():
    text = " ".join(_read("references/refine.md").lower().split())
    for needle in (
        "iris_usage_summary",
        "not_useful",
        "dismissed",
        "expanded",
        "never shown",
        "too little",
        "retire",
        "one change",
        "reason",
        "new template",
        "redact",
        "never fabricate",
        "nothing is used until",
    ):
        assert needle in text, needle


def _approved_base(plugin, hermes_home):
    """The study skill's deploy-status example, proposed and approved, as the refinements below assume."""
    from hermes_iris.genui import catalog, personal
    from hermes_iris.genui.store import Store

    p = Store(hermes_home / "iris").profile("default")
    study = re.findall(r"```json\n(.*?)```", _read("references/study.md", STUDY), re.S)
    base = json.loads(study[0])
    assert base["id"] == "deploy-status"
    assert personal.propose_template(p, catalog.v1(), base)["ok"]
    assert personal.put_template(p, catalog.v1(), "deploy-status", {"status": "approved"})["ok"]
    return p, catalog.v1(), personal


def test_the_worked_examples_are_valid_refinements(plugin, hermes_home):
    """Every `json refine` block is a real call: the plugin accepts it against the approved base template."""
    p, lib, personal = _approved_base(plugin, hermes_home)
    blocks = re.findall(r"```json refine\n(.*?)```", _read("references/refine.md"), re.S)
    assert len(blocks) == 2, "one change and one retirement"
    kinds = set()
    for i, block in enumerate(blocks, 1):
        args = json.loads(block)
        result = personal.propose_refinement(p, lib, args)
        assert result["ok"], f"example {i}: {result}"
        kinds.add(result["proposal"])
    assert kinds == {"refine", "retire"}


def test_register_adds_the_three_skills(plugin):
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
    assert set(by) == {"iris-genui", "iris-study", "iris-refine"}
    path, description = by["iris-refine"]
    assert path.name == "SKILL.md" and path.exists() and description
