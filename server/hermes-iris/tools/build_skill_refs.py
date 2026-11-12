"""Rewrites ``skills/iris-genui/references/library.md`` from the catalog. Run after the library changes:

    python tools/build_skill_refs.py            # write
    python tools/build_skill_refs.py --check    # exit 1 if the file is stale

Hermes is not needed. The plugin directory is loaded as a package under a private name, as ``plugin_api.py`` does.
"""

from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load():
    name = "hermes_iris"
    spec = importlib.util.spec_from_file_location(name, ROOT / "__init__.py", submodule_search_locations=[str(ROOT)])
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return importlib.import_module(f"{name}.genui.skill")


def main(argv: list[str]) -> int:
    skill = _load()
    text = skill.render_library_md()
    path = skill.library_md_path()
    current = path.read_bytes().decode("utf-8") if path.exists() else None
    if "--check" in argv:
        if current != text:
            print(f"{path} is stale; run tools/build_skill_refs.py")
            return 1
        return 0
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))
    print(f"wrote {path} ({len(text)} characters)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
