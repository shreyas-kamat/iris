"""APNs delivery for iPhones: token-auth (ES256) requests sent straight to Apple with the system ``curl``.

HTTP/2 comes from ``curl --http2`` because the Hermes runtime has no HTTP/2 client. The URL, the headers (with the
provider token) and the body go to curl on stdin as a config file (``-K -``), so none of them appears in the process
list. Nothing here logs the device token, the provider token, the key, the notification's text, or curl's stderr.

Config: ``<iris root>/push/apns.json``::

    {"team_id": "ABCDE12345", "key_id": "KEY1234567", "bundle_id": "com.iflotech.iris",
     "key_path": "AuthKey_KEY1234567.p8", "environment": "sandbox" | "production"}

``key_path`` is relative to that ``push`` directory (or absolute). On POSIX the key file must be mode 0600.
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import os
import re
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Literal

_log = logging.getLogger("hermes_iris")

#: A provider token is good for an hour; Apple refuses one renewed more often than every 20 minutes.
TOKEN_TTL_S = 50 * 60
PAYLOAD_MAX = 4096
COLLAPSE_MAX = 64
CURL_MAX_TIME_S = 15

HOSTS = {"sandbox": "api.sandbox.push.apple.com", "production": "api.push.apple.com"}
SENDABLE = ("reply", "approval", "job", "test")

_APPLE_ID = re.compile(r"[A-Z0-9]{10}")
_BUNDLE = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]{0,154}")
_DEVICE_TOKEN = re.compile(r"[0-9a-f]{64,200}")
_REASON = re.compile(r"[A-Za-z]{1,64}")

Result = Literal["ok", "drop_device", "retry", "fail"]


@dataclass(frozen=True)
class ApnsConfig:
    team_id: str
    key_id: str
    bundle_id: str
    key_path: Path
    environment: str


#: (team, key id, key path) -> (iat, jwt). Cleared when Apple says the token expired.
_TOKENS: dict[tuple[str, str, str], tuple[float, str]] = {}
_TOKENS_LOCK = threading.Lock()
_last_warning: str | None = None


def _warn_once(reason: str | None) -> None:
    """Logs why APNs is off, once per distinct reason (the worker asks every second)."""
    global _last_warning
    if reason is not None and reason != _last_warning:
        _log.warning("hermes-iris: APNs is off: %s", reason)
    _last_warning = reason


def available() -> bool:
    """Whether the system ``curl`` is there to send with."""
    return shutil.which("curl") is not None


def load_config(root: Path) -> ApnsConfig | None:
    """The APNs settings under ``root`` (``<hermes root>/iris``), or ``None`` when absent or not usable."""
    push = Path(root) / "push"
    path = push / "apns.json"
    if not path.is_file():
        _warn_once(None)
        return None
    try:
        data = json.loads(path.read_text("utf-8"))
    except (OSError, ValueError):
        _warn_once("apns.json is not readable JSON")
        return None
    if not isinstance(data, dict):
        _warn_once("apns.json is not a JSON object")
        return None
    team, key_id, bundle = data.get("team_id"), data.get("key_id"), data.get("bundle_id")
    env, key_path = data.get("environment"), data.get("key_path")
    if not (isinstance(team, str) and _APPLE_ID.fullmatch(team)):
        _warn_once("team_id must be the 10-character Apple team id")
        return None
    if not (isinstance(key_id, str) and _APPLE_ID.fullmatch(key_id)):
        _warn_once("key_id must be the 10-character key id")
        return None
    if not (isinstance(bundle, str) and _BUNDLE.fullmatch(bundle)):
        _warn_once("bundle_id is not a bundle id")
        return None
    if env not in HOSTS:
        _warn_once("environment must be 'sandbox' or 'production'")
        return None
    if not isinstance(key_path, str) or not key_path:
        _warn_once("key_path is missing")
        return None
    key = Path(key_path) if os.path.isabs(key_path) else push / key_path
    if not key.is_file():
        _warn_once("the key file named by key_path is missing")
        return None
    if os.name == "posix" and key.stat().st_mode & 0o077:
        _warn_once("the key file must be mode 0600")
        return None
    _warn_once(None)
    return ApnsConfig(team, key_id, bundle, key, env)


# ---- provider token ---------------------------------------------------------------------------------------------------


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _sign(cfg: ApnsConfig, iat: int) -> str:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

    key = serialization.load_pem_private_key(cfg.key_path.read_bytes(), password=None)
    if not isinstance(key, ec.EllipticCurvePrivateKey) or key.curve.name != "secp256r1":
        raise ValueError("the APNs key is not a P-256 key")
    head = _b64(json.dumps({"alg": "ES256", "kid": cfg.key_id}, separators=(",", ":")).encode())
    claims = _b64(json.dumps({"iss": cfg.team_id, "iat": iat}, separators=(",", ":")).encode())
    r, s = decode_dss_signature(key.sign(f"{head}.{claims}".encode(), ec.ECDSA(hashes.SHA256())))
    return f"{head}.{claims}.{_b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"


def provider_token(cfg: ApnsConfig, now: float | None = None) -> str:
    """The ES256 JWT APNs wants in ``authorization``, reused for 50 minutes."""
    t = time.time() if now is None else now
    cache_key = (cfg.team_id, cfg.key_id, str(cfg.key_path))
    with _TOKENS_LOCK:
        cached = _TOKENS.get(cache_key)
        if cached is not None and 0 <= t - cached[0] < TOKEN_TTL_S:
            return cached[1]
        jwt = _sign(cfg, int(t))
        _TOKENS[cache_key] = (t, jwt)
        return jwt


# ---- request ----------------------------------------------------------------------------------------------------------


def _collapse_id(collapse: object) -> str | None:
    if not isinstance(collapse, str) or not collapse:
        return None
    if len(collapse.encode("utf-8")) <= COLLAPSE_MAX:
        return collapse
    return hashlib.sha256(collapse.encode("utf-8")).hexdigest()[:COLLAPSE_MAX]


def _payload(notice: dict[str, Any]) -> bytes:
    title = notice.get("title") or "Iris"
    body = notice.get("body") or None
    while True:
        alert: dict[str, Any] = {"title": title}
        if body:
            alert["body"] = body
        aps: dict[str, Any] = {"alert": alert, "sound": "default"}
        if notice.get("session_id"):
            aps["thread-id"] = notice["session_id"]
        if notice.get("category") == "approval":
            aps["category"] = "iris.approval"
        data = {"aps": aps, "iris": {"kind": notice.get("kind"), "session_id": notice.get("session_id"),
                                     "event_id": notice.get("event_id")}}
        raw = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        excess = len(raw) - PAYLOAD_MAX
        if excess <= 0:
            return raw
        if not body:
            raise ValueError("the notification is too large for APNs")
        raw_body = body.encode("utf-8")
        cut = len(raw_body) - excess - 3  # "…" is three bytes; a JSON escape can only make the cut generous
        body = raw_body[:cut].decode("utf-8", "ignore").rstrip() + "…" if cut > 0 else None


def build_request(
    cfg: ApnsConfig, device_token: str, notice: dict[str, Any], now: float | None = None
) -> tuple[str, dict[str, str], bytes]:
    """The URL, headers and JSON body of one APNs alert. ``approval_done`` is Android-only and refused here."""
    if notice.get("kind") not in SENDABLE:
        raise ValueError("this notice is not sent to iOS")
    if not isinstance(device_token, str) or _DEVICE_TOKEN.fullmatch(device_token) is None:
        raise ValueError("not an APNs device token")
    url = f"https://{HOSTS[cfg.environment]}/3/device/{device_token}"
    headers = {
        "apns-push-type": "alert",
        "apns-topic": cfg.bundle_id,
        "apns-priority": "10",
    }
    collapse = _collapse_id(notice.get("collapse"))
    if collapse is not None:
        headers["apns-collapse-id"] = collapse
    headers["authorization"] = f"bearer {provider_token(cfg, now)}"
    return url, headers, _payload(notice)


# ---- send -------------------------------------------------------------------------------------------------------------


def _quote(value: str) -> str:
    """A double-quoted curl config value (curl unescapes ``\\\\`` and ``\\"`` inside quotes)."""
    if "\n" in value or "\r" in value:
        raise ValueError("a curl config value cannot hold a line break")
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _curl_config(url: str, headers: dict[str, str], body: bytes) -> bytes:
    lines = [f"url = {_quote(url)}"]
    lines += [f"header = {_quote(f'{k}: {v}')}" for k, v in headers.items()]
    lines.append(f"header = {_quote('content-type: application/json')}")
    lines.append(f"data-binary = {_quote(body.decode('utf-8'))}")
    return ("\n".join(lines) + "\n").encode("utf-8")


def _reason(body: str) -> str:
    try:
        reason = json.loads(body).get("reason")
    except (ValueError, AttributeError):
        return ""
    return reason if isinstance(reason, str) and _REASON.fullmatch(reason) else ""


def send(
    cfg: ApnsConfig,
    device_token: str,
    notice: dict[str, Any],
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
    now: float | None = None,
) -> Result:
    """Sends one alert. ``drop_device`` means Apple says the token is dead; ``retry`` is worth one more try."""
    try:
        url, headers, body = build_request(cfg, device_token, notice, now)
        config = _curl_config(url, headers, body)
    except Exception as e:  # noqa: BLE001 - a bad key or notice: never raise into the worker
        _log.warning("hermes-iris: APNs request not built (%s)", type(e).__name__)
        return "fail"
    argv = ["curl", "--http2", "-sS", "--max-time", str(CURL_MAX_TIME_S), "-w", "\n%{http_code}", "-K", "-"]
    try:
        done = run(argv, input=config, capture_output=True, timeout=CURL_MAX_TIME_S + 5, check=False)
    except subprocess.TimeoutExpired:
        _log.warning("hermes-iris: APNs send timed out")
        return "retry"
    except OSError as e:
        _log.warning("hermes-iris: APNs send could not run curl (%s)", type(e).__name__)
        return "fail"
    if done.returncode != 0:
        _log.warning("hermes-iris: APNs send failed (curl exit %s)", done.returncode)
        return "retry"
    out = (done.stdout or b"").decode("utf-8", "replace")
    text, _, status = out.rpartition("\n")
    status = status.strip()
    if status == "200":
        return "ok"
    reason = _reason(text)
    _log.warning("hermes-iris: APNs answered %s %s", status if status.isdigit() else "?", reason)
    if status == "410" or (status == "400" and reason == "BadDeviceToken"):
        return "drop_device"
    if status == "403" and reason == "ExpiredProviderToken":
        with _TOKENS_LOCK:
            _TOKENS.clear()
        return "retry"
    if status == "429" or (status.isdigit() and int(status) >= 500):
        return "retry"
    return "fail"


__all__ = ["ApnsConfig", "available", "build_request", "load_config", "provider_token", "send"]
