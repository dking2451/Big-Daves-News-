from __future__ import annotations

import json
import os
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path


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
    with urllib.request.urlopen(req, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def _markdown_table(headers: list[str], rows: list[list[str]]) -> str:
    head = "| " + " | ".join(headers) + " |"
    sep = "| " + " | ".join(["---"] * len(headers)) + " |"
    body = "\n".join(["| " + " | ".join(row) + " |" for row in rows])
    if not body:
        body = "| " + " | ".join(["-"] * len(headers)) + " |"
    return "\n".join([head, sep, body])


def _to_markdown(payload: dict) -> str:
    generated = payload.get("generated_at_utc", "")
    plain = payload.get("plain_english", {})
    tables = payload.get("tables", {})
    charts = payload.get("charts", {})

    top_events = tables.get("top_events_24h", [])[:10]
    top_api = tables.get("top_api_endpoints_24h", [])[:10]
    sports = tables.get("sports_events_24h", {})
    event_series = charts.get("event_volume_series", [])
    sports_series = charts.get("sports_open_series", [])
    fail_rate_series = charts.get("api_failure_rate_series", [])

    lines: list[str] = []
    lines.append("# Daily Product Metrics (Layman)")
    lines.append("")
    lines.append(f"- Generated UTC: `{generated}`")
    lines.append("")
    lines.append("## Plain-English Summary")
    lines.append("")
    for bullet in plain.get("summary_bullets", []):
        lines.append(f"- {bullet}")
    for bullet in plain.get("sports_bullets", []):
        lines.append(f"- {bullet}")
    lines.append("")
    lines.append("## Top Events (24h)")
    lines.append("")
    lines.append(
        _markdown_table(
            ["Event", "Count"],
            [[str(item.get("event_name", "")), str(item.get("count", 0))] for item in top_events],
        )
    )
    lines.append("")
    lines.append("## Top API Endpoints (24h)")
    lines.append("")
    lines.append(
        _markdown_table(
            ["Endpoint", "Calls", "Failures", "Avg ms"],
            [
                [
                    str(item.get("endpoint", "")),
                    str(item.get("calls", 0)),
                    str(item.get("failure_calls", 0)),
                    str(item.get("avg_duration_ms", 0)),
                ]
                for item in top_api
            ],
        )
    )
    lines.append("")
    lines.append("## Sports Event Counters (24h)")
    lines.append("")
    lines.append(
        _markdown_table(
            ["Metric", "Value"],
            [[str(k), str(v)] for k, v in sorted(sports.items())],
        )
    )
    lines.append("")
    lines.append("## Chart Series (Daily)")
    lines.append("")
    lines.append("### Event Volume")
    lines.append(
        _markdown_table(
            ["Day (UTC)", "Events"],
            [[str(x.get("day_utc", "")), str(x.get("value", 0))] for x in event_series],
        )
    )
    lines.append("")
    lines.append("### Sports Opens")
    lines.append(
        _markdown_table(
            ["Day (UTC)", "Sports Opens"],
            [[str(x.get("day_utc", "")), str(x.get("value", 0))] for x in sports_series],
        )
    )
    lines.append("")
    lines.append("### API Failure Rate")
    lines.append(
        _markdown_table(
            ["Day (UTC)", "Failure Rate"],
            [[str(x.get("day_utc", "")), f"{float(x.get('value', 0)) * 100:.2f}%"] for x in fail_rate_series],
        )
    )
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    base_url = os.getenv("METRICS_BASE_URL", "http://127.0.0.1:8000").strip()
    admin_token = os.getenv("ADMIN_TOKEN", "").strip()
    days = _env_int("METRICS_ROLLUP_DAYS", 14)
    output_dir = Path(os.getenv("METRICS_OUTPUT_DIR", "reports/metrics")).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    if not admin_token:
        print("Missing ADMIN_TOKEN; cannot fetch admin metrics.")
        return

    payload = _fetch_metrics_payload(base_url=base_url, token=admin_token, days=days)
    if not payload.get("success"):
        print(f"Metrics request failed: {payload.get('message', 'unknown error')}")
        return

    stamp = datetime.utcnow().strftime("%Y-%m-%d")
    json_path = output_dir / f"metrics_layman_{stamp}.json"
    md_path = output_dir / f"metrics_layman_{stamp}.md"

    json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    md_path.write_text(_to_markdown(payload), encoding="utf-8")
    print(f"Wrote: {json_path}")
    print(f"Wrote: {md_path}")


if __name__ == "__main__":
    main()

