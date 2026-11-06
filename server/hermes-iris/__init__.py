"""hermes-iris: the Hermes side of Iris's generated UI.

Hermes loads this package for the agent (tools, hooks, skill) and, separately, ``dashboard/plugin_api.py`` for the
routes. The two can run in different processes and share nothing but files (see ``genui/store.py``).
"""

from __future__ import annotations

import logging

__version__ = "0.1.0"

#: The OpenUI Lang version this plugin validates against.
OPENUI_VERSION = "1.0"

_log = logging.getLogger("hermes_iris")


def register(ctx) -> None:
    """Called by Hermes when the plugin is enabled. Tools, hooks and the skill are registered here as they land."""
    from .genui import guards, tool

    ctx.register_tool(name="iris_ui", toolset="iris", schema=tool.SCHEMA, handler=tool.handle_iris_ui)
    ctx.register_hook("pre_tool_call", guards.on_pre_tool_call)
    ctx.register_hook("transform_tool_result", guards.on_transform_tool_result)
    _log.info("hermes-iris %s loaded", __version__)
