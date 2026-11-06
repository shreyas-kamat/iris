"""The component libraries the plugin knows (``catalog/*.library.json``).

``v1.library.json`` is exported from Dart (the Iris catalog is defined once, in
``lib/features/genui/render/iris_library.dart``) and checked in; Python builds the validator and the prompt from that
file. Refresh it with ``IRIS_WRITE_CATALOG=1 flutter test test/features/genui/iris_library_test.dart``.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from ..openui.library import Library

CATALOG_DIR = Path(__file__).resolve().parent.parent / "catalog"


@lru_cache(maxsize=8)
def _load(path: str, mtime_ns: int) -> Library:  # mtime is part of the key so an upgrade in place is picked up
    return Library.load(path)


def load(name: str) -> Library:
    path = CATALOG_DIR / f"{name}.library.json"
    return _load(str(path), path.stat().st_mtime_ns)


def v1() -> Library:
    return load("v1")


def library_ids() -> list[str]:
    """The ids of every library file, sorted."""
    ids = []
    for path in sorted(CATALOG_DIR.glob("*.library.json")):
        lib = _load(str(path), path.stat().st_mtime_ns)
        if lib.id:
            ids.append(lib.id)
    return ids
