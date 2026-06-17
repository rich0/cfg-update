#!/bin/bash
# Integration test harness for cfg-update fixtures.
# All tiers run without root when cfg-update is invoked with --testsandbox (stage 6c).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/test/fixtures"
CFG_UPDATE="$REPO_ROOT/cfg-update"
HOSTS_FILE="$REPO_ROOT/test/cfg-update.hosts"
LINT_FIXTURES="$REPO_ROOT/test/lint-fixtures.sh"

PASS=0
FAIL=0
SKIP=0
REQUIRE_FULL=0
FULL_TIERS_SKIPPED=0
SANDBOX=""
EXPECTED_MARKER_COUNT=12

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
skip_tier() { skip "$@"; FULL_TIERS_SKIPPED=$((FULL_TIERS_SKIPPED + 1)); }

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --full|--require-root) REQUIRE_FULL=1; shift ;;
            -h|--help)
                echo "Usage: $0 [--full]"
                echo "  Default: run all tiers (0/A/B/C); no root required."
                echo "  --full: alias --require-root; fail if Tier B/C were skipped."
                exit 0
                ;;
            *) die "unknown argument: $1 (try --help)" ;;
        esac
    done
}

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

assert_output_not_matches() {
    local desc="$1" pattern="$2" output="$3"
    if echo "$output" | grep -Eq "$pattern"; then
        fail "$desc (unexpected pattern: $pattern)"
    else
        pass "$desc"
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

assert_file_exists() {
    local desc="$1" path="$2"
    if [[ -e "$path" ]]; then
        pass "$desc"
    else
        fail "$desc (missing: $path)"
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
        local dest="$SANDBOX/var/lib/cfg-update/backups${SANDBOX}/etc/test"
        mkdir -p "$dest"
        cp -a "$scenario/backups/etc/test/." "$dest/"
    }

    if [[ "$mode" == "all" ]]; then
        for scenario in "$FIXTURES"/stage*/; do
            [[ -d "$scenario/etc" ]] || continue
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
    perl "$CFG_UPDATE" --ebuild --testsandbox "${extra_args[@]}"
}

tier0_static() {
    echo "=== Tier 0: static checks ==="
    if perl -c "$CFG_UPDATE" >/dev/null 2>&1; then
        pass "perl -c cfg-update"
    else
        fail "perl -c cfg-update"
    fi
    if bash -n "$REPO_ROOT/test/run-tests.sh"; then
        pass "bash -n run-tests.sh"
    else
        fail "bash -n run-tests.sh"
    fi
    if bash -n "$LINT_FIXTURES"; then
        pass "bash -n lint-fixtures.sh"
    else
        fail "bash -n lint-fixtures.sh"
    fi
    if bash -n "$REPO_ROOT/cfg-update_indexing"; then
        pass "bash -n cfg-update_indexing"
    else
        fail "bash -n cfg-update_indexing"
    fi
    if command -v shellcheck >/dev/null 2>&1; then
        if shellcheck -x "$REPO_ROOT/test/run-tests.sh" "$LINT_FIXTURES" "$REPO_ROOT/cfg-update_indexing"; then
            pass "shellcheck scripts"
        else
            fail "shellcheck scripts"
        fi
    else
        skip "shellcheck not installed"
    fi
}

tier0_lint_fixtures() {
    echo "=== Tier 0: fixture lint ==="
    if bash "$LINT_FIXTURES"; then
        pass "lint-fixtures.sh"
    else
        fail "lint-fixtures.sh"
    fi
}

tier_a_classify_combined() {
    echo "=== Tier A: classify combined (-lv) ==="
    setup_sandbox all
    local output
    output="$(run_cfg_update -lv 2>&1)" || true

    assert_output_matches "combined: stage1 unmodified text" \
        'Stage\[1\][[:space:]]+Unmodified File[[:space:]].*_cfg0000_test_unmodified_file' "$output"
    assert_output_matches "combined: stage1 unmodified binary" \
        'Stage\[1\][[:space:]]+Unmodified Binary[[:space:]].*_cfg0000_test_unmodified_binary' "$output"
    assert_output_matches "combined: stage2 3-way success" \
        'Stage\[2\][[:space:]]+Modified File[[:space:]].*_cfg0000_test_auto_3way_success' "$output"
    assert_output_matches "combined: stage2 3-way conflict" \
        'Stage\[2\][[:space:]]+Modified File[[:space:]].*_cfg0000_test_auto_3way_conflict' "$output"
    assert_output_matches "combined: stage4 manual 2-way 0000" \
        'Stage\[4\][[:space:]]+Modified File[[:space:]].*_cfg0000_test_manual_2way' "$output"
    assert_output_matches "combined: stage4 manual 2-way 0001" \
        'Stage\[4\][[:space:]]+Modified File[[:space:]].*_cfg0001_test_manual_2way' "$output"
    assert_output_matches "combined: stage4 custom file" \
        'Stage\[4\][[:space:]]+Custom File[[:space:]].*_cfg0000_test_custom_file' "$output"
    assert_output_matches "combined: stage5 modified binary" \
        'Stage\[5\][[:space:]]+Modified Binary[[:space:]].*_cfg0000_test_modified_binary' "$output"
    assert_output_matches "combined: stage5 custom binary" \
        'Stage\[5\][[:space:]]+Custom Binary[[:space:]].*_cfg0000_test_custom_binary' "$output"
    assert_output_matches "combined: stage5 file to link" \
        'Stage\[5\][[:space:]]+File to Link[[:space:]].*_cfg0000_test_file_2_link' "$output"
    assert_output_matches "combined: stage5 link to file" \
        'Stage\[5\][[:space:]]+Link to File[[:space:]].*_cfg0000_test_link_2_file' "$output"
    assert_output_matches "combined: stage5 link to link" \
        'Stage\[5\][[:space:]]+Link to Link[[:space:]].*_cfg0000_test_link_2_link' "$output"

    local count
    count="$(echo "$output" | grep -cE '_cfg[0-9]{4}_' || true)"
    if [[ "$count" -eq "$EXPECTED_MARKER_COUNT" ]]; then
        pass "combined: $EXPECTED_MARKER_COUNT pending markers listed"
    else
        fail "combined: expected $EXPECTED_MARKER_COUNT markers, got $count"
    fi
}

tier_a_per_scenario() {
    echo "=== Tier A: classify per scenario (-lv) ==="
    local output

    # stage1-unmodified-text
    setup_sandbox stage1-unmodified-text
    output="$(run_cfg_update -lv 2>&1)" || true
    assert_output_matches "isolated stage1-unmodified-text" \
        'Stage\[1\][[:space:]]+Unmodified File[[:space:]].*_cfg0000_test_unmodified_file' "$output"
    assert_output_matches "isolated stage1-unmodified-text: only one marker" \
        '^1[[:space:]]+Stage\[1\]' "$output"

    setup_sandbox stage1-unmodified-binary
    output="$(run_cfg_update -lv 2>&1)" || true
    assert_output_matches "isolated stage1-unmodified-binary" \
        'Stage\[1\][[:space:]]+Unmodified Binary[[:space:]].*_cfg0000_test_unmodified_binary' "$output"

    setup_sandbox stage2-3way-merge-success
    output="$(run_cfg_update -lv 2>&1)" || true
    assert_output_matches "isolated stage2-3way-merge-success" \
        'Stage\[2\][[:space:]]+Modified File[[:space:]].*_cfg0000_test_auto_3way_success' "$output"

    setup_sandbox stage2-3way-merge-conflict
    output="$(run_cfg_update -lv 2>&1)" || true
    assert_output_matches "isolated stage2-3way-merge-conflict" \
        'Stage\[2\][[:space:]]+Modified File[[:space:]].*_cfg0000_test_auto_3way_conflict' "$output"

    setup_sandbox stage4-manual-2way
    output="$(run_cfg_update -lv 2>&1)" || true
    assert_output_matches "isolated stage4-manual-2way 0000" \
        'Stage\[4\][[:space:]]+Modified File[[:space:]].*_cfg0000_test_manual_2way' "$output"
    assert_output_matches "isolated stage4-manual-2way 0001" \
        'Stage\[4\][[:space:]]+Modified File[[:space:]].*_cfg0001_test_manual_2way' "$output"

    setup_sandbox stage4-custom-file
    output="$(run_cfg_update -lv 2>&1)" || true
    assert_output_matches "isolated stage4-custom-file" \
        'Stage\[4\][[:space:]]+Custom File[[:space:]].*_cfg0000_test_custom_file' "$output"

    setup_sandbox stage5-modified-binary
    output="$(run_cfg_update -lv 2>&1)" || true
    assert_output_matches "isolated stage5-modified-binary" \
        'Stage\[5\][[:space:]]+Modified Binary[[:space:]].*_cfg0000_test_modified_binary' "$output"

    setup_sandbox stage5-custom-binary
    output="$(run_cfg_update -lv 2>&1)" || true
    assert_output_matches "isolated stage5-custom-binary" \
        'Stage\[5\][[:space:]]+Custom Binary[[:space:]].*_cfg0000_test_custom_binary' "$output"

    setup_sandbox stage5-file-to-link
    output="$(run_cfg_update -lv 2>&1)" || true
    assert_output_matches "isolated stage5-file-to-link" \
        'Stage\[5\][[:space:]]+File to Link[[:space:]].*_cfg0000_test_file_2_link' "$output"

    setup_sandbox stage5-link-to-file
    output="$(run_cfg_update -lv 2>&1)" || true
    assert_output_matches "isolated stage5-link-to-file" \
        'Stage\[5\][[:space:]]+Link to File[[:space:]].*_cfg0000_test_link_2_file' "$output"

    setup_sandbox stage5-link-to-link
    output="$(run_cfg_update -lv 2>&1)" || true
    assert_output_matches "isolated stage5-link-to-link" \
        'Stage\[5\][[:space:]]+Link to Link[[:space:]].*_cfg0000_test_link_2_link' "$output"
}

tier_a_protected_dirs() {
    echo "=== Tier A: protected dirs (-s) ==="
    setup_sandbox all
    local output
    output="$(run_cfg_update -s 2>&1)" || true
    assert_output_matches "protected dirs lists sandbox etc/test" \
        "${SANDBOX}/etc/test" "$output"
}

tier_a_ancestor_backups() {
    echo "=== Tier A: ancestor backups on disk ==="
    setup_sandbox all
    local backup_root="$SANDBOX/var/lib/cfg-update/backups${SANDBOX}/etc/test"
    assert_file_exists "ancestor: 3-way success" \
        "$backup_root/._new-cfg_test_auto_3way_success"
    assert_file_exists "ancestor: 3-way conflict" \
        "$backup_root/._new-cfg_test_auto_3way_conflict"
}

tier_b_pretend_auto() {
    echo "=== Tier B: pretend automatic (-p -au) ==="
    setup_sandbox all auto
    local output
    output="$(run_cfg_update -p -au 2>&1)" || true

    assert_output_matches "pretend stage1 runs" '<< Stage1 >>' "$output"
    assert_output_matches "pretend stage2 runs" '<< Stage2 >>' "$output"
    assert_output_matches "pretend stage3 skipped" '<< Stage3 >> disabled with -a' "$output"

    assert_file_contains "pretend left live file at v1.0" \
        "$SANDBOX/etc/test/test_unmodified_file" "#version 1.0"
    assert_file_contains "pretend kept cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_unmodified_file" "#version 1.1"
}

tier_c_execute_auto() {
    echo "=== Tier C: execute automatic (-au) ==="
    require_cmd diff3

    setup_sandbox stage1-unmodified-text auto
    run_cfg_update -au >/dev/null
    assert_file_contains "stage1 replaced live file" \
        "$SANDBOX/etc/test/test_unmodified_file" "#version 1.1"
    assert_missing "stage1 removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_unmodified_file"

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
    parse_args "$@"

    require_cmd perl
    require_cmd grep
    require_cmd sed
    require_cmd mktemp
    require_cmd md5sum
    [[ -x "$CFG_UPDATE" || -f "$CFG_UPDATE" ]] || die "cfg-update not found at $CFG_UPDATE"
    [[ -x "$LINT_FIXTURES" ]] || chmod +x "$LINT_FIXTURES"

    perl -MTerm::ANSIColor -MTerm::ReadKey -e 1 2>/dev/null \
        || die "Perl modules missing (install Term::ANSIColor and Term::ReadKey)"

    tier0_static
    tier0_lint_fixtures
    tier_a_classify_combined
    tier_a_per_scenario
    tier_a_protected_dirs
    tier_a_ancestor_backups
    tier_b_pretend_auto
    tier_c_execute_auto

    echo ""
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
    if [[ "$REQUIRE_FULL" -eq 1 && "$FULL_TIERS_SKIPPED" -gt 0 ]]; then
        fail "--full set but $FULL_TIERS_SKIPPED tier(s) were skipped"
    fi
    [[ "$FAIL" -eq 0 ]]
}

main "$@"