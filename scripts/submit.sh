#!/usr/bin/env bash
set -euo pipefail

echo ""
echo "========================================"
echo "  Generating Submission"
echo "========================================"
echo ""

# Generate patch from all changes since initial commit
INITIAL_COMMIT=$(git rev-list --max-parents=0 HEAD)
PATCH_FILE="submission-$(date +%Y%m%d-%H%M%S).patch"

git diff "${INITIAL_COMMIT}"..HEAD > "${PATCH_FILE}"

if [ -s "${PATCH_FILE}" ]; then
  echo "Submission generated: ${PATCH_FILE}"
  echo ""
  echo "Files changed:"
  git diff --stat "${INITIAL_COMMIT}"..HEAD
  echo ""
  echo "Next steps:"
  echo "  - Push to your private fork, OR"
  echo "  - Email ${PATCH_FILE} to the hiring team"
else
  echo "No changes detected. Make sure you've committed your work."
  rm -f "${PATCH_FILE}"
  exit 1
fi
