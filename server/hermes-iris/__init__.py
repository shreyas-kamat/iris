"""hermes-iris: the Hermes side of Iris's generated UI.

Hermes loads this package for the agent (tools, hooks, skill) and, separately, ``dashboard/plugin_api.py`` for the
routes. The two can run in different processes and share nothing but files (see ``genui/store.py``).
"""

from __future__ import annotations

import logging

__version__ = "0.2.0"

#: The OpenUI Lang version this plugin validates against.
OPENUI_VERSION = "1.0"

_log = logging.getLogger("hermes_iris")


def register(ctx) -> None:
    """Called by Hermes when the plugin is enabled. Tools, hooks and the skill are registered here as they land."""
    from .genui import context, guards, personal_tools, skill, tool, usage

    ctx.register_tool(name="iris_ui", toolset="iris", schema=tool.SCHEMA, handler=tool.handle_iris_ui)
    for schema, handler in personal_tools.TOOLS:
        ctx.register_tool(name=schema["name"], toolset="iris", schema=schema, handler=handler)
    ctx.register_hook("pre_llm_call", context.on_pre_llm_call)
    ctx.register_hook("pre_tool_call", guards.on_pre_tool_call)
    ctx.register_hook("transform_tool_result", guards.on_transform_tool_result)
    ctx.register_hook("post_llm_call", usage.on_post_llm_call)
    for name, directory, description in (
        (skill.SKILL_NAME, skill.SKILL_DIR, skill.SKILL_DESCRIPTION),
        (skill.STUDY_SKILL_NAME, skill.STUDY_SKILL_DIR, skill.STUDY_SKILL_DESCRIPTION),
        (skill.REFINE_SKILL_NAME, skill.REFINE_SKILL_DIR, skill.REFINE_SKILL_DESCRIPTION),
    ):
        try:
            ctx.register_skill(name, directory / "SKILL.md", description=description)
        except Exception:  # noqa: BLE001 - an older Hermes without plugin skills still gets the tools and the hooks
            _log.warning("hermes-iris: could not register the %s skill", name, exc_info=True)
    _log.info("hermes-iris %s loaded", __version__)
