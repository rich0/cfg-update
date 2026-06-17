#!/bin/bash
# Integration test harness for cfg-update fixtures.
# Tier A (classify): no root required.
# Tier B/C (auto update): require root; skipped otherwise.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/test/fixtures"
CFG_UPDATE="$REPO_ROOT/cfg-update"
HOSTS_FILE="$REPO_ROOT/test/cfg-update.hosts"

PASS=0
FAIL=0
SKIP=0
SANDBOX=""

cleanup() {
    if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
        rm -rf "$SANDBOX"
    fi
}
trap cleanup EXIT

die() { echo "ERROR: $*" >&2; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP: $*"; SKIP=$((SKIP + 1)); }

assert_output_matches() {
    local desc="$1" pattern="$2" output="$3"
    if echo "$output" | grep -Eq "$pattern"; then
        pass "$desc"
    else
        fail "$desc (expected pattern: $pattern)"
        echo "--- output ---" >&2
        echo "$output" >&2
        echo "-------------" >&2
    fi
}

assert_file_contains() {
    local desc="$1" file="$2" pattern="$3"
    if [[ -f "$file" ]] && grep -qF "$pattern" "$file"; then
        pass "$desc"
    else
        fail "$desc (file: $file, expected: $pattern)"
    fi
}

assert_missing() {
    local desc="$1" path="$2"
    if [[ ! -e "$path" ]]; then
        pass "$desc"
    else
        fail "$desc (still exists: $path)"
    fi
}

write_test_config() {
    local conf="$1" index="$2" backup="$3"
    local stages="${4:-all}"
    local s1=yes s2=yes s3=yes s4=yes s5=yes
    if [[ "$stages" == "auto" ]]; then
        s3=no s4=no s5=no
    fi
    cat >"$conf" <<EOF
MERGE_TOOL = /usr/bin/diff3
ENABLE_BACKUPS = yes
ENABLE_STAGE1 = $s1
ENABLE_STAGE2 = $s2
ENABLE_STAGE3 = $s3
ENABLE_STAGE4 = $s4
ENABLE_STAGE5 = $s5
INDEX_FILE = $index
BACKUP_PATH = $backup
EOF
}

setup_sandbox() {
    local mode="${1:-all}"  # all | scenario name
    SANDBOX="$(mktemp -d)"
    export CFG_UPDATE_TEST_SANDBOX="$SANDBOX"

    mkdir -p "$SANDBOX/etc/test" "$SANDBOX/var/lib/cfg-update/backups/etc/test" "$SANDBOX/bin"

    cat >"$SANDBOX/bin/portageq" <<'EOF'
#!/bin/bash
echo "\"${CFG_UPDATE_TEST_SANDBOX}/etc/test\""
EOF
    chmod +x "$SANDBOX/bin/portageq"

    deploy_backups() {
        local scenario="$1"
        [[ -d "$scenario/backups/etc/test" ]] || return 0
        # cfg-update resolves ancestors at BACKUP_PATH + dirname(marker)
        local dest="$SANDBOX/var/lib/cfg-update/backups${SANDBOX}/etc/test"
        mkdir -p "$dest"
        cp -a "$scenario/backups/etc/test/." "$dest/"
    }

    if [[ "$mode" == "all" ]]; then
        for scenario in "$FIXTURES"/stage*/; do
            [[ -d "$scenario/etc" ]] || continue
            # Use etc/. so dotfiles (._cfg0000_*) are included; glob * skips them.
            cp -a "$scenario/etc/." "$SANDBOX/etc/test/"
            deploy_backups "$scenario"
        done
        sed "s|/etc/test|${SANDBOX}/etc/test|g" "$FIXTURES/checksum.index.seed" \
            >"$SANDBOX/var/lib/cfg-update/checksum.index"
    else
        local scenario="$FIXTURES/$mode"
        [[ -d "$scenario/etc" ]] || die "unknown scenario: $mode"
        cp -a "$scenario/etc/." "$SANDBOX/etc/test/"
        deploy_backups "$scenario"
        if [[ -f "$scenario/checksum.index.entry" ]] && ! grep -q '^#' "$scenario/checksum.index.entry"; then
            {
                echo "Portage:0"
                sed "s|/etc/test|${SANDBOX}/etc/test|g" "$scenario/checksum.index.entry"
            } >"$SANDBOX/var/lib/cfg-update/checksum.index"
        else
            echo "Portage:0" >"$SANDBOX/var/lib/cfg-update/checksum.index"
        fi
    fi

    write_test_config \
        "$SANDBOX/etc/cfg-update.conf" \
        "$SANDBOX/var/lib/cfg-update/checksum.index" \
        "$SANDBOX/var/lib/cfg-update/backups" \
        "${2:-all}"
}

run_cfg_update() {
    local extra_args=("$@")
    CFG_UPDATE_CONF="$SANDBOX/etc/cfg-update.conf" \
    CFG_UPDATE_HOSTS="$HOSTS_FILE" \
    PATH="$SANDBOX/bin:$PATH" \
    perl "$CFG_UPDATE" --ebuild "${extra_args[@]}"
}

tier_a_classify() {
    echo "=== Tier A: classify (-lv) ==="
    setup_sandbox all
    local output
    output="$(run_cfg_update -lv 2>&1)" || true

    # Stage 1 (-lv prints verbose state names, not UF/UB abbreviations)
    assert_output_matches "stage1 unmodified text" \
        'Stage\[1\][[:space:]]+Unmodified File[[:space:]].*_cfg0000_test_unmodified_file' "$output"
    assert_output_matches "stage1 unmodified binary" \
        'Stage\[1\][[:space:]]+Unmodified Binary[[:space:]].*_cfg0000_test_unmodified_binary' "$output"

    # Stage 2
    assert_output_matches "stage2 3-way success" \
        'Stage\[2\][[:space:]]+Modified File[[:space:]].*_cfg0000_test_auto_3way_success' "$output"
    assert_output_matches "stage2 3-way conflict (queued for auto)" \
        'Stage\[2\][[:space:]]+Modified File[[:space:]].*_cfg0000_test_auto_3way_conflict' "$output"

    # Stage 4
    assert_output_matches "stage4 manual 2-way marker 0000" \
        'Stage\[4\][[:space:]]+Modified File[[:space:]].*_cfg0000_test_manual_2way' "$output"
    assert_output_matches "stage4 manual 2-way marker 0001" \
        'Stage\[4\][[:space:]]+Modified File[[:space:]].*_cfg0001_test_manual_2way' "$output"
    assert_output_matches "stage4 custom file" \
        'Stage\[4\][[:space:]]+Custom File[[:space:]].*_cfg0000_test_custom_file' "$output"

    # Stage 5
    assert_output_matches "stage5 custom binary" \
        'Stage\[5\][[:space:]]+Custom Binary[[:space:]].*_cfg0000_test_custom_binary' "$output"
    assert_output_matches "stage5 file to link" \
        'Stage\[5\][[:space:]]+File to Link[[:space:]].*_cfg0000_test_file_2_link' "$output"
    assert_output_matches "stage5 link to file" \
        'Stage\[5\][[:space:]]+Link to File[[:space:]].*_cfg0000_test_link_2_file' "$output"
    assert_output_matches "stage5 link to link" \
        'Stage\[5\][[:space:]]+Link to Link[[:space:]].*_cfg0000_test_link_2_link' "$output"

    # Incomplete fixture: modified binary has no ._cfg marker
    if echo "$output" | grep -q 'test_modified_binary'; then
        fail "stage5 modified binary should not appear without ._cfg marker"
    else
        pass "stage5 modified binary absent (no ._cfg marker in fixtures)"
    fi
}

tier_b_pretend_auto() {
    echo "=== Tier B: pretend automatic (-p -au) ==="
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "tier B requires root"
        return
    fi

    setup_sandbox all auto
    local output
    output="$(run_cfg_update -p -au 2>&1)" || true

    assert_output_matches "pretend stage1 runs" '<< Stage1 >>' "$output"
    assert_output_matches "pretend stage2 runs" '<< Stage2 >>' "$output"
    assert_output_matches "pretend stage3 skipped" '<< Stage3 >> disabled with -a' "$output"

    # Files must be unchanged in pretend mode
    assert_file_contains "pretend left live file at v1.0" \
        "$SANDBOX/etc/test/test_unmodified_file" "#version 1.0"
    assert_file_contains "pretend kept cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_unmodified_file" "#version 1.1"
}

tier_c_execute_auto() {
    echo "=== Tier C: execute automatic (-au) ==="
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "tier C requires root"
        return
    fi
    require_cmd diff3

    # Stage 1: unmodified text auto-replace
    setup_sandbox stage1-unmodified-text auto
    run_cfg_update -au >/dev/null
    assert_file_contains "stage1 replaced live file" \
        "$SANDBOX/etc/test/test_unmodified_file" "#version 1.1"
    assert_missing "stage1 removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_unmodified_file"

    # Stage 2: 3-way merge success
    setup_sandbox stage2-3way-merge-success auto
    run_cfg_update -au >/dev/null
    assert_file_contains "stage2 merged custom setting" \
        "$SANDBOX/etc/test/test_auto_3way_success" "SETTING = custom"
    assert_file_contains "stage2 merged new default version" \
        "$SANDBOX/etc/test/test_auto_3way_success" "#version 1.1"
    assert_missing "stage2 removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_auto_3way_success"
    if [[ -f "$SANDBOX/etc/test/test_auto_3way_success" ]] && \
       grep -qE '^<<<<<<<|^=======|^>>>>>>>' "$SANDBOX/etc/test/test_auto_3way_success"; then
        fail "stage2 merge left conflict markers"
    else
        pass "stage2 merge has no conflict markers"
    fi
}

main() {
    require_cmd perl
    require_cmd grep
    require_cmd sed
    require_cmd mktemp
    [[ -x "$CFG_UPDATE" || -f "$CFG_UPDATE" ]] || die "cfg-update not found at $CFG_UPDATE"

    perl -MTerm::ANSIColor -MTerm::ReadKey -e 1 2>/dev/null \
        || die "Perl modules missing (install Term::ANSIColor and Term::ReadKey)"

    tier_a_classify
    tier_b_pretend_auto
    tier_c_execute_auto

    echo ""
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
    [[ "$FAIL" -eq 0 ]]
}

main "$@"