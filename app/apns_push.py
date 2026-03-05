from __future__ import annotations

import os
import time
from dataclasses import dataclass

import httpx
import jwt

from app.push_devices import PushDevice, disable_push_device


INVALID_TOKEN_REASONS = {
    "BadDeviceToken",
    "DeviceTokenNotForTopic",
    "Unregistered",
}


@dataclass
class PushSendSummary:
    sent: int = 0
    failed: int = 0
    disabled: int = 0


def _apns_host() -> str:
    env = os.getenv("APNS_ENV", "production").strip().lower()
    if env == "sandbox":
        return "https://api.sandbox.push.apple.com"
    return "https://api.push.apple.com"


def _private_key() -> str:
    raw = os.getenv("APNS_PRIVATE_KEY", "").strip()
    if not raw:
        return ""
    return raw.replace("\\n", "\n")


def _jwt_token() -> str:
    key_id = os.getenv("APNS_KEY_ID", "").strip()
    team_id = os.getenv("APNS_TEAM_ID", "").strip()
    private_key = _private_key()
    if not key_id or not team_id or not private_key:
        raise RuntimeError("APNS credentials are incomplete (APNS_KEY_ID/APNS_TEAM_ID/APNS_PRIVATE_KEY).")
    now = int(time.time())
    return jwt.encode(
        {"iss": team_id, "iat": now},
        private_key,
        algorithm="ES256",
        headers={"alg": "ES256", "kid": key_id},
    )


def send_daily_push_to_devices(
    *,
    devices: list[PushDevice],
    title: str,
    body: str,
    report_url: str,
    bundle_id: str,
) -> PushSendSummary:
    if not devices:
        return PushSendSummary()
    if not bundle_id:
        raise RuntimeError("APNS_BUNDLE_ID is required for push sending.")

    auth_token = _jwt_token()
    host = _apns_host()
    summary = PushSendSummary()
    payload = {
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default",
            "badge": 1,
        },
        "report_url": report_url,
    }

    headers = {
        "authorization": f"bearer {auth_token}",
        "apns-topic": bundle_id,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": "0",
    }

    with httpx.Client(http2=True, timeout=15.0) as client:
        for device in devices:
            endpoint = f"{host}/3/device/{device.device_token}"
            try:
                response = client.post(endpoint, headers=headers, json=payload)
            except Exception:
                summary.failed += 1
                continue

            if response.status_code == 200:
                summary.sent += 1
                continue

            summary.failed += 1
            reason = ""
            try:
                reason = str(response.json().get("reason", "")).strip()
            except Exception:
                reason = ""
            if reason in INVALID_TOKEN_REASONS:
                disable_push_device(device_token=device.device_token, platform=device.platform)
                summary.disabled += 1

    return summary
