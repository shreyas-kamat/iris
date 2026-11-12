"""Auth is the dashboard's, not the plugin's (plan 0.2, re-read in 2.2).

Hermes's ``auth_middleware`` and the OAuth gate refuse every ``/api/*`` path with 401 unless it is on
``PUBLIC_API_PATHS`` (read at release 2026.9.24). Plugin routes are mounted at ``/api/plugins/<name>/``, so they are
protected as long as none of them is on that list, which is a fixed set of exact paths. A local test cannot run
Hermes's middleware; the real "no login -> 401, login -> 200" check is the live check in plan 2.12.
What a local test can pin is what the plugin controls: no route can be public, and every route takes ``?profile=``.
"""

from __future__ import annotations

from conftest import load_plugin_api

PREFIX = "/api/plugins/iris"

# hermes_cli/dashboard_auth/public_paths.py at v2026.9.24
HERMES_PUBLIC_API_PATHS = {
    "/api/health",
    "/api/status",
    "/api/config/defaults",
    "/api/config/schema",
    "/api/model/info",
    "/api/dashboard/themes",
    "/api/dashboard/plugins",
    "/api/cron/fire",
}


def _routes(hermes_home):
    return [r for r in load_plugin_api().router.routes if hasattr(r, "dependant")]


def test_the_router_has_routes(hermes_home):
    assert _routes(hermes_home)


def test_no_route_is_on_hermes_public_list(hermes_home):
    for route in _routes(hermes_home):
        assert f"{PREFIX}{route.path}" not in HERMES_PUBLIC_API_PATHS, route.path


def test_every_route_lives_under_the_plugin_prefix(hermes_home):
    # include_router(prefix="/api/plugins/iris") is Hermes's doing; a route path must not try to climb out of it.
    for route in _routes(hermes_home):
        assert route.path.startswith("/") and ".." not in route.path, route.path


def test_every_route_takes_a_profile(hermes_home):
    for route in _routes(hermes_home):
        names = {p.name for p in route.dependant.query_params}
        assert "profile" in names, f"{route.methods} {route.path} has no ?profile="
