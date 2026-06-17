#!/bin/bash
# Validate test fixture layout and checksum.index.entry consistency.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/test/fixtures"

PASS=0
FAIL=0

pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }

lint_index_entry() {
    local scenario="$1"
    local entry_file="$scenario/checksum.index.entry"
    [[ -f "$entry_file" ]] || return 0
    if grep -q '^#' "$entry_file"; then
        pass "$(basename "$scenario"): unindexed (no MD5 check)"
        return 0
    fi
    local line path hash
    line="$(grep -v '^#' "$entry_file" | head -1)"
    path="${line%% *}"
    hash="${line#* }"
    local base="${path##*/}"
    local live="$scenario/etc/$base"
    if [[ ! -e "$live" ]]; then
        fail "$(basename "$scenario"): live file missing for index entry ($base)"
        return 0
    fi
    if [[ "$hash" == "0" ]]; then
        pass "$(basename "$scenario"): index entry 0 (modified)"
        return 0
    fi
    local actual
    actual="$(md5sum "$live" | awk '{print $1}')"
    if [[ "$actual" == "$hash" ]]; then
        pass "$(basename "$scenario"): MD5 matches index ($base)"
    else
        fail "$(basename "$scenario"): MD5 mismatch for $base (index $hash, actual $actual)"
    fi
}

lint_scenario_structure() {
    local scenario="$1"
    local name
    name="$(basename "$scenario")"
    [[ -d "$scenario/etc" ]] || { fail "$name: missing etc/"; return; }
    local markers
    markers="$(find "$scenario/etc" -maxdepth 1 -name '._cfg*' 2>/dev/null | wc -l)"
    if [[ "$markers" -eq 0 ]]; then
        fail "$name: no ._cfg* marker in etc/"
        return
    fi
    pass "$name: has $markers pending marker(s)"
    if [[ -d "$scenario/backups/etc/test" ]]; then
        local ancestors
        ancestors="$(find "$scenario/backups/etc/test" -maxdepth 1 -name '._new-cfg*' 2>/dev/null | wc -l)"
        if [[ "$ancestors" -ge 1 ]]; then
            pass "$name: has ancestor backup(s)"
        else
            fail "$name: backups/etc/test present but no ._new-cfg* files"
        fi
    fi
}

lint_duplicate_markers() {
    local combined
    combined="$(mktemp)"
    find "$FIXTURES"/stage*/etc -maxdepth 1 -name '._cfg*' -printf '%f\n' 2>/dev/null | sort >"$combined"
    local dupes
    dupes="$(uniq -d "$combined" || true)"
    rm -f "$combined"
    if [[ -n "$dupes" ]]; then
        fail "duplicate marker basenames across scenarios: $dupes"
    else
        pass "no duplicate marker basenames across scenarios"
    fi
}

main() {
    command -v md5sum >/dev/null || { echo "ERROR: md5sum required" >&2; exit 1; }
    echo "=== Fixture lint ==="
    for scenario in "$FIXTURES"/stage*/; do
        [[ -d "$scenario/etc" ]] || continue
        lint_scenario_structure "$scenario"
        lint_index_entry "$scenario"
    done
    lint_duplicate_markers
    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    [[ "$FAIL" -eq 0 ]]
}

main "$@"