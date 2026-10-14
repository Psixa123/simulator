"""Small Roblox Open Cloud client shared by upload_pets.py and publish_place.py (standard library only).

The API key comes from the ROBLOX_API_KEY environment variable (Creator Dashboard > Open Cloud >
API Keys). Never put it in a file in this repository.
"""

import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
API = os.environ.get("ROBLOX_API_BASE", "https://apis.roblox.com").rstrip("/")  # override only for tests
USER_AGENT = "StormCatcher-tools/1.0"
RETRY_STATUS = {429, 500, 502, 503, 504}


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(f"HTTP {status}: {message}")
        self.status = status


def env(name, required=True, hint=""):
    value = os.environ.get(name, "").strip()
    if not value and required:
        sys.exit(f"{name} is not set. {hint}".strip())
    return value


def api_key():
    return env(
        "ROBLOX_API_KEY",
        hint="Create an Open Cloud API key (Creator Dashboard > Open Cloud > API Keys) and store it as an "
        "environment variable; see tools/roblox/README.md.",
    )


def request(method, url, *, body=None, json_body=None, content_type=None, attempts=5):
    """Sends one Open Cloud request and returns the decoded JSON (or {} for an empty body).

    Retries rate limits and server errors with backoff; other errors raise ApiError with Roblox's message.
    """
    headers = {"x-api-key": api_key(), "User-Agent": USER_AGENT, "Accept": "application/json"}
    if json_body is not None:
        body = json.dumps(json_body).encode()
        content_type = "application/json"
    if content_type:
        headers["Content-Type"] = content_type
    for attempt in range(1, attempts + 1):
        req = urllib.request.Request(url, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                raw = response.read()
                return json.loads(raw) if raw.strip() else {}
        except urllib.error.HTTPError as error:
            raw = error.read().decode(errors="replace")
            if error.code in RETRY_STATUS and attempt < attempts:
                wait = error.headers.get("Retry-After")
                time.sleep(float(wait) if wait and wait.replace(".", "", 1).isdigit() else 2**attempt)
                continue
            raise ApiError(error.code, describe(raw)) from None
        except urllib.error.URLError as error:
            if attempt < attempts:
                time.sleep(2**attempt)
                continue
            raise ApiError(0, f"can't reach {url} ({error.reason})") from None
    raise ApiError(0, "no response")


def describe(raw):
    """Roblox error bodies are JSON in a few shapes; return the most useful message."""
    try:
        data = json.loads(raw)
    except ValueError:
        return raw.strip()[:500] or "(empty response)"
    if isinstance(data, dict):
        for key in ("message", "Message", "error", "title"):
            if isinstance(data.get(key), str) and data[key]:
                detail = data.get("errors") or data.get("details") or ""
                return f"{data[key]} {json.dumps(detail) if detail else ''}".strip()
        if isinstance(data.get("errors"), list) and data["errors"]:
            return "; ".join(str(e.get("message", e)) if isinstance(e, dict) else str(e) for e in data["errors"])
    return json.dumps(data)[:500]


def multipart(fields):
    """Encodes multipart/form-data. fields: list of (name, filename or None, content_type or None, bytes)."""
    boundary = "----StormCatcher" + uuid.uuid4().hex
    chunks = []
    for name, filename, content_type, data in fields:
        disposition = f'form-data; name="{name}"'
        if filename:
            disposition += f'; filename="{filename}"'
        chunks.append(f"--{boundary}\r\nContent-Disposition: {disposition}\r\n".encode())
        if content_type:
            chunks.append(f"Content-Type: {content_type}\r\n".encode())
        chunks.append(b"\r\n" + data + b"\r\n")
    chunks.append(f"--{boundary}--\r\n".encode())
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"
