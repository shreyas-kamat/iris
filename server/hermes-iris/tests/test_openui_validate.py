from __future__ import annotations

import pytest

from conftest import ROOT

LIB = ROOT.parent.parent / "packages" / "openui_lang" / "test" / "fixtures" / "library.json"


@pytest.fixture
def lib(plugin):
    from hermes_iris.openui import Library

    return Library.load(LIB)


@pytest.fixture
def v(plugin, lib):
    from hermes_iris.openui import validate_program

    return lambda code, **kw: validate_program(lib, code, **kw)


GOOD = 'root = Stack([a, b])\na = Text("Hello")\nb = Tag("ok", "green")\n'


def test_a_clean_program_is_accepted(v):
    r = v(GOOD)
    assert r.ok and r.problems == [] and r.lines == []
    assert r.result.tree.type == "Stack"


def test_a_fenced_program_is_accepted(v):
    assert v("```openui\n" + GOOD + "```\n").ok


def test_an_unknown_component_is_rejected_with_the_choices(v):
    r = v("root = Stack([a])\na = Gauge(3)\n")
    assert not r.ok
    assert any('unknown component "Gauge"' in ln and "Available:" in ln and "Stack" in ln for ln in r.lines), r.lines


def test_missing_required_shows_the_signature(v):
    r = v('root = Stack([m])\nm = Metric("Users")\n')
    assert not r.ok
    assert any("missing required" in ln and "Metric(label*, value*)" in ln for ln in r.lines), r.lines


def test_excess_args_are_rejected(v):
    r = v('root = Stack([t])\nt = Text("a", "body", "extra")\n')
    assert not r.ok and any("takes 2 arguments" in ln for ln in r.lines), r.lines


def test_unresolved_reference_is_named(v):
    r = v('root = Stack([a, ghost])\na = Text("x")\n')
    assert not r.ok
    assert any('"ghost" is used but never defined' in ln for ln in r.lines), r.lines


def test_an_unreferenced_statement_is_rejected_because_it_would_not_render(v):
    r = v('root = Stack([a])\na = Text("x")\nlost = Text("y")\n')
    assert not r.ok
    assert any('"lost" is defined but nothing uses it' in ln for ln in r.lines), r.lines


def test_no_root_is_rejected_even_though_the_language_renders_through_it(v):
    r = v('s = Stack([t])\nt = Text("x")\n')
    assert not r.ok
    assert any("no root statement" in ln for ln in r.lines), r.lines


def test_an_unterminated_program_is_rejected(v):
    r = v('root = Stack([a])\na = Text("never ends')
    assert not r.ok
    assert any("unclosed string or bracket" in ln for ln in r.lines), r.lines


def test_query_and_mutation_are_not_available(v):
    r = v('root = Stack([t])\nt = Text("x")\nq = Query("tool", {}, {})\n')
    assert not r.ok
    assert any("query statements are not available" in ln for ln in r.lines), r.lines


def test_empty_and_prose_only_text(v):
    assert not v("").ok
    assert not v("Sure! Here is a display for you.").ok  # nothing in it is a statement


def test_unknown_function_is_reported(v):
    r = v('root = Stack([t])\nt = Text(@Nope(1))\n')
    assert not r.ok and any("unknown function @Nope" in ln for ln in r.lines), r.lines


def test_builtin_functions_and_state_pass(v):
    code = (
        '$name = "Ada"\n'
        "root = Stack([hello, field])\n"
        'hello = Text("Hi " + $name)\n'
        'field = Input("name", "Your name", $name)\n'
    )
    r = v(code)
    assert r.ok, r.lines


def test_each_with_inline_template(v):
    code = 'data = {rows: [{n: "a"}, {n: "b"}]}\nroot = Stack(@Each(data.rows, "r", Text(r.n)))\n'
    r = v(code)
    assert r.ok, r.lines


# ---- limits --------------------------------------------------------------------------------------------------------


def test_source_size_limit(v):
    from hermes_iris.openui import Limits

    r = v(GOOD, limits=Limits(max_source_bytes=20))
    assert not r.ok and "bytes" in r.lines[0]


def test_size_counts_bytes_not_characters(v):
    from hermes_iris.openui import Limits

    code = 'root = Text("' + "é" * 30 + '")\n'
    assert len(code) < len(code.encode("utf-8"))
    assert v(code, limits=Limits(max_source_bytes=len(code))).ok is False  # 30 two-byte letters


def test_statement_limit(v):
    from hermes_iris.openui import Limits

    items = [f"t{i}" for i in range(10)]
    code = f"root = Stack([{', '.join(items)}])\n" + "".join(f't{i} = Text("x")\n' for i in range(10))
    assert v(code, limits=Limits(max_statements=11)).ok
    r = v(code, limits=Limits(max_statements=10))
    assert not r.ok and any("11 statements" in ln for ln in r.lines), r.lines


def test_default_limits_match_the_spec(plugin):
    from hermes_iris.openui import Limits

    d = Limits()
    assert (d.max_statements, d.max_source_bytes, d.max_depth, d.max_string_bytes) == (60, 12288, 8, 2048)


def test_depth_limit_counts_nested_components(v):
    def nested(levels: int) -> str:
        code = "root = c0\n"
        for i in range(levels):
            inner = f"c{i + 1}" if i + 1 < levels else 'Text("leaf")'
            code += f'c{i} = Card("t", [{inner}])\n'
        return code

    assert v(nested(7)).ok  # 7 cards + the text = 8 levels
    r = v(nested(8))
    assert not r.ok and any("nest" in ln and "limit is 8" in ln for ln in r.lines), r.lines


def test_string_limit(v):
    r = v('root = Text("' + "a" * 2049 + '")\n')
    assert not r.ok and any("longer than 2048" in ln for ln in r.lines), r.lines
    assert v('root = Text("' + "a" * 2048 + '")\n').ok


def test_pathological_nesting_is_refused_without_a_crash(v):
    r = v("root = " + "[" * 5000 + "]" * 5000)
    assert not r.ok
    assert any("nest" in ln for ln in r.lines), r.lines


def test_lines_are_short_and_capped(v):
    code = "root = Stack([" + ", ".join(f"g{i}" for i in range(30)) + "])\n" + "".join(f"g{i} = Nope()\n" for i in range(30))
    r = v(code)
    assert not r.ok
    assert len(r.lines) == 11 and r.lines[-1].startswith("(and ")
    assert all(len(ln) < 400 for ln in r.lines)


# ---- the lexer and parser in Python --------------------------------------------------------------------------------


def test_surrogate_pair_escapes_become_one_character(plugin):
    from hermes_iris.openui.lexer import lex

    tok = next(t for t in lex(r'"😀"') if t.kind == "string")
    assert tok.value == "😀"


def test_lone_surrogate_survives(plugin):
    from hermes_iris.openui.lexer import lex

    tok = next(t for t in lex(r'"\ud83d x"') if t.kind == "string")
    assert tok.value == "\ud83d x"


def test_a_comment_marker_inside_a_string_is_not_a_comment(v):
    assert v('root = Text("see // not a comment # nor this")\n').ok


def test_crlf_line_endings(v):
    assert v(GOOD.replace("\n", "\r\n")).ok


def test_the_validator_never_raises_on_junk(v):
    junk = ["", "\x00\x01", "=", "root =", "root = (", "root = Stack(", "]]>openui:", "```", "root = -", "$ = 1", "@@@", 'root = Text("\\u12']
    for code in junk:
        assert v(code).ok is False  # none of it is a valid program


def test_a_computed_root_is_rejected(v):
    r = v('root = $x ? Text("a") : Text("b")\n')
    assert not r.ok and any("root must be a component" in ln for ln in r.lines), r.lines
