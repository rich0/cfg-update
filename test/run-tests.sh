#!/bin/bash
# Integration test harness for cfg-update fixtures.
# All tiers run without root when cfg-update is invoked with --testsandbox (stage 6c).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/test/fixtures"
INDEX_FIXTURE="$FIXTURES/index-portage"
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

assert_file_equals() {
    local desc="$1" actual="$2" expected="$3"
    if [[ -f "$actual" && -f "$expected" ]] && cmp -s "$actual" "$expected"; then
        pass "$desc"
    else
        fail "$desc (actual: $actual, expected: $expected)"
        if [[ -f "$actual" && -f "$expected" ]]; then
            echo "--- diff ---" >&2
            diff -u "$expected" "$actual" >&2 || true
            echo "------------" >&2
        fi
    fi
}

assert_md5_equals() {
    local desc="$1" file="$2" expected_hash="$3"
    local actual_hash
    actual_hash="$(md5sum "$file" | awk '{print $1}')"
    if [[ "$actual_hash" == "$expected_hash" ]]; then
        pass "$desc"
    else
        fail "$desc (file: $file, expected: $expected_hash, actual: $actual_hash)"
    fi
}

assert_symlink() {
    local desc="$1" expected_target="$2" linkpath="$3"
    if [[ -L "$linkpath" ]]; then
        local actual
        actual="$(readlink "$linkpath")"
        if [[ "$actual" == "$expected_target" ]]; then
            pass "$desc"
        else
            fail "$desc (link: $linkpath, expected: $expected_target, actual: $actual)"
        fi
    else
        fail "$desc (not a symlink: $linkpath)"
    fi
}

write_test_config() {
    local conf="$1" index="$2" backup="$3"
    local stages="${4:-all}"
    local merge_tool="${5:-/usr/bin/diff3}"
    local s1=yes s2=yes s3=yes s4=yes s5=yes
    if [[ "$stages" == "auto" ]]; then
        s3=no s4=no s5=no
    elif [[ "$stages" == "manual" ]]; then
        s1=no s2=no
    fi
    cat >"$conf" <<EOF
MERGE_TOOL = $merge_tool
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
    local stages="${2:-all}"
    local merge_tool="${3:-/usr/bin/diff3}"
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
        "$stages" \
        "$merge_tool"
}

run_cfg_update() {
    local extra_args=("$@")
    CFG_UPDATE_CONF="$SANDBOX/etc/cfg-update.conf" \
    CFG_UPDATE_HOSTS="$HOSTS_FILE" \
    PATH="$SANDBOX/bin:$PATH" \
    perl "$CFG_UPDATE" --ebuild --testsandbox "${extra_args[@]}"
}

run_cfg_update_stdin() {
    local keys="$1"
    shift
    local extra_args=("$@")
    printf '%b' "$keys" | run_cfg_update "${extra_args[@]}"
}

remap_sandbox_paths() {
    sed "s|@SANDBOX@|$SANDBOX|g" "$1"
}

write_index_test_config() {
    local conf="$1" index="$2" backup="$3" pkg_db="$4" install_log="$5"
    cat >"$conf" <<EOF
MERGE_TOOL = /usr/bin/diff3
ENABLE_BACKUPS = yes
ENABLE_STAGE1 = yes
ENABLE_STAGE2 = yes
ENABLE_STAGE3 = yes
ENABLE_STAGE4 = yes
ENABLE_STAGE5 = yes
INDEX_FILE = $index
BACKUP_PATH = $backup
PKG_DB = $pkg_db
INSTALL_LOG = $install_log
EOF
}

setup_index_sandbox() {
    local index_variant="$1"
    local emerge_variant="$2"
    local with_marker="${3:-no}"

    SANDBOX="$(mktemp -d)"
    export CFG_UPDATE_TEST_SANDBOX="$SANDBOX"

    mkdir -p "$SANDBOX/etc/test" \
             "$SANDBOX/var/lib/cfg-update/backups" \
             "$SANDBOX/var/log" \
             "$SANDBOX/var/db/pkg/app-test/test-pkg-1.0" \
             "$SANDBOX/bin"

    cat >"$SANDBOX/bin/portageq" <<'EOF'
#!/bin/bash
echo "\"${CFG_UPDATE_TEST_SANDBOX}/etc/test\""
EOF
    chmod +x "$SANDBOX/bin/portageq"

    cp -a "$INDEX_FIXTURE/etc/test_unmodified_file" "$SANDBOX/etc/test/"
    if [[ "$with_marker" == yes ]]; then
        cp -a "$FIXTURES/stage1-unmodified-text/etc/._cfg0000_test_unmodified_file" \
            "$SANDBOX/etc/test/"
    fi

    remap_sandbox_paths "$INDEX_FIXTURE/var/db/pkg/app-test/test-pkg-1.0/CONTENTS.template" \
        >"$SANDBOX/var/db/pkg/app-test/test-pkg-1.0/CONTENTS"
    cp "$INDEX_FIXTURE/emerge.log.$emerge_variant" "$SANDBOX/var/log/emerge.log"
    remap_sandbox_paths "$INDEX_FIXTURE/checksum.index.$index_variant" \
        >"$SANDBOX/var/lib/cfg-update/checksum.index"

    write_index_test_config \
        "$SANDBOX/etc/cfg-update.conf" \
        "$SANDBOX/var/lib/cfg-update/checksum.index" \
        "$SANDBOX/var/lib/cfg-update/backups" \
        "$SANDBOX/var/db/pkg" \
        "$SANDBOX/var/log/emerge.log"
}

index_golden_path() {
    remap_sandbox_paths "$INDEX_FIXTURE/checksum.index.current"
}

assert_index_header() {
    local desc="$1" file="$2" expected_ts="$3"
    local header
    header="$(head -1 "$file")"
    if [[ "$header" == "Portage:$expected_ts" ]]; then
        pass "$desc"
    else
        fail "$desc (expected Portage:$expected_ts, got: $header)"
    fi
}

run_cfg_update_index() {
    run_cfg_update -i "$@"
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
    local output

    setup_sandbox stage1-unmodified-text auto
    run_cfg_update -au >/dev/null
    assert_file_equals "stage1 text matches golden" \
        "$SANDBOX/etc/test/test_unmodified_file" \
        "$FIXTURES/stage1-unmodified-text/expected/test_unmodified_file"
    assert_missing "stage1 removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_unmodified_file"

    setup_sandbox stage1-unmodified-binary auto
    run_cfg_update -au >/dev/null
    assert_file_equals "stage1 binary matches golden" \
        "$SANDBOX/etc/test/test_unmodified_binary" \
        "$FIXTURES/stage1-unmodified-binary/expected/test_unmodified_binary"
    assert_md5_equals "stage1 binary MD5 matches index" \
        "$SANDBOX/etc/test/test_unmodified_binary" "6964280fbdcfa71b9bb39c07ef72f506"
    assert_missing "stage1 binary removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_unmodified_binary"

    setup_sandbox stage2-3way-merge-success auto
    run_cfg_update -au >/dev/null
    assert_file_equals "stage2 merge matches golden" \
        "$SANDBOX/etc/test/test_auto_3way_success" \
        "$FIXTURES/stage2-3way-merge-success/expected/test_auto_3way_success"
    assert_missing "stage2 removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_auto_3way_success"
    if [[ -f "$SANDBOX/etc/test/test_auto_3way_success" ]] && \
       grep -qE '^<<<<<<<|^=======|^>>>>>>>' "$SANDBOX/etc/test/test_auto_3way_success"; then
        fail "stage2 merge left conflict markers"
    else
        pass "stage2 merge has no conflict markers"
    fi

    setup_sandbox stage2-3way-merge-conflict auto
    output="$(run_cfg_update -au 2>&1)" || true
    assert_file_equals "stage2 conflict left live file unchanged" \
        "$SANDBOX/etc/test/test_auto_3way_conflict" \
        "$FIXTURES/stage2-3way-merge-conflict/expected/test_auto_3way_conflict"
    assert_file_exists "stage2 conflict kept cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_auto_3way_conflict"
    assert_missing "stage2 conflict removed temp merge file" \
        "$SANDBOX/etc/test/test_auto_3way_conflict.merge"
    assert_output_matches "stage2 conflict reported merge conflict" \
        'Merge conflict\(s\) found' "$output"
    assert_output_matches "stage2 conflict re-scheduled for manual" \
        're-scheduled for manual updating' "$output"

    output="$(run_cfg_update_stdin $'s\n' -mu 2>&1)" || true
    assert_output_matches "stage2 conflict handoff runs stage3" \
        '<< Stage3 >>' "$output"
}

tier_d_execute_manual() {
    echo "=== Tier D: execute manual (-mu, stdin) ==="

    setup_sandbox stage2-3way-merge-conflict auto
    run_cfg_update -au >/dev/null
    run_cfg_update_stdin $'1\n' -mu >/dev/null
    assert_file_equals "stage3 conflict replace matches golden" \
        "$SANDBOX/etc/test/test_auto_3way_conflict" \
        "$FIXTURES/stage2-3way-merge-conflict/expected/test_auto_3way_conflict.after_replace"
    assert_missing "stage3 conflict replace removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_auto_3way_conflict"

    setup_sandbox stage4-manual-2way manual
    run_cfg_update_stdin $'1\n1\n' -mu >/dev/null
    assert_file_equals "stage4 manual replace matches golden" \
        "$SANDBOX/etc/test/test_manual_2way" \
        "$FIXTURES/stage4-manual-2way/expected/test_manual_2way"
    assert_missing "stage4 manual replace removed cfg0000 marker" \
        "$SANDBOX/etc/test/._cfg0000_test_manual_2way"
    assert_missing "stage4 manual replace removed cfg0001 marker" \
        "$SANDBOX/etc/test/._cfg0001_test_manual_2way"

    setup_sandbox stage4-manual-2way manual
    run_cfg_update_stdin $'2\n2\n' -mu >/dev/null
    assert_file_equals "stage4 manual keep matches golden" \
        "$SANDBOX/etc/test/test_manual_2way" \
        "$FIXTURES/stage4-manual-2way/expected/test_manual_2way.keep"
    assert_missing "stage4 manual keep removed cfg0000 marker" \
        "$SANDBOX/etc/test/._cfg0000_test_manual_2way"
    assert_missing "stage4 manual keep removed cfg0001 marker" \
        "$SANDBOX/etc/test/._cfg0001_test_manual_2way"

    setup_sandbox stage4-custom-file manual
    run_cfg_update_stdin $'2\n' -mu >/dev/null
    assert_file_equals "stage4 custom keep matches golden" \
        "$SANDBOX/etc/test/test_custom_file" \
        "$FIXTURES/stage4-custom-file/expected/test_custom_file"
    assert_missing "stage4 custom keep removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_custom_file"

    setup_sandbox stage5-modified-binary manual
    run_cfg_update_stdin $'1\n' -mu >/dev/null
    assert_file_equals "stage5 modified binary replace matches golden" \
        "$SANDBOX/etc/test/test_modified_binary" \
        "$FIXTURES/stage5-modified-binary/expected/test_modified_binary"
    assert_missing "stage5 modified binary removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_modified_binary"

    setup_sandbox stage5-custom-binary manual
    run_cfg_update_stdin $'1\n' -mu >/dev/null
    assert_file_equals "stage5 custom binary replace matches golden" \
        "$SANDBOX/etc/test/test_custom_binary" \
        "$FIXTURES/stage5-custom-binary/expected/test_custom_binary"
    assert_missing "stage5 custom binary removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_custom_binary"

    setup_sandbox stage5-file-to-link manual
    run_cfg_update_stdin $'1\n' -mu >/dev/null
    assert_symlink "stage5 file-to-link replace is symlink" \
        "link_target_after_update" "$SANDBOX/etc/test/test_file_2_link"
    assert_missing "stage5 file-to-link removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_file_2_link"

    setup_sandbox stage5-link-to-file manual
    run_cfg_update_stdin $'1\n' -mu >/dev/null
    assert_file_equals "stage5 link-to-file replace matches golden" \
        "$SANDBOX/etc/test/test_link_2_file" \
        "$FIXTURES/stage5-link-to-file/expected/test_link_2_file"
    assert_missing "stage5 link-to-file removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_link_2_file"

    setup_sandbox stage5-link-to-link manual
    run_cfg_update_stdin $'1\n' -mu >/dev/null
    assert_symlink "stage5 link-to-link replace is symlink" \
        "link_target_after_update" "$SANDBOX/etc/test/test_link_2_link"
    assert_missing "stage5 link-to-link removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_link_2_link"
}

tier_e_index_portage() {
    echo "=== Tier E: Portage --index (-i) ==="
    local output golden index_before

    setup_index_sandbox current current
    index_before="$(mktemp)"
    cp "$SANDBOX/var/lib/cfg-update/checksum.index" "$index_before"
    output="$(run_cfg_update_index 2>&1)" || true
    assert_output_matches "index up-to-date skips rebuild" \
        'Checksum index is up-to-date' "$output"
    assert_file_equals "index up-to-date left file unchanged" \
        "$SANDBOX/var/lib/cfg-update/checksum.index" "$index_before"
    rm -f "$index_before"

    setup_index_sandbox stale current
    golden="$(mktemp)"
    index_golden_path >"$golden"
    run_cfg_update_index >/dev/null
    assert_index_header "index stale rebuild updated header" \
        "$SANDBOX/var/lib/cfg-update/checksum.index" "1690000000"
    assert_file_equals "index stale rebuild matches golden" \
        "$SANDBOX/var/lib/cfg-update/checksum.index" "$golden"
    rm -f "$golden"

    setup_index_sandbox stale current yes
    index_before="$(mktemp)"
    cp "$SANDBOX/var/lib/cfg-update/checksum.index" "$index_before"
    output="$(run_cfg_update_index 2>&1)" || true
    assert_output_matches "index marker present skips rebuild" \
        'Skipping checksum index updating' "$output"
    assert_file_equals "index marker present left file unchanged" \
        "$SANDBOX/var/lib/cfg-update/checksum.index" "$index_before"
    rm -f "$index_before"

    setup_index_sandbox stale current yes
    run_cfg_update_index -f >/dev/null
    assert_index_header "index force rebuild uses zero timestamp" \
        "$SANDBOX/var/lib/cfg-update/checksum.index" "0000000000"
    assert_file_contains "index force rebuild has indexed path" \
        "$SANDBOX/var/lib/cfg-update/checksum.index" \
        "$SANDBOX/etc/test/test_unmodified_file e2dda9550032d229538e6ae35652ca6d"

    setup_index_sandbox stale current
    run_cfg_update_index >/dev/null
    cp -a "$FIXTURES/stage1-unmodified-text/etc/._cfg0000_test_unmodified_file" \
        "$SANDBOX/etc/test/"
    output="$(run_cfg_update -lv 2>&1)" || true
    assert_output_matches "index rebuild enables stage1 classify" \
        'Stage\[1\][[:space:]]+Unmodified File[[:space:]].*_cfg0000_test_unmodified_file' "$output"
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
    tier_d_execute_manual
    tier_e_index_portage

    echo ""
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
    if [[ "$REQUIRE_FULL" -eq 1 && "$FULL_TIERS_SKIPPED" -gt 0 ]]; then
        fail "--full set but $FULL_TIERS_SKIPPED tier(s) were skipped"
    fi
    [[ "$FAIL" -eq 0 ]]
}

main "$@"