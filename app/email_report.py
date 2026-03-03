from __future__ import annotations

import os
import smtplib
from dataclasses import dataclass
from datetime import datetime
from email.message import EmailMessage
from pathlib import Path
from zoneinfo import ZoneInfo

import httpx
from dotenv import load_dotenv

from app.subscribers import load_subscribers


@dataclass
class ReportSnapshot:
    total_claims: int
    corroborated_claims: int
    trusted_source_claims: int
    needs_follow_up_claims: int
    report_url: str


def load_config() -> dict[str, str]:
    load_dotenv()
    required_keys = [
        "EMAIL_SMTP_HOST",
        "EMAIL_SMTP_PORT",
        "EMAIL_USERNAME",
        "EMAIL_APP_PASSWORD",
        "EMAIL_FROM",
        "EMAIL_TO",
        "REPORT_URL",
        "REPORT_API_URL",
    ]
    config = {key: os.getenv(key, "").strip() for key in required_keys}
    missing = [key for key, value in config.items() if not value]
    if missing:
        missing_keys = ", ".join(sorted(missing))
        raise RuntimeError(f"Missing required environment variables: {missing_keys}")
    return config


def get_public_report_url(default_url: str) -> str:
    """Use dynamic tunnel URL only when explicitly enabled."""
    dynamic_enabled = os.getenv("USE_DYNAMIC_PUBLIC_REPORT_URL", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }
    if not dynamic_enabled:
        return default_url

    file_path = os.getenv("PUBLIC_REPORT_URL_FILE", "").strip()
    if not file_path:
        return default_url

    candidate = Path(file_path)
    if not candidate.exists():
        return default_url

    public_url = candidate.read_text().strip()
    if public_url.startswith("http://") or public_url.startswith("https://"):
        return public_url
    return default_url


def fetch_snapshot(report_api_url: str, report_url: str) -> ReportSnapshot:
    response = httpx.get(report_api_url, timeout=20)
    response.raise_for_status()
    payload = response.json()
    claims = payload.get("claims", [])
    corroborated = []
    trusted_source = []
    needs_follow_up = []
    for claim in claims:
        evidence = claim.get("evidence", []) or []
        source_count = len(
            {
                str(item.get("source_name", "")).strip()
                for item in evidence
                if str(item.get("source_name", "")).strip()
            }
        )
        tier1_count = len(
            {
                str(item.get("source_name", "")).strip()
                for item in evidence
                if str(item.get("source_name", "")).strip() and int(item.get("source_tier", 99)) == 1
            }
        )
        max_trust = max(
            [float(item.get("source_trust_score", 0.0) or 0.0) for item in evidence],
            default=0.0,
        )

        # Corroborated means multiple independent sources, ideally including trusted tier-1.
        if source_count >= 2 and (tier1_count >= 1 or max_trust >= 0.9):
            corroborated.append(claim)
        # Trusted source means at least one trusted source reported it,
        # even if only one source currently carries the story.
        elif tier1_count >= 1 or max_trust >= 0.9:
            trusted_source.append(claim)
        else:
            needs_follow_up.append(claim)
    return ReportSnapshot(
        total_claims=len(claims),
        corroborated_claims=len(corroborated),
        trusted_source_claims=len(trusted_source),
        needs_follow_up_claims=len(needs_follow_up),
        report_url=report_url,
    )


def build_subject(timezone_name: str = "America/Chicago") -> str:
    now = datetime.now(ZoneInfo(timezone_name)).strftime("%Y-%m-%d")
    brand = os.getenv("NEWS_BRAND", "Big Daves News").strip() or "Big Daves News"
    return f"{brand} - Daily Report - {now}"


def build_body(snapshot: ReportSnapshot, timezone_name: str = "America/Chicago") -> str:
    now = datetime.now(ZoneInfo(timezone_name)).strftime("%Y-%m-%d")
    brand = os.getenv("NEWS_BRAND", "Big Daves News").strip() or "Big Daves News"
    return (
        f"{brand} daily report ({now}) is ready.\n\n"
        f"Report link: {snapshot.report_url}\n"
    )


def build_html_body(snapshot: ReportSnapshot, timezone_name: str = "America/Chicago") -> str:
    now = datetime.now(ZoneInfo(timezone_name)).strftime("%B %d, %Y")
    brand = os.getenv("NEWS_BRAND", "Big Daves News").strip() or "Big Daves News"

    return f"""\
<!doctype html>
<html lang="en">
  <body style="margin:0; padding:0; background:#f2f6fc; font-family:Arial,Helvetica,sans-serif; color:#1f2937;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f2f6fc; padding:28px 12px;">
      <tr>
        <td align="center">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:680px; background:#ffffff; border-radius:10px; overflow:hidden; border:1px solid #d7e3f5;">
            <tr>
              <td style="background:linear-gradient(90deg, #0b3b91, #1f6feb); color:#ffffff; padding:20px 24px;">
                <div style="font-size:12px; letter-spacing:0.08em; text-transform:uppercase; opacity:0.95;">Daily Briefing</div>
                <div style="font-size:26px; font-weight:700; margin-top:6px;">{brand}</div>
                <div style="font-size:14px; margin-top:6px; opacity:0.92;">{now}</div>
              </td>
            </tr>
            <tr>
              <td style="padding:22px 24px 10px 24px;">
                <p style="margin:0 0 14px 0; font-size:15px; line-height:1.45;">
                  Your daily report is ready. Open the full page for the latest headlines and details.
                </p>
              </td>
            </tr>
            <tr>
              <td style="padding:14px 24px 26px 24px;" align="center">
                <a href="{snapshot.report_url}" style="display:inline-block; text-decoration:none; background:#0b3b91; color:#ffffff; font-weight:700; border-radius:6px; padding:12px 18px;">
                  Open Full Report
                </a>
                <p style="margin:14px 0 0 0; font-size:12px; color:#6b7280;">
                  If the button does not work, copy and paste this URL into your browser:<br />
                  <span style="color:#1d4ed8;">{snapshot.report_url}</span>
                </p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>
"""


def send_daily_email() -> str:
    config = load_config()
    timezone_name = os.getenv("SCHEDULER_TIMEZONE", "America/Chicago")
    report_url = get_public_report_url(config["REPORT_URL"])
    snapshot = fetch_snapshot(
        report_api_url=config["REPORT_API_URL"],
        report_url=report_url,
    )

    recipients = [config["EMAIL_TO"].strip().lower(), *load_subscribers()]
    unique_recipients = []
    seen = set()
    for recipient in recipients:
        normalized = recipient.strip().lower()
        if normalized and normalized not in seen:
            seen.add(normalized)
            unique_recipients.append(normalized)
    if not unique_recipients:
        raise RuntimeError("No email recipients configured.")

    msg = EmailMessage()
    msg["Subject"] = build_subject(timezone_name=timezone_name)
    msg["From"] = config["EMAIL_FROM"]
    msg["To"] = unique_recipients[0]
    if len(unique_recipients) > 1:
        msg["Bcc"] = ", ".join(unique_recipients[1:])
    msg.set_content(build_body(snapshot=snapshot, timezone_name=timezone_name))
    msg.add_alternative(build_html_body(snapshot=snapshot, timezone_name=timezone_name), subtype="html")

    smtp_port = int(config["EMAIL_SMTP_PORT"])
    app_password = config["EMAIL_APP_PASSWORD"].replace(" ", "")
    with smtplib.SMTP(config["EMAIL_SMTP_HOST"], smtp_port, timeout=30) as server:
        server.starttls()
        server.login(config["EMAIL_USERNAME"], app_password)
        server.send_message(msg)

    return f"sent:{len(unique_recipients)}"


if __name__ == "__main__":
    result = send_daily_email()
    print(f"Email delivered successfully ({result})")
