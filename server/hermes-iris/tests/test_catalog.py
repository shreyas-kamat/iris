from __future__ import annotations

import json

from conftest import ROOT

LIBRARY_ID = "https://iris.shreyaskamat.in/genui/library/v1"


def test_the_v1_catalog_loads(plugin):
    from hermes_iris.genui import catalog

    lib = catalog.v1()
    assert lib.id == LIBRARY_ID
    assert lib.root == "Stack"
    assert len(lib.components) >= 10
    assert "Ask" in lib.actions


def test_signatures_match_the_schema_order(plugin):
    """The signature text and the JSON Schema both define the positional order; they must not drift apart."""
    from hermes_iris.genui import catalog

    data = json.loads((ROOT / "catalog" / "v1.library.json").read_text("utf-8"))
    for name, spec in catalog.v1().components.items():
        printed = data["components"][name]["signature"]
        names = [p.name for p in spec.props]
        positions = [printed.index(f"{n}") for n in names]
        assert positions == sorted(positions), name


def test_available_ids_lists_every_catalog_file(plugin):
    from hermes_iris.genui import catalog

    assert catalog.library_ids() == [LIBRARY_ID]


def test_a_realistic_display_validates_against_the_catalog(plugin):
    from hermes_iris.genui import catalog
    from hermes_iris.openui import validate_program

    code = "\n".join(
        [
            "root = Stack([head, stats, jobs])",
            'head = Text("Cron jobs", "title")',
            'stats = StatRow([Stat("Running", "12", "+2", "up"), Stat("Failed", "1", null, "down")])',
            'jobs = Card([r1, r2], "Last runs")',
            'r1 = ListRow("backup", "03:00", "ok")',
            'r2 = ListRow("sync", "04:30", "failed")',
        ]
    )
    result = validate_program(catalog.v1(), code)
    assert result.ok, result.lines


def test_charts_and_a_bound_form_validate_against_the_catalog(plugin):
    from hermes_iris.genui import catalog
    from hermes_iris.openui import validate_program

    charts = "\n".join(
        [
            "root = Stack([spark, line, bars, donut])",
            "spark = Sparkline([3, 5, 4, 8])",
            'line = LineChart([Series("Requests", [10, 14, 9]), Series("Errors", [1, 0, 2])], ["Mon", "Tue", "Wed"])',
            'bars = BarChart([Series("Revenue", [120, 90, -20])], ["Q1", "Q2", "Q3"])',
            'donut = Donut([Slice("Docs", 40), Slice("Code", 35)])',
        ]
    )
    result = validate_program(catalog.v1(), charts)
    assert result.ok, result.lines

    form = "\n".join(
        [
            '$cadence = "Weekly"',
            '$note = ""',
            "root = Card([ChoiceChips([\"Daily\", \"Weekly\"], $cadence), Input(\"Note\", $note), "
            'Submit("Send", @Ask("Here is my answer", {cadence: $cadence, note: $note}))], "A form")',
        ]
    )
    result = validate_program(catalog.v1(), form)
    assert result.ok, result.lines


def test_the_catalog_prompt_is_stable_and_complete(plugin):
    from hermes_iris.genui import catalog
    from hermes_iris.openui.prompt import PromptOptions, generate_system_prompt

    lib = catalog.v1()
    prompt = generate_system_prompt(lib, PromptOptions(bindings=True))
    for name in lib.components:
        assert f"\n{name}(" in prompt, name
    assert "@Ask(text: string, context?: any)" in prompt
    assert "@Percent(done: number, total: number)" in prompt
    assert prompt == generate_system_prompt(catalog.v1(), PromptOptions(bindings=True))


def test_capabilities_reports_the_library(client):
    body = client.get("/api/plugins/iris/capabilities").json()
    assert body["library_ids"] == [LIBRARY_ID]
