from __future__ import annotations

import pytest

SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string", "maxLength": 40},
        "rows": {
            "type": "array",
            "maxItems": 3,
            "items": {
                "type": "object",
                "properties": {"name": {"type": "string"}, "state": {"enum": ["ok", "failed"]}, "n": {"type": "integer", "minimum": 0}},
                "required": ["name", "state"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["title", "rows"],
}

PROGRAM = (
    "root = Stack([head, list])\n"
    'head = Text(data.title, "title")\n'
    'list = Stack(@Each(data.rows, "r", ListRow(r.name, r.state)))\n'
)


@pytest.fixture
def t(plugin):
    from hermes_iris.genui import templates

    return templates


def test_conforming_data_has_no_errors(t):
    assert t.check_data(SCHEMA, {"title": "Jobs", "rows": [{"name": "a", "state": "ok", "n": 2}]}) == []


@pytest.mark.parametrize(
    "data, fragment",
    [
        ({"rows": []}, "title is required"),
        ({"title": 3, "rows": []}, "title must be a string"),
        ({"title": "x" * 41, "rows": []}, "title is longer than 40"),
        ({"title": "t", "rows": "no"}, "rows must be an array"),
        ({"title": "t", "rows": [{}] * 4}, "rows has more than 3 items"),
        ({"title": "t", "rows": [{"name": "a"}]}, "rows[0].state is required"),
        ({"title": "t", "rows": [{"name": "a", "state": "weird"}]}, "rows[0].state must be one of"),
        ({"title": "t", "rows": [{"name": "a", "state": "ok", "n": -1}]}, "rows[0].n must be at least 0"),
        ({"title": "t", "rows": [{"name": "a", "state": "ok", "n": 1.5}]}, "rows[0].n must be an integer"),
        ({"title": "t", "rows": [{"name": "a", "state": "ok", "extra": 1}]}, "rows[0].extra is not allowed"),
        ("not an object", "data must be an object"),
    ],
)
def test_nonconforming_data_names_the_path(t, data, fragment):
    errors = t.check_data(SCHEMA, data)
    assert any(fragment in e for e in errors), errors


def test_booleans_are_not_numbers(t):
    assert t.check_data({"type": "number"}, True) != []
    assert t.check_data({"type": "integer"}, True) != []
    assert t.check_data({"type": "boolean"}, True) == []


def test_expand_prepends_data(t):
    code = t.expand({"data_schema": SCHEMA, "program": PROGRAM}, {"title": "Jobs", "rows": [{"name": "a", "state": "ok"}]})
    assert code.startswith('data = {"title": "Jobs", "rows": [{"name": "a", "state": "ok"}]}\n')
    assert code.endswith(PROGRAM)


def test_expand_checks_the_data(t):
    with pytest.raises(t.TemplateError) as e:
        t.expand({"data_schema": SCHEMA, "program": PROGRAM}, {"rows": []})
    assert "title is required" in str(e.value)


def test_a_template_may_not_define_data(t):
    with pytest.raises(t.TemplateError):
        t.expand({"data_schema": {}, "program": 'data = {}\nroot = Text("x")\n'}, {})


def test_awkward_strings_survive_the_round_trip(plugin, t):
    from hermes_iris.genui import catalog
    from hermes_iris.openui import parse_program
    from hermes_iris.openui.nodes import Deferred

    nasty = 'He said "hi"\nline2 // not a comment # nor this \\ back   é 😀 {[(]) $x @y'
    code = t.expand({"data_schema": {}, "program": 'root = Text("x")\n'}, {"v": nasty})
    result = parse_program(catalog.v1(), code)
    assert result.errors == []
    stmt = result.program.statements["data"]
    # the object literal's one entry holds exactly the original string
    assert stmt.expr.entries[0][0] == "v"
    assert stmt.expr.entries[0][1].value == nasty
    assert not isinstance(result.tree, Deferred)


def test_non_finite_numbers_are_refused(t):
    with pytest.raises(t.TemplateError):
        t.expand({"data_schema": {}, "program": "root = Text(\"x\")\n"}, {"v": float("nan")})
