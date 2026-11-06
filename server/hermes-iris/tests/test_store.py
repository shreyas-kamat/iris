from __future__ import annotations

import json
import os
import sys

import pytest


@pytest.fixture
def store_mod(plugin):
    from hermes_iris.genui import store

    return store


@pytest.fixture
def root(tmp_path):
    return tmp_path / "iris"


@pytest.fixture
def store(store_mod, root):
    return store_mod.Store(root)


GOOD = ["a", "A1", "work", "my-profile", "my_profile", "20261106_193512_ab12cd", "x" * 64]
BAD = ["", ".", "..", "a/b", "a\\b", "../x", "a b", "é", "a.b", ".hidden", "x" * 65, "a\x00b", "a\nb", "C:", "a:b"]


@pytest.mark.parametrize("name", GOOD)
def test_good_names(store_mod, name):
    assert store_mod.safe_component(name) == name


@pytest.mark.parametrize("name", BAD)
def test_bad_names(store_mod, name):
    with pytest.raises(store_mod.InvalidName):
        store_mod.safe_component(name)


def test_non_strings_are_invalid(store_mod):
    for value in (None, 3, b"abc", ["a"]):
        with pytest.raises(store_mod.InvalidName):
            store_mod.safe_component(value)


def test_profile_round_trip(store):
    assert store.profile("default").get_profile() is None
    store.profile("default").put_profile({"name": "Ada", "n": 1, "é": "ü"})
    assert store.profile("default").get_profile() == {"name": "Ada", "n": 1, "é": "ü"}


def test_profiles_are_isolated(store):
    store.profile("a").put_profile({"who": "a"})
    store.profile("b").put_profile({"who": "b"})
    assert store.profile("a").get_profile() == {"who": "a"}
    assert store.profile("b").get_profile() == {"who": "b"}


def test_corrupt_profile_reads_as_missing(store, root):
    p = store.profile("default")
    p.put_profile({"a": 1})
    (root / "default" / "profile.json").write_text("{not json", "utf-8")
    assert p.get_profile() is None


def test_profile_must_be_an_object(store, store_mod):
    with pytest.raises(store_mod.StoreError):
        store.profile("default").put_profile(["not", "an", "object"])  # type: ignore[arg-type]


def test_templates(store):
    p = store.profile("default")
    assert p.list_templates() == []
    p.put_template("deploy-status", {"title": "Deploys", "program": 'root = Text("x")'})
    p.put_template("cron", {"title": "Cron"})
    assert p.get_template("deploy-status")["title"] == "Deploys"
    assert p.list_templates() == ["cron", "deploy-status"]
    assert p.delete_template("cron") is True
    assert p.delete_template("cron") is False
    assert p.get_template("cron") is None
    assert p.list_templates() == ["deploy-status"]


def test_surfaces(store):
    p = store.profile("default")
    assert p.get_surface("20261106_a", "s1") is None
    assert p.list_surfaces("20261106_a") == []
    p.put_surface("20261106_a", "s1", {"rev": 1, "code": 'root = Text("a")'})
    p.put_surface("20261106_a", "s2", {"rev": 1, "code": 'root = Text("b")'})
    p.put_surface("20261106_b", "s1", {"rev": 7, "code": 'root = Text("c")'})
    assert p.get_surface("20261106_a", "s1")["rev"] == 1
    assert p.get_surface("20261106_b", "s1")["rev"] == 7
    assert p.list_surfaces("20261106_a") == ["s1", "s2"]
    p.put_surface("20261106_a", "s1", {"rev": 2, "code": 'root = Text("a2")'})
    assert p.get_surface("20261106_a", "s1")["rev"] == 2
    assert p.delete_surface("20261106_a", "s1") is True
    assert p.delete_surface("20261106_a", "s1") is False
    assert p.list_surfaces("20261106_a") == ["s2"]


def test_traversal_is_refused_and_writes_nothing_outside(store, store_mod, root, tmp_path):
    p = store.profile("default")
    for call in (
        lambda: p.put_surface("../evil", "s", {}),
        lambda: p.put_surface("ok", "../../evil", {}),
        lambda: p.put_surface("ok/..", "s", {}),
        lambda: p.put_template("../t", {}),
        lambda: p.get_template("..\\t"),
        lambda: p.get_surface("a/b", "s"),
        lambda: p.list_surfaces(".."),
        lambda: store.profile("../other"),
        lambda: store.profile("a/b"),
    ):
        with pytest.raises(store_mod.InvalidName):
            call()
    written = {path.relative_to(tmp_path).as_posix() for path in tmp_path.rglob("*") if path.is_file()}
    assert written == set()


def test_symlinked_profile_dir_cannot_escape(store, store_mod, root, tmp_path):
    outside = tmp_path / "outside"
    outside.mkdir()
    root.mkdir()
    try:
        os.symlink(outside, root / "evil", target_is_directory=True)
    except (OSError, NotImplementedError):
        pytest.skip("symlinks need privileges here")
    with pytest.raises(store_mod.StoreError):
        store.profile("evil").put_profile({"a": 1})
    assert list(outside.iterdir()) == []


def test_writes_are_atomic_and_leave_no_temp_files(store, root, monkeypatch):
    p = store.profile("default")
    p.put_profile({"v": 1})

    def boom(src, dst):
        raise OSError("disk went away")

    monkeypatch.setattr(os, "replace", boom)
    with pytest.raises(OSError):
        p.put_profile({"v": 2})
    monkeypatch.undo()

    assert p.get_profile() == {"v": 1}
    assert [f.name for f in (root / "default").iterdir()] == ["profile.json"]


@pytest.mark.skipif(sys.platform == "win32", reason="POSIX modes")
def test_files_are_private(store, root):
    store.profile("default").put_profile({"a": 1})
    assert (root / "default" / "profile.json").stat().st_mode & 0o077 == 0


def test_usage_appends_and_rotates_at_the_limit(store_mod, root):
    store = store_mod.Store(root, usage_max_bytes=2_000)
    p = store.profile("default")
    row = {"event": "used", "template": "t" * 100}
    for i in range(60):
        p.append_usage({**row, "i": i})
    current = root / "default" / "usage.jsonl"
    rotated = root / "default" / "usage.jsonl.1"
    assert rotated.exists()
    assert current.stat().st_size < 2_000 + 200
    assert rotated.stat().st_size >= 1_000
    rows = p.read_usage()
    assert rows == sorted(rows, key=lambda r: r["i"])
    assert rows[-1]["i"] == 59
    assert not (root / "default" / "usage.jsonl.2").exists()


def test_usage_default_limit_is_one_mebibyte(store_mod):
    assert store_mod.USAGE_MAX_BYTES == 1024 * 1024


def test_usage_skips_damaged_lines(store, root):
    p = store.profile("default")
    p.append_usage({"i": 1})
    with (root / "default" / "usage.jsonl").open("a", encoding="utf-8") as f:
        f.write("{broken\n")
    p.append_usage({"i": 2})
    assert [r["i"] for r in p.read_usage()] == [1, 2]


def test_reset_deletes_one_profile_only(store, root):
    store.profile("a").put_profile({"x": 1})
    store.profile("a").put_surface("s", "u", {"rev": 1})
    store.profile("b").put_profile({"x": 2})
    store.profile("a").reset()
    assert not (root / "a").exists()
    assert store.profile("a").get_profile() is None
    assert store.profile("b").get_profile() == {"x": 2}
    store.profile("a").reset()  # idempotent


def test_unicode_is_stored_as_utf8(store, root):
    store.profile("default").put_profile({"text": "naïve — ü"})
    raw = (root / "default" / "profile.json").read_bytes().decode("utf-8")
    assert "naïve — ü" in raw
    assert json.loads(raw) == {"text": "naïve — ü"}


def test_iris_root_is_under_the_hermes_root(plugin, hermes_home):
    from hermes_iris.genui import paths

    assert paths.iris_root() == hermes_home / "iris"
