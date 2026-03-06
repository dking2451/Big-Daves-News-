#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path


PROJECT_YML = Path(__file__).resolve().parents[1] / "project.yml"


def _read() -> str:
    return PROJECT_YML.read_text(encoding="utf-8")


def _write(content: str) -> None:
    PROJECT_YML.write_text(content, encoding="utf-8")


def _replace_setting(content: str, key: str, value: str) -> str:
    pattern = re.compile(rf"^(\s*{re.escape(key)}:\s*).*$", flags=re.MULTILINE)
    if not pattern.search(content):
        raise ValueError(f"Could not find '{key}' in {PROJECT_YML}")
    return pattern.sub(rf"\1{value}", content, count=1)


def _extract_setting(content: str, key: str) -> str:
    pattern = re.compile(rf"^\s*{re.escape(key)}:\s*(.+)\s*$", flags=re.MULTILINE)
    match = pattern.search(content)
    if not match:
        raise ValueError(f"Could not find '{key}' in {PROJECT_YML}")
    return match.group(1).strip().strip('"').strip("'")


def main() -> None:
    parser = argparse.ArgumentParser(description="Bump iOS app version/build in project.yml")
    parser.add_argument("--set-version", help="Set MARKETING_VERSION (example: 1.1.0)")
    parser.add_argument("--set-build", type=int, help="Set CURRENT_PROJECT_VERSION explicitly")
    parser.add_argument(
        "--bump-build",
        action="store_true",
        help="Increment CURRENT_PROJECT_VERSION by 1 (default when no build option provided)",
    )
    args = parser.parse_args()

    content = _read()

    if args.set_version:
        content = _replace_setting(content, "MARKETING_VERSION", args.set_version)

    current_build = int(_extract_setting(content, "CURRENT_PROJECT_VERSION"))
    next_build: int
    if args.set_build is not None:
        next_build = args.set_build
    elif args.bump_build or args.set_version or (args.set_build is None and not args.bump_build):
        next_build = current_build + 1
    else:
        next_build = current_build

    content = _replace_setting(content, "CURRENT_PROJECT_VERSION", str(next_build))
    _write(content)

    version = _extract_setting(content, "MARKETING_VERSION")
    print(f"Updated version -> MARKETING_VERSION={version}, CURRENT_PROJECT_VERSION={next_build}")
    print("Next: xcodegen generate")


if __name__ == "__main__":
    main()
