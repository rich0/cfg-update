#!/bin/bash
set -euo pipefail

# scripts/bump-version.sh
# Simple, conventional version bump script for small personal projects.
# Usage: ./scripts/bump-version.sh 1.11.0 [--dry-run]

NEW_VERSION="${1:-}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

if [[ -z "$NEW_VERSION" ]]; then
    echo "Usage: $0 NEW_VERSION [--dry-run]"
    echo "Example: $0 1.11.0"
    exit 1
fi

if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Version must look like X.Y.Z (got '$NEW_VERSION')"
    exit 1
fi

echo "Preparing bump to version $NEW_VERSION"

LATEST_EBUILD=$(ls gentoo/cfg-update-*.ebuild 2>/dev/null | sort -V | tail -1 || true)

if $DRY_RUN; then
    echo "[DRY RUN] Would perform the following updates:"
    echo "  • cfg-update: set \\$version = \"$NEW_VERSION\"" 
    echo "  • README.md: set **Version:** $NEW_VERSION"
    [[ -n "$LATEST_EBUILD" ]] && echo "  • Create gentoo/cfg-update-$NEW_VERSION.ebuild (from $(basename "$LATEST_EBUILD"))"
    echo "  • Prepend stub header to ChangeLog"
    exit 0
fi

read -p "Proceed with updates to version $NEW_VERSION? [y/N] " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Aborted."; exit 1; }

# 1. Update version in the main script
perl -pi -e 's/^(    my \$version\s+=\s+")[^"]+(";\s*)$/${1}'"$NEW_VERSION"'${2}/' cfg-update

# 2. Update README
perl -pi -e 's/^\*\*Version:\*\* .*/**Version:** '