"""The person's work profile and personal templates (Phase 5): what the agent proposes and what the person approves.

Both are proposals until the person approves them in Iris (D8). A record's ``status`` is ``proposed``, ``approved`` or
``retired``; only ``approved`` templates are offered to the model (context) or usable by ``iris_ui``. The agent may only
*propose*, and a proposal never replaces an approved template, because that one is in use. A change to an approved one
(``propose_refinement``) waits beside it in ``proposal`` until the person applies or discards it.
The app writes through :func:`put_profile` and :func:`put_template`, which merge the fields they are given.

Every function returns a plain dict: ``{"ok": True, ...}`` or ``{"ok": False, "errors": [one line each]}``. Nothing here
logs content.
"""

from __future__ import annotations

import json
import threading
import time
from typing import Any

from ..openui import Library, validate_program
from . import templates
from .store import InvalidName, ProfileStore, StoreError, safe_component

STATUSES = ("proposed", "approved", "retired")
KINDS = ("display", "reply_kit")
MAX_TEMPLATES = 50
SUMMARY_MAX = 600
CHIPS_MAX = 12
CHIP_MAX = 40
NAME_MAX = 60
WHEN_MAX = 200
SCHEMA_MAX_BYTES = 4096
SAMPLE_MAX_BYTES = 4096

_TEMPLATE_FIELDS = ("name", "when", "data_schema", "program", "sample_data", "kind")
_LOCK = threading.Lock()


def _fail(*errors: str) -> dict[str, Any]:
    return {"ok": False, "errors": list(errors)}


def _size(value: Any) -> int:
    try:
        return len(json.dumps(value, ensure_ascii=False, allow_nan=False).encode("utf-8"))
    except (TypeError, ValueError):
        return SCHEMA_MAX_BYTES + 1


# ---- profile ---------------------------------------------------------------------------------------------------------


def _profile_problems(summary: Any, chips: Any) -> list[str]:
    problems: list[str] = []
    if not isinstance(summary, str) or not summary.strip():
        problems.append("summary is required: one or two sentences about the person's work")
    elif len(summary) > SUMMARY_MAX:
        problems.append(f"summary is longer than {SUMMARY_MAX} characters")
    if not isinstance(chips, list):
        problems.append("chips must be a list of short strings")
    else:
        if len(chips) > CHIPS_MAX:
            problems.append(f"chips has more than {CHIPS_MAX} items")
        if any(not isinstance(c, str) or not c.strip() for c in chips):
            problems.append("chips must be non-empty strings")
        elif any(len(c) > CHIP_MAX for c in chips):
            problems.append(f"each chip is at most {CHIP_MAX} characters")
    return problems


def get_profile(profile: ProfileStore) -> dict[str, Any]:
    return {"ok": True, "profile": profile.get_profile()}


def propose_profile(profile: ProfileStore, args: Any) -> dict[str, Any]:
    """The agent's profile proposal. It replaces an earlier one, and remembers what had been approved as ``previous``."""
    if not isinstance(args, dict):
        return _fail("the arguments must be an object")
    summary, chips = args.get("summary"), args.get("chips", [])
    problems = _profile_problems(summary, chips)
    if problems:
        return _fail(*problems)
    summary = summary.strip()
    chips = [c.strip() for c in chips]
    try:
        with _LOCK:
            old = profile.get_profile()
            now = time.time()
            record: dict[str, Any] = {
                "summary": summary,
                "chips": chips,
                "status": "proposed",
                "rev": (old.get("rev", 0) if old else 0) + 1,
                "created": old.get("created", now) if old else now,
                "updated": now,
            }
            if old and old.get("status") == "approved":
                record["previous"] = {"summary": old.get("summary"), "chips": old.get("chips", [])}
            elif old and isinstance(old.get("previous"), dict):
                record["previous"] = old["previous"]
            profile.put_profile(record)
    except StoreError:
        return _fail("the profile could not be saved; try again")
    return {"ok": True, "rev": record["rev"], "status": "proposed"}


def put_profile(profile: ProfileStore, body: Any) -> dict[str, Any]:
    """The person's edit: merges ``summary``, ``chips`` and ``status`` onto what is stored."""
    if not isinstance(body, dict):
        return _fail("the body must be an object")
    try:
        with _LOCK:
            old = profile.get_profile()
            merged = {k: body[k] for k in ("summary", "chips", "status") if k in body}
            if old is None:
                merged.setdefault("chips", [])
            else:
                merged = {**{k: old.get(k) for k in ("summary", "chips", "status")}, **merged}
            problems = _profile_problems(merged.get("summary"), merged.get("chips"))
            if merged.get("status", "proposed") not in STATUSES:
                problems.insert(0, f"status must be one of {', '.join(STATUSES)}")
            if problems:
                return _fail(*problems)
            now = time.time()
            record = {
                "summary": merged["summary"].strip(),
                "chips": [c.strip() for c in merged["chips"]],
                "status": merged.get("status", "proposed"),
                "rev": (old.get("rev", 0) if old else 0) + 1,
                "created": old.get("created", now) if old else now,
                "updated": now,
            }
            if old and isinstance(old.get("previous"), dict) and record["status"] != "approved":
                record["previous"] = old["previous"]
            profile.put_profile(record)
    except StoreError:
        return _fail("the profile could not be saved; try again")
    return {"ok": True, "profile": record}


# ---- templates -------------------------------------------------------------------------------------------------------


def _template_problems(library: Library, fields: dict[str, Any]) -> list[str]:
    """Everything wrong with a complete set of template fields, as lines the model or the person can act on."""
    problems: list[str] = []
    name, when = fields.get("name"), fields.get("when")
    if not isinstance(name, str) or not name.strip():
        problems.append("name is required: a short title the person will see")
    elif len(name) > NAME_MAX:
        problems.append(f"name is longer than {NAME_MAX} characters")
    if not isinstance(when, str) or not when.strip():
        problems.append("when is required: one line saying when to use this template")
    elif len(when) > WHEN_MAX:
        problems.append(f"when is longer than {WHEN_MAX} characters")
    if fields.get("kind", "display") not in KINDS:
        problems.append(f"kind must be one of {', '.join(KINDS)}")
    schema, sample, program = fields.get("data_schema"), fields.get("sample_data"), fields.get("program")
    schema_ok = isinstance(schema, dict) and schema.get("type") == "object"
    if not schema_ok:
        problems.append('data_schema must be a JSON Schema object with "type": "object"')
    elif _size(schema) > SCHEMA_MAX_BYTES:
        problems.append(f"data_schema is larger than {SCHEMA_MAX_BYTES} bytes")
        schema_ok = False
    sample_ok = isinstance(sample, dict)
    if not sample_ok:
        problems.append("sample_data must be an object that fits data_schema, with made-up values")
    elif _size(sample) > SAMPLE_MAX_BYTES:
        problems.append(f"sample_data is larger than {SAMPLE_MAX_BYTES} bytes")
        sample_ok = False
    if not isinstance(program, str) or not program.strip():
        problems.append("program is required: OpenUI Lang that reads the `data` object")
    elif schema_ok and sample_ok:
        try:
            code = templates.expand({"data_schema": schema, "program": program}, sample)
        except templates.TemplateError as e:
            problems.extend(e.errors)
        else:
            verdict = validate_program(library, code)
            if not verdict.ok:
                problems.extend(verdict.lines)
    return problems


def _template_id(value: Any) -> tuple[str | None, list[str]]:
    try:
        return safe_component(value), []
    except InvalidName:
        return None, ["id must be 1-64 letters, digits, '_' or '-'"]


def _count(profile: ProfileStore) -> int:
    return len(profile.list_templates())


def propose_template(profile: ProfileStore, library: Library, args: Any) -> dict[str, Any]:
    """The agent's template proposal. Stored as ``proposed``; never replaces an approved template."""
    if not isinstance(args, dict):
        return _fail("the arguments must be an object")
    template_id, problems = _template_id(args.get("id"))
    args = {**args, "kind": args.get("kind") or "display"}
    problems += _template_problems(library, args)
    if problems:
        return _fail(*problems)
    assert template_id is not None
    try:
        with _LOCK:
            old = profile.get_template(template_id)
            if old and old.get("status") == "approved":
                return _fail(
                    f'template "{template_id}" is already approved and in use; change it with iris_template_refine, '
                    "or propose a new id"
                )
            if old is None and _count(profile) >= MAX_TEMPLATES:
                return _fail(f"there are already {MAX_TEMPLATES} templates; the person must retire some first")
            now = time.time()
            record = {
                "id": template_id,
                **{k: args[k] for k in _TEMPLATE_FIELDS},
                "status": "proposed",
                "rev": (old.get("rev", 0) if old else 0) + 1,
                "created": old.get("created", now) if old else now,
                "updated": now,
            }
            profile.put_template(template_id, record)
    except StoreError:
        return _fail("the template could not be saved; try again")
    return {"ok": True, "id": template_id, "rev": record["rev"], "status": "proposed"}


def put_template(profile: ProfileStore, library: Library, template_id: Any, body: Any) -> dict[str, Any]:
    """The person's edit: merges the given fields onto the stored template (or creates one from a full set)."""
    if not isinstance(body, dict):
        return _fail("the body must be an object")
    tid, problems = _template_id(template_id)
    if problems:
        return _fail(*problems)
    assert tid is not None
    if "proposal" in body:
        return decide_proposal(profile, library, tid, body["proposal"])
    try:
        with _LOCK:
            old = profile.get_template(tid)
            merged = {k: (old or {}).get(k) for k in (*_TEMPLATE_FIELDS, "status")}
            merged.update({k: body[k] for k in (*_TEMPLATE_FIELDS, "status") if k in body})
            if merged.get("status") is None:
                merged["status"] = "proposed"
            if merged.get("kind") is None:
                merged["kind"] = "display"
            problems = [] if merged["status"] in STATUSES else [f"status must be one of {', '.join(STATUSES)}"]
            problems += _template_problems(library, merged)
            if old is None and not problems and _count(profile) >= MAX_TEMPLATES:
                problems.append(f"there are already {MAX_TEMPLATES} templates; retire some first")
            if problems:
                return _fail(*problems)
            now = time.time()
            record = {
                "id": tid,
                **{k: merged[k] for k in _TEMPLATE_FIELDS},
                "status": merged["status"],
                "rev": (old.get("rev", 0) if old else 0) + 1,
                "created": old.get("created", now) if old else now,
                "updated": now,
            }
            waiting = old.get("proposal") if old else None
            if isinstance(waiting, dict) and record["status"] == "approved":
                # The person's own edit stays in a waiting proposal wherever the agent left that field as it was.
                carried = dict(waiting)
                for key in _TEMPLATE_FIELDS:
                    if old is not None and waiting.get(key) == old.get(key):
                        carried[key] = record[key]
                record["proposal"] = carried
            profile.put_template(tid, record)
    except StoreError:
        return _fail("the template could not be saved; try again")
    return {"ok": True, "template": record}


# ---- refinement (Phase 6): a waiting change to an approved template, decided by the person --------------------------------

REASON_MAX = 300


def propose_refinement(profile: ProfileStore, library: Library, args: Any) -> dict[str, Any]:
    """The agent's change to an approved template, or its suggestion to retire it.

    The approved version stays in use; the change waits in ``template["proposal"]`` until the person applies or discards
    it in Iris. A later proposal for the same template replaces an earlier one.
    """
    if not isinstance(args, dict):
        return _fail("the arguments must be an object")
    template_id, problems = _template_id(args.get("id"))
    reason = args.get("reason")
    if not isinstance(reason, str) or not reason.strip():
        problems.append("reason is required: one line on what the use and the signals showed")
    elif len(reason) > REASON_MAX:
        problems.append(f"reason is longer than {REASON_MAX} characters")
    retire = args.get("retire")
    if retire is not None and not isinstance(retire, bool):
        problems.append("retire must be true or false")
    changed = {k: args[k] for k in _TEMPLATE_FIELDS if args.get(k) is not None}
    if retire and changed:
        problems.append("a suggestion to retire carries no changes: leave out the template fields")
    if problems:
        return _fail(*problems)
    assert template_id is not None and isinstance(reason, str)
    try:
        with _LOCK:
            old = profile.get_template(template_id)
            if old is None or old.get("status") != "approved":
                return _fail(f'template "{template_id}" is not an approved template; only approved ones can be refined')
            now = time.time()
            if retire:
                proposal: dict[str, Any] = {"retire": True, "reason": reason.strip(), "created": now}
            else:
                merged = {k: old.get(k) for k in _TEMPLATE_FIELDS}
                merged["kind"] = merged.get("kind") or "display"
                merged.update(changed)
                if all(merged.get(k) == (old.get(k) or ("display" if k == "kind" else None)) for k in _TEMPLATE_FIELDS):
                    return _fail("nothing would change: give the fields you want different")
                problems = _template_problems(library, merged)
                if problems:
                    return _fail(*problems)
                proposal = {**merged, "reason": reason.strip(), "created": now}
            profile.put_template(template_id, {**old, "proposal": proposal, "updated": now})
    except StoreError:
        return _fail("the change could not be saved; try again")
    return {"ok": True, "id": template_id, "status": "approved", "proposal": "retire" if retire else "refine"}


def decide_proposal(profile: ProfileStore, library: Library, tid: str, decision: Any) -> dict[str, Any]:
    """The person's answer to a waiting change: ``"apply"`` makes it the template (or retires it), ``"discard"`` drops it."""
    if decision not in ("apply", "discard"):
        return _fail('proposal must be "apply" or "discard"')
    try:
        with _LOCK:
            old = profile.get_template(tid)
            proposal = old.get("proposal") if old else None
            if old is None or not isinstance(proposal, dict):
                return _fail("no change is waiting for this template")
            record = {k: v for k, v in old.items() if k != "proposal"}
            now = time.time()
            if decision == "apply":
                record["rev"] = old.get("rev", 0) + 1
                if proposal.get("retire"):
                    record["status"] = "retired"
                else:
                    fields = {k: proposal.get(k) for k in _TEMPLATE_FIELDS}
                    problems = _template_problems(library, fields)
                    if problems:
                        return _fail(*problems)
                    record.update(fields)
            record["updated"] = now
            profile.put_template(tid, record)
    except StoreError:
        return _fail("the template could not be saved; try again")
    return {"ok": True, "template": record}


# ---- what the agent reads before it refines -----------------------------------------------------------------------------

_COUNTED = ("used", "expanded", "dismissed", "not_useful")


def _clean_ids(value: Any) -> list[str]:
    return [v for v in value if isinstance(v, str)] if isinstance(value, list) else []


def usage_summary(profile: ProfileStore) -> dict[str, Any]:
    """Counts only, per approved template and for displays made without one, from ``usage.jsonl``. No content."""
    rows = [r for r in profile.read_usage() if isinstance(r, dict)]
    approved = [t for t in list_templates(profile, "approved")]
    stats: dict[str, dict[str, int]] = {
        str(t["id"]): {"shown": 0, **{k: 0 for k in _COUNTED}} for t in approved if isinstance(t.get("id"), str)
    }
    plain = {"shown": 0, **{k: 0 for k in _COUNTED}}
    turns = with_display = 0
    first = last = None
    surface_template: dict[tuple[str, str], str | None] = {}

    def template_of(session: Any, surface: Any) -> str | None:
        key = (str(session), str(surface))
        if key not in surface_template:
            try:
                record = profile.get_surface(session, surface)
            except InvalidName:
                record = None
            tid = record.get("template") if record else None
            surface_template[key] = tid if isinstance(tid, str) else None
        return surface_template[key]

    for row in rows:
        ts = row.get("ts")
        if isinstance(ts, (int, float)):
            first = ts if first is None else min(first, ts)
            last = ts if last is None else max(last, ts)
        if row.get("kind") == "use":
            turns += 1
            templates_used = _clean_ids(row.get("templates_used"))
            surfaces_shown = _clean_ids(row.get("surfaces"))
            if surfaces_shown:
                with_display += 1
            for tid in templates_used:
                if tid in stats:
                    stats[tid]["shown"] += 1
            if len(surfaces_shown) > len(templates_used):
                plain["shown"] += len(surfaces_shown) - len(templates_used)
        elif row.get("kind") == "signal" and row.get("signal") in _COUNTED:
            tid = row.get("template") if isinstance(row.get("template"), str) else None
            if tid is None and row.get("session") is not None and row.get("surface") is not None:
                tid = template_of(row["session"], row["surface"])
            if tid is not None and tid in stats:
                stats[tid][row["signal"]] += 1
            elif tid is None:
                plain[row["signal"]] += 1
    names = {str(t["id"]): t.get("name") for t in approved}
    return {
        "ok": True,
        "turns": turns,
        "turns_with_display": with_display,
        "first_ts": first,
        "last_ts": last,
        "templates": [{"id": tid, "name": names.get(tid), **counts} for tid, counts in stats.items()],
        "plain_displays": plain,
    }


def list_templates(profile: ProfileStore, status: str | None = None) -> list[dict[str, Any]]:
    """Full records (a damaged file is skipped), oldest id first, optionally only those with ``status``."""
    out = []
    for template_id in profile.list_templates():
        t = profile.get_template(template_id)
        if t is None or (status is not None and t.get("status") != status):
            continue
        out.append(t)
    return out


def list_template_summaries(profile: ProfileStore, status: str | None = None) -> list[dict[str, Any]]:
    """What the agent sees when it lists templates: no program or sample, just how to call each one."""
    out = []
    for t in list_templates(profile, status):
        props = (t.get("data_schema") or {}).get("properties")
        out.append(
            {
                "id": t.get("id"),
                "name": t.get("name"),
                "when": t.get("when"),
                "kind": t.get("kind") or "display",
                "status": t.get("status"),
                "rev": t.get("rev"),
                "has_proposal": isinstance(t.get("proposal"), dict),
                "keys": list(props) if isinstance(props, dict) else [],
            }
        )
    return out
