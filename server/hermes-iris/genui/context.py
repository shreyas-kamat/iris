"""The text ``pre_llm_call`` adds to a flagged session's turn (Phase 0.4: it reaches the model, is not stored in the
user's row, and so needs no stripping in the app).

It must stay small (``MAX_CHARS``): it is sent on every turn. It carries the rules, the one tool and its argument shape
(Hermes defers plugin tools, and naming it lets the model skip the ~13 s discovery), a one-line-per-component digest,
and an index of the person's approved templates. The full signatures and worked examples live in the skill
(``skill_view('iris:iris-genui', 'references/library.md')``) and are pulled only when composing something new.
"""

from __future__ import annotations

from typing import Any

from ..openui.library import Library
from . import catalog
from .flags import is_flagged
from .paths import current_profile, iris_root
from .store import Store

MAX_CHARS = 2500
_TITLE_MAX = 50

_RULES = """[iris] This chat is in the Iris app, which can show native displays. To show one, call the tool iris_ui (through tool_call if it is deferred) with {surface_id, code or template+data, fallback}.
Rules:
- Use a display only when it beats text: status, comparisons, lists, forms, choices. Otherwise reply in text.
- Always write the full answer in your text as well. fallback is the same content as Markdown.
- One display per idea, at most 4 per reply. To change one, reuse its surface_id.
- code is OpenUI Lang: one statement per line, root first, positional arguments, e.g. root = Stack([a])  a = Text("Hi", "title"). Every statement must be reachable from root.
- Prefer a template when one fits. Never put secrets or tokens in a display.
- If iris_ui returns errors, fix them and send it again."""

_FOOTER = "Full signatures and examples: skill_view('iris:iris-genui', 'references/library.md')"


def _signature(spec: Any) -> str:
    return f"{spec.name}({', '.join(p.name + ('' if p.required else '?') for p in spec.props)})"


def _fit(lines: list[str], budget: int, more: str, sep: str = "\n") -> str:
    """As many of ``lines`` as fit in ``budget`` characters, then a "(+N more ...)" note for the rest."""
    if budget <= 0 or not lines:
        return ""
    out: list[str] = []
    used = 0
    for i, line in enumerate(lines):
        left = len(lines) - i - 1
        note = f"(+{left} {more})" if left else ""
        # keep room for the note when something is left over
        if used + len(line) + (len(sep) if out else 0) + (len(sep) + len(note) if left else 0) > budget:
            rest = len(lines) - i
            out.append(f"(+{rest} {more})")
            break
        used += len(line) + (len(sep) if out else 0)
        out.append(line)
    return sep.join(out)


def build(library: Library, templates: list[dict[str, Any]]) -> str:
    """The context text for ``library`` and the approved ``templates`` (each ``{id, title, keys}``), at most
    :data:`MAX_CHARS` characters. The rules and the pointer to the skill are never cut; templates give way first."""
    fixed = f"{_RULES}\n{_FOOTER}"
    room = MAX_CHARS - len(fixed) - len("\nComponents: \nTemplates:\n")

    specs = list(library.components.values())
    full = [_signature(s) for s in specs]
    names = [s.name for s in specs]

    template_lines = [
        f"- {t['id']}: {str(t.get('title') or '')[:_TITLE_MAX]} (data: {', '.join(t.get('keys') or [])})" for t in templates
    ]
    # Templates may take up to a third of what is left; the digest gets the rest, shrinking before it is cut.
    template_budget = min(sum(len(line) + 1 for line in template_lines), room // 3) if template_lines else 0
    templates_text = _fit(template_lines, template_budget, "more templates") if template_lines else ""

    digest_budget = room - len(templates_text)
    digest = ", ".join(full)
    if len(digest) > digest_budget:
        digest = ", ".join(names)
    if len(digest) > digest_budget:
        digest = _fit(names, digest_budget, "more components", sep=", ")

    parts = [_RULES, f"Components: {digest}"]
    if templates_text:
        parts.append(f"Templates:\n{templates_text}")
    parts.append(_FOOTER)
    text = "\n".join(parts)
    if len(text) > MAX_CHARS:  # cannot happen with the budgets above; the cap is a promise, so enforce it
        text = text[: MAX_CHARS - 1] + "…"
    return text


def _approved_templates(store_profile: Any) -> list[dict[str, Any]]:
    out = []
    for template_id in store_profile.list_templates():
        t = store_profile.get_template(template_id)
        if not t or t.get("status") != "approved":
            continue
        props = (t.get("data_schema") or {}).get("properties")
        keys = list(props)[:6] if isinstance(props, dict) else []
        out.append({"id": template_id, "title": t.get("name") or "", "keys": keys})
    return out


def on_pre_llm_call(**kw: Any) -> dict[str, str] | None:
    """Hermes ``pre_llm_call``: ``{"context": text}`` for a flagged session, otherwise None. Never raises."""
    try:
        session_id = kw.get("session_id")
        if not isinstance(session_id, str) or not is_flagged(session_id):
            return None
        profile = Store(iris_root()).profile(current_profile())
        try:
            templates = _approved_templates(profile)
        except Exception:  # noqa: BLE001 - a damaged template file must not take the whole context away
            templates = []
        return {"context": build(catalog.v1(), templates)}
    except Exception:  # noqa: BLE001
        return None
