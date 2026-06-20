#!/bin/bash
set -euo pipefail

# scripts/bump-version.sh
# Release-only version bump for cfg-update.
# Usage: ./scripts/bump-version.sh 1.11.0 [--dry-run]

NEW_VERSION="${1:-}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

HEADER_LINES=4

usage() {
    echo "Usage: $0 NEW_VERSION [--dry-run]"
    echo "Example: $0 1.11.0"
}

die() { echo "Error: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "$NEW_VERSION" ]]; then
    usage
    exit 1
fi

if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "Version must look like X.Y.Z (got '$NEW_VERSION')"
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "Must run from a git repository"

mapfile -t EBUILDS < <(ls gentoo/cfg-update-*.ebuild 2>/dev/null | sort -V || true)
EBUILD_COUNT=${#EBUILDS[@]}

if (( EBUILD_COUNT > 1 )); then
    die "Expected exactly one gentoo/cfg-update-*.ebuild, found $EBUILD_COUNT: ${EBUILDS[*]}"
fi

OLD_EBUILD=""
if (( EBUILD_COUNT == 1 )); then
    OLD_EBUILD="${EBUILDS[0]}"
fi

NEW_EBUILD="gentoo/cfg-update-$NEW_VERSION.ebuild"
TODAY=$(date +%Y-%m-%d)
CHANGELOG_STUB="*cfg-update-$NEW_VERSION ($TODAY)

  (Summarize changes here — what was added, fixed, or changed since the previous release.)

"

echo "Preparing bump to version $NEW_VERSION"

if $DRY_RUN; then
    echo "[DRY RUN] Would perform the following updates:"
    echo "  • cfg-update: set \$version = \"$NEW_VERSION\""
    echo "  • README.md: set **Version:** $NEW_VERSION"
    if [[ -n "$OLD_EBUILD" ]]; then
        if [[ "$OLD_EBUILD" == "$NEW_EBUILD" ]]; then
            echo "  • Ebuild already at $NEW_VERSION (no rename)"
        else
            echo "  • git mv $(basename "$OLD_EBUILD") → $(basename "$NEW_EBUILD")"
        fi
    else
        echo "  • (no ebuild in gentoo/ — skip rename)"
    fi
    echo "  • Insert ChangeLog stub after line $HEADER_LINES:"
    printf '    %s' "$CHANGELOG_STUB" | sed 's/^/    /'
    echo "  • Verify cfg-update, README.md, and ebuild PV all equal $NEW_VERSION"
    exit 0
fi

read -p "Proceed with updates to version $NEW_VERSION? [y/N] " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Aborted."; exit 1; }

# 1. Update version in the main script
perl -pi -e 's/^(    my \$version\s+=\s+")[^"]+(";\s*)$/${1}'"$NEW_VERSION"'${2}/' cfg-update

# 2. Update README
perl -pi -e 's/^\*\*Version:\*\* .*/**Version:** '"$NEW_VERSION"'/' README.md

# 3. Rename ebuild (filename carries PV for Portage)
if [[ -n "$OLD_EBUILD" ]]; then
    if [[ "$OLD_EBUILD" == "$NEW_EBUILD" ]]; then
        echo "Ebuild already at $NEW_VERSION; skipping rename."
    else
        if [[ -e "$NEW_EBUILD" ]]; then
            die "$NEW_EBUILD already exists (remove it or choose a different version)"
        fi
        git mv "$OLD_EBUILD" "$NEW_EBUILD"
        echo "Renamed $(basename "$OLD_EBUILD") → $(basename "$NEW_EBUILD")"
    fi
fi

# 4. Insert ChangeLog stub after the header block
{
    head -n "$HEADER_LINES" ChangeLog
    printf '%s' "$CHANGELOG_STUB"
    tail -n +$((HEADER_LINES + 1)) ChangeLog
} > ChangeLog.tmp && mv ChangeLog.tmp ChangeLog

# 5. Post-bump consistency check
"$SCRIPT_DIR/check-version.sh" "$NEW_VERSION"

echo
echo "Bump complete. Next manual steps:"
echo "  1. Edit the new ChangeLog entry with a good summary."
echo "  2. git add cfg-update README.md ChangeLog"
if [[ -n "$OLD_EBUILD" || -e "$NEW_EBUILD" ]]; then
    echo "     git add -A gentoo/"
fi
echo "  3. Open a PR to master (see VERSIONING.md)"
echo "  4. After merge: git tag -a $NEW_VERSION -m 'cfg-update $NEW_VERSION'"
echo "  5. git push origin $NEW_VERSION"