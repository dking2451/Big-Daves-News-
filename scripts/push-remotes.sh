#!/usr/bin/env bash
# Push the current branch to both remotes (familyos + origin).
# Usage: from repo root — ./scripts/push-remotes.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "Pushing branch '$BRANCH' to familyos and origin..."
git push familyos "$BRANCH"
git push origin "$BRANCH"
echo "Done."
