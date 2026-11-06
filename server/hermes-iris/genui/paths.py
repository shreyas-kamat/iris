"""Where the plugin keeps its files.

The agent-side hooks and the dashboard routes can run in different processes (and, for a named Hermes profile, with
different ``HERMES_HOME``s), so both resolve the same directory: ``<default Hermes root>/iris``, with one
subdirectory per Hermes profile name. This is the only module that imports ``hermes_constants``.
"""

from __future__ import annotations

from pathlib import Path


def hermes_root() -> Path:
    """The default Hermes home (``~/.hermes``), never a named profile's home."""
    try:
        from hermes_constants import get_default_hermes_root

        return Path(get_default_hermes_root())
    except ImportError:  # an older Hermes without the helper
        from hermes_constants import get_hermes_home

        return Path(get_hermes_home())


def iris_root() -> Path:
    return hermes_root() / "iris"


def current_profile() -> str:
    """The Hermes profile this process serves, as the store names it ("default" when it is not a named profile)."""
    try:
        from hermes_constants import get_hermes_home, profile_name_for_home

        name = profile_name_for_home(get_hermes_home())
        return name or "default"
    except Exception:  # noqa: BLE001 - an older Hermes, or no home: the default profile
        return "default"
