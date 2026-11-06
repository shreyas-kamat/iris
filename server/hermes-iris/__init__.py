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
    _log.info("hermes-iris %s loaded", __version__)
