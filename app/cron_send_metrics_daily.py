from __future__ import annotations

import json
import os
import smtplib
import urllib.parse
import urllib.request
from datetime import datetime
from email.message import EmailMessage
from zoneinfo import ZoneInfo


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _fetch_metrics_payload(base_url: str, token: str, days: int) -> dict:
    params = urllib.parse.urlencode({"token": token, "days": str(days)})
    url = f"{base_url.rstrip('/')}/api/admin/metrics-layman?{params}"
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def _subject(timezone_name: str) -> str:
    now_local = datetime.now(ZoneInfo(timezone_name)).strftime("%Y-%m-%d")
    return f"Big Daves News - Daily Metrics - {now_local}"


def _text_body(payload: dict, timezone_name: str) -> str:
    plain = payload.get("plain_english", {})
    generated = payload.get("generated_at_utc", "")
    lines: list[str] = [
        f"Daily metrics summary ({datetime.now(ZoneInfo(timezone_name)).strftime('%Y-%m-%d')})",
        "",
        f"Generated UTC: {generated}",
        "",
        "Plain-English highlights:",
    ]
    for bullet in plain.get("summary_bullets", []):
        lines.append(f"- {bullet}")
    for bullet in plain.get("sports_bullets", []):
        lines.append(f"- {bullet}")
    lines.append("")

    top_events = payload.get("tables", {}).get("top_events_24h", [])[:5]
    if top_events:
        lines.append("Top events (24h):")
        for item in top_events:
            lines.append(f"- {item.get('event_name', '')}: {item.get('count', 0)}")
        lines.append("")

    top_api = payload.get("tables", {}).get("top_api_endpoints_24h", [])[:5]
    if top_api:
        lines.append("Top API endpoints (24h):")
        for item in top_api:
            lines.append(
                f"- {item.get('endpoint', '')}: calls={item.get('calls', 0)} "
                f"failures={item.get('failure_calls', 0)} avg_ms={item.get('avg_duration_ms', 0)}"
            )
        lines.append("")

    lines.append("Tip: You can fetch full JSON via /api/admin/metrics-layman.")
    return "\n".join(lines)


def _html_body(payload: dict, timezone_name: str) -> str:
    plain = payload.get("plain_english", {})
    generated = payload.get("generated_at_utc", "")
    top_events = payload.get("tables", {}).get("top_events_24h", [])[:6]
    top_api = payload.get("tables", {}).get("top_api_endpoints_24h", [])[:6]

    bullets_html = "".join([f"<li>{b}</li>" for b in plain.get("summary_bullets", []) + plain.get("sports_bullets", [])])
    events_rows = "".join(
        [
            f"<tr><td style='padding:6px 8px;border-bottom:1px solid #eee'>{e.get('event_name','')}</td>"
            f"<td style='padding:6px 8px;border-bottom:1px solid #eee;text-align:right'>{e.get('count',0)}</td></tr>"
            for e in top_events
        ]
    ) or "<tr><td colspan='2' style='padding:6px 8px;color:#666'>No events recorded.</td></tr>"
    api_rows = "".join(
        [
            f"<tr><td style='padding:6px 8px;border-bottom:1px solid #eee'>{a.get('endpoint','')}</td>"
            f"<td style='padding:6px 8px;border-bottom:1px solid #eee;text-align:right'>{a.get('calls',0)}</td>"
            f"<td style='padding:6px 8px;border-bottom:1px solid #eee;text-align:right'>{a.get('failure_calls',0)}</td></tr>"
            for a in top_api
        ]
    ) or "<tr><td colspan='3' style='padding:6px 8px;color:#666'>No API metrics recorded.</td></tr>"

    return f"""
<!doctype html>
<html>
  <body style="font-family:Arial,Helvetica,sans-serif;color:#1f2937;background:#f7f9fc;padding:16px;">
    <div style="max-width:760px;margin:0 auto;background:#fff;border:1px solid #e5e7eb;border-radius:10px;overflow:hidden;">
      <div style="background:#0b3b91;color:#fff;padding:16px 20px;">
        <div style="font-size:20px;font-weight:700;">Daily Metrics Summary</div>
        <div style="font-size:13px;opacity:0.9;">{datetime.now(ZoneInfo(timezone_name)).strftime('%B %d, %Y')} • generated {generated}</div>
      </div>
      <div style="padding:16px 20px;">
        <h3 style="margin:0 0 10px 0;">Highlights</h3>
        <ul style="margin-top:0;">{bullets_html}</ul>
        <h3 style="margin:16px 0 8px 0;">Top Events (24h)</h3>
        <table style="width:100%;border-collapse:collapse;font-size:14px;">
          <thead><tr><th style="text-align:left;padding:6px 8px;">Event</th><th style="text-align:right;padding:6px 8px;">Count</th></tr></thead>
          <tbody>{events_rows}</tbody>
        </table>
        <h3 style="margin:16px 0 8px 0;">Top API Endpoints (24h)</h3>
        <table style="width:100%;border-collapse:collapse;font-size:14px;">
          <thead>
            <tr>
              <th style="text-align:left;padding:6px 8px;">Endpoint</th>
              <th style="text-align:right;padding:6px 8px;">Calls</th>
              <th style="text-align:right;padding:6px 8px;">Failures</th>
            </tr>
          </thead>
          <tbody>{api_rows}</tbody>
        </table>
      </div>
    </div>
  </body>
</html>
""".strip()


def main() -> None:
    smtp_host = os.getenv("EMAIL_SMTP_HOST", "").strip()
    smtp_port = _env_int("EMAIL_SMTP_PORT", 587)
    smtp_username = os.getenv("EMAIL_USERNAME", "").strip()
    smtp_password = os.getenv("EMAIL_APP_PASSWORD", "").strip().replace(" ", "")
    email_from = os.getenv("EMAIL_FROM", "").strip()
    email_to = os.getenv("METRICS_EMAIL_TO", "").strip() or os.getenv("EMAIL_TO", "").strip()
    admin_token = os.getenv("ADMIN_TOKEN", "").strip()
    base_url = os.getenv("METRICS_BASE_URL", "https://big-daves-news-web.onrender.com").strip()
    timezone_name = os.getenv("SCHEDULER_TIMEZONE", "America/Chicago").strip() or "America/Chicago"
    days = _env_int("METRICS_ROLLUP_DAYS", 14)

    missing = [
        name
        for name, value in {
            "EMAIL_SMTP_HOST": smtp_host,
            "EMAIL_SMTP_PORT": str(smtp_port),
            "EMAIL_USERNAME": smtp_username,
            "EMAIL_APP_PASSWORD": smtp_password,
            "EMAIL_FROM": email_from,
            "METRICS_EMAIL_TO or EMAIL_TO": email_to,
            "ADMIN_TOKEN": admin_token,
            "METRICS_BASE_URL": base_url,
        }.items()
        if not value
    ]
    if missing:
        # Exit successfully so the cron run is not marked "failed" when email is intentionally not configured.
        print(
            "[cron_send_metrics_daily] Skipping send — set these on the Render cron service "
            f"(Environment): {', '.join(missing)}. "
            "Same SMTP vars as daily email if you use that job."
        )
        return

    payload = _fetch_metrics_payload(base_url=base_url, token=admin_token, days=days)
    if not payload.get("success"):
        raise RuntimeError(f"Metrics endpoint failed: {payload.get('message', 'unknown error')}")

    msg = EmailMessage()
    msg["Subject"] = _subject(timezone_name)
    msg["From"] = email_from
    msg["To"] = email_to
    msg.set_content(_text_body(payload, timezone_name))
    msg.add_alternative(_html_body(payload, timezone_name), subtype="html")

    with smtplib.SMTP(smtp_host, smtp_port, timeout=30) as server:
        server.starttls()
        server.login(smtp_username, smtp_password)
        server.send_message(msg)

    print(f"Daily metrics email sent to {email_to}")


if __name__ == "__main__":
    main()

