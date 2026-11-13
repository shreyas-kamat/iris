from __future__ import annotations

import base64
import json
import logging
import os
import subprocess

import pytest
from conftest import APNS_KEY_ID, APNS_TEAM

SID = "20261113_051659_b9bbb3"
TOKEN = "ab" * 32
T0 = 1_800_000_000.0


@pytest.fixture
def apns(plugin):
    from hermes_iris.push import apns

    apns._TOKENS.clear()
    return apns


@pytest.fixture
def cfg(apns, apns_key, hermes_home):
    c = apns.load_config(hermes_home / "iris")
    assert c is not None
    return c


def _b64(part: str) -> bytes:
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))


def approval_notice(**kw) -> dict:
    return {"event_id": "17", "kind": "approval", "session_id": SID, "title": "Look!", "body": "rm -rf /tmp/x",
            "category": "approval", "collapse": f"approval-{SID}", **kw}


class FakeCurl:
    """Stands in for ``subprocess.run``: records argv and stdin and answers with a status line and body."""

    def __init__(self, status: str = "200", body: str = "", returncode: int = 0) -> None:
        self.status, self.body, self.returncode = status, body, returncode
        self.calls: list[tuple[list[str], bytes]] = []

    def __call__(self, argv, *, input=None, capture_output=False, timeout=None, check=False):  # noqa: A002
        self.calls.append((list(argv), input))
        out = f"{self.body}\n{self.status}".encode() if self.returncode == 0 else b""
        return subprocess.CompletedProcess(argv, self.returncode, out, b"curl: (7) Failed to connect")


# ---- config -------------------------------------------------------------------------------------------------------


def test_load_config(cfg):
    assert (cfg.team_id, cfg.key_id, cfg.bundle_id, cfg.environment) == (
        APNS_TEAM, APNS_KEY_ID, "com.iflotech.iris", "sandbox")


def test_no_config_is_none(apns, hermes_home):
    assert apns.load_config(hermes_home / "iris") is None


@pytest.mark.parametrize("change", [{"environment": "staging"}, {"team_id": ""}, {"key_path": "missing.p8"}])
def test_bad_config_is_none(apns, apns_key, hermes_home, change):
    path = hermes_home / "iris" / "push" / "apns.json"
    data = json.loads(path.read_text("utf-8"))
    path.write_text(json.dumps({**data, **change}), "utf-8")
    assert apns.load_config(hermes_home / "iris") is None


@pytest.mark.skipif(os.name != "posix", reason="file modes are POSIX only")
def test_key_file_mode_checked(apns, apns_key, hermes_home):
    p8 = hermes_home / "iris" / "push" / f"AuthKey_{APNS_KEY_ID}.p8"
    os.chmod(p8, 0o644)
    assert apns.load_config(hermes_home / "iris") is None
    os.chmod(p8, 0o600)
    assert apns.load_config(hermes_home / "iris") is not None


def test_available_needs_curl(apns, monkeypatch):
    monkeypatch.setattr(apns.shutil, "which", lambda name: None)
    assert apns.available() is False
    monkeypatch.setattr(apns.shutil, "which", lambda name: "/usr/bin/curl")
    assert apns.available() is True


# ---- provider token -------------------------------------------------------------------------------------------------


def test_jwt_header_and_claims(apns, cfg, apns_key):
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

    jwt = apns.provider_token(cfg, T0)
    head, claims, sig = jwt.split(".")
    assert json.loads(_b64(head)) == {"alg": "ES256", "kid": APNS_KEY_ID}
    assert json.loads(_b64(claims)) == {"iss": APNS_TEAM, "iat": int(T0)}
    raw = _b64(sig)
    assert len(raw) == 64  # JOSE raw r || s, not DER
    der = encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
    apns_key.public_key().verify(der, f"{head}.{claims}".encode(), ec.ECDSA(hashes.SHA256()))


def test_token_cached_50_min(apns, cfg):
    first = apns.provider_token(cfg, T0)
    assert apns.provider_token(cfg, T0 + 49 * 60) == first
    renewed = apns.provider_token(cfg, T0 + 50 * 60 + 1)
    assert renewed != first
    assert json.loads(_b64(renewed.split(".")[1]))["iat"] == int(T0 + 50 * 60 + 1)


# ---- request ----------------------------------------------------------------------------------------------------------


def test_request_for_approval(apns, cfg):
    url, headers, body = apns.build_request(cfg, TOKEN, approval_notice(), now=T0)
    assert url == f"https://api.sandbox.push.apple.com/3/device/{TOKEN}"
    assert headers == {
        "apns-push-type": "alert",
        "apns-topic": "com.iflotech.iris",
        "apns-priority": "10",
        "apns-collapse-id": f"approval-{SID}",
        "authorization": f"bearer {apns.provider_token(cfg, T0)}",
    }
    assert json.loads(body) == {
        "aps": {"alert": {"title": "Look!", "body": "rm -rf /tmp/x"}, "sound": "default", "thread-id": SID,
                "category": "iris.approval"},
        "iris": {"kind": "approval", "session_id": SID, "event_id": "17"},
    }


def test_production_host(apns, cfg):
    from dataclasses import replace

    url, _, _ = apns.build_request(replace(cfg, environment="production"), TOKEN, approval_notice(), now=T0)
    assert url == f"https://api.push.apple.com/3/device/{TOKEN}"


def test_text_mode_body_absent(apns, cfg):
    notice = {"event_id": "18", "kind": "reply", "session_id": SID, "title": "Attention!", "body": None,
              "category": None, "collapse": f"reply-{SID}"}
    _, _, body = apns.build_request(cfg, TOKEN, notice, now=T0)
    data = json.loads(body)
    assert data["aps"]["alert"] == {"title": "Attention!"}
    assert "category" not in data["aps"]
    assert data["iris"] == {"kind": "reply", "session_id": SID, "event_id": "18"}


def test_text_and_emoji_sent_intact(apns, cfg):
    title = 'Hey "you" \\ 👀 ' + "x" * 80
    _, _, body = apns.build_request(cfg, TOKEN, approval_notice(title=title), now=T0)
    assert json.loads(body)["aps"]["alert"]["title"] == title


def test_long_collapse_id_fits_apns_limit(apns, cfg):
    _, headers, _ = apns.build_request(cfg, TOKEN, approval_notice(collapse="job-" + "c" * 90), now=T0)
    assert len(headers["apns-collapse-id"].encode()) <= 64


def test_approval_done_is_not_for_ios(apns, cfg):
    with pytest.raises(ValueError):
        apns.build_request(cfg, TOKEN, {"event_id": "1", "kind": "approval_done", "session_id": SID,
                                        "collapse": f"approval-{SID}"}, now=T0)


# ---- send -------------------------------------------------------------------------------------------------------------


def test_send_keeps_secrets_out_of_argv(apns, cfg):
    curl = FakeCurl("200")
    assert apns.send(cfg, TOKEN, approval_notice(), run=curl, now=T0) == "ok"
    (argv, stdin), = curl.calls
    joined = " ".join(argv)
    assert argv[0] == "curl" and "--http2" in argv and "-K" in argv and argv[argv.index("-K") + 1] == "-"
    for secret in ("bearer", TOKEN, "rm -rf", apns.provider_token(cfg, T0)):
        assert secret not in joined
    text = stdin.decode("utf-8")
    assert f'url = "https://api.sandbox.push.apple.com/3/device/{TOKEN}"' in text
    assert f'header = "authorization: bearer {apns.provider_token(cfg, T0)}"' in text
    assert "data-binary = " in text


def test_send_config_quotes_survive_curl_unescaping(apns, cfg):
    curl = FakeCurl("200")
    title = 'say "hi" \\ there'
    apns.send(cfg, TOKEN, approval_notice(title=title), run=curl, now=T0)
    line = next(l for l in curl.calls[0][1].decode().splitlines() if l.startswith("data-binary = "))
    quoted = line[len("data-binary = "):]
    assert quoted.startswith('"') and quoted.endswith('"')
    # curl's config unescaping: \\ -> \, \" -> "
    unescaped = quoted[1:-1].replace('\\\\', "\0").replace('\\"', '"').replace("\0", "\\")
    assert json.loads(unescaped)["aps"]["alert"]["title"] == title


@pytest.mark.parametrize(
    ("status", "body", "rc", "want"),
    [
        ("200", "", 0, "ok"),
        ("410", '{"reason":"Unregistered"}', 0, "drop_device"),
        ("400", '{"reason":"BadDeviceToken"}', 0, "drop_device"),
        ("400", '{"reason":"PayloadTooLarge"}', 0, "fail"),
        ("429", '{"reason":"TooManyRequests"}', 0, "retry"),
        ("503", "", 0, "retry"),
        ("000", "", 7, "retry"),
        ("403", '{"reason":"ExpiredProviderToken"}', 0, "retry"),
        ("403", '{"reason":"InvalidProviderToken"}', 0, "fail"),
    ],
)
def test_410_drops_device(apns, cfg, status, body, rc, want):
    assert apns.send(cfg, TOKEN, approval_notice(), run=FakeCurl(status, body, rc), now=T0) == want


def test_expired_provider_token_is_renewed(apns, cfg):
    first = apns.provider_token(cfg, T0)
    apns.send(cfg, TOKEN, approval_notice(), run=FakeCurl("403", '{"reason":"ExpiredProviderToken"}'), now=T0)
    assert apns.provider_token(cfg, T0 + 1) != first


def test_send_survives_a_hung_curl(apns, cfg):
    def hang(argv, **kw):
        raise subprocess.TimeoutExpired(argv, 20)

    assert apns.send(cfg, TOKEN, approval_notice(), run=hang, now=T0) == "retry"


def test_nothing_logged_has_token(apns, cfg, caplog):
    caplog.set_level(logging.DEBUG)
    jwt = apns.provider_token(cfg, T0)
    for status, body, rc in [("410", '{"reason":"Unregistered"}', 0), ("000", "", 7), ("500", "oops", 0),
                             ("400", '{"reason":"BadDeviceToken"}', 0)]:
        apns.send(cfg, TOKEN, approval_notice(), run=FakeCurl(status, body, rc), now=T0)
    assert caplog.records  # failures are logged...
    for secret in (TOKEN, jwt, "bearer", "rm -rf", "Look!", "Failed to connect"):
        assert secret not in caplog.text  # ...without the token, the provider token, content or curl's stderr


def test_long_body_trimmed_to_apns_limit(apns, cfg):
    _, _, body = apns.build_request(cfg, TOKEN, approval_notice(body="é" * 5000), now=T0)
    assert len(body) <= 4096
    alert = json.loads(body)["aps"]["alert"]
    assert alert["title"] == "Look!" and alert["body"].endswith("…") and len(alert["body"]) > 1000
