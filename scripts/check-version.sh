#!/bin/bash
set -euo pipefail

# scripts/check-version.sh
# Verify cfg-update, README.md, and ebuild PV agree (no git required).
# Usage: ./scripts/check-version.sh [EXPECTED_VERSION]

EXPECTED="${1:-}"

die() { echo "Error: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

CFG_VERSION=$(perl -ne 'print $1 if /^    my \$version\s+=\s+"([^"]+)"/' cfg-update)
README_VERSION=$(perl -ne 'print $1 if /^\*\*Version:\*\* (.+)/' README.md)

mapfile -t EBUILDS < <(ls gentoo/cfg-update-*.ebuild 2>/dev/null | sort -V || true)
EBUILD_COUNT=${#EBUILDS[@]}

if (( EBUILD_COUNT > 1 )); then
    die "Expected exactly one gentoo/cfg-update-*.ebuild, found $EBUILD_COUNT: ${EBUILDS[*]}"
fi

EBUILD_VERSION=""
if (( EBUILD_COUNT == 1 )); then
    EBUILD_BASENAME=$(basename "${EBUILDS[0]}")
    if [[ "$EBUILD_BASENAME" =~ ^cfg-update-([0-9]+\.[0-9]+\.[0-9]+)\.ebuild$ ]]; then
        EBUILD_VERSION="${BASH_REMATCH[1]}"
    else
        die "Cannot parse PV from ebuild filename: $EBUILD_BASENAME"
    fi
fi

if [[ -z "$CFG_VERSION" ]]; then
    die "Could not read \$version from cfg-update"
fi
if [[ -z "$README_VERSION" ]]; then
    die "Could not read **Version:** from README.md"
fi

TARGET="$EXPECTED"
if [[ -z "$TARGET" ]]; then
    TARGET="$CFG_VERSION"
fi

if ! [[ "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "Version must look like X.Y.Z (got '$TARGET')"
fi

MISMATCH=0
report_mismatch() {
    local label="$1" actual="$2"
    echo "Mismatch: $label has \"$actual\" (expected $TARGET)" >&2
    MISMATCH=1
}

[[ "$CFG_VERSION" == "$TARGET" ]] || report_mismatch 'cfg-update \$version' "$CFG_VERSION"
[[ "$README_VERSION" == "$TARGET" ]] || report_mismatch 'README.md **Version:**' "$README_VERSION"

if (( EBUILD_COUNT == 1 )); then
    [[ "$EBUILD_VERSION" == "$TARGET" ]] || report_mismatch 'ebuild PV' "$EBUILD_VERSION"
else
    echo "Warning: no ebuild in gentoo/ — skipped ebuild PV check" >&2
fi

if (( MISMATCH )); then
    die "Version check failed"
fi

echo "Version check passed: cfg-update, README.md, and ebuild all at $TARGET"