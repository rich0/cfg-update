#!/bin/bash
# Integration test harness for cfg-update fixtures.
# All tiers run without root when cfg-update is invoked with --testsandbox (stage 6c).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$REPO_ROOT/test/fixtures"
INDEX_FIXTURE="$FIXTURES/index-portage"
CFG_UPDATE="$REPO_ROOT/cfg-update"
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
    elif [[ "$stages" == "stage3_only" ]]; then
        s1=no s2=no s4=no s5=no
    elif [[ "$stages" == "stage4_only" ]]; then
        s1=no s2=no s3=no s5=no
    elif [[ "$stages" == "stage5_only" ]]; then
        s1=no s2=no s3=no s4=no
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

install_portageq_mock() {
    cat >"$SANDBOX/bin/portageq" <<'EOF'
#!/bin/bash
echo "\"${CFG_UPDATE_TEST_SANDBOX}/etc/test\" \"${CFG_UPDATE_TEST_SANDBOX}/etc/test2\""
EOF
    chmod +x "$SANDBOX/bin/portageq"
}

setup_sandbox() {
    local mode="${1:-all}"  # all | scenario name
    local stages="${2:-all}"
    local merge_tool="${3:-/usr/bin/diff3}"
    SANDBOX="$(mktemp -d)"
    export CFG_UPDATE_TEST_SANDBOX="$SANDBOX"

    mkdir -p "$SANDBOX/etc/test" "$SANDBOX/etc/test2" \
             "$SANDBOX/var/lib/cfg-update/backups/etc/test" "$SANDBOX/bin"

    install_portageq_mock

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
            [[ "$(basename "$scenario")" == "stage0-no-index" ]] && continue
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

setup_sandbox_no_index() {
    local scenario="${1:-stage0-no-index}"
    setup_sandbox "$scenario"
    rm -f "$SANDBOX/var/lib/cfg-update/checksum.index"
    assert_missing "no-index sandbox removed checksum.index" \
        "$SANDBOX/var/lib/cfg-update/checksum.index"
}

setup_multi_config_protect_sandbox() {
    local stages="${1:-auto}"
    SANDBOX="$(mktemp -d)"
    export CFG_UPDATE_TEST_SANDBOX="$SANDBOX"

    mkdir -p "$SANDBOX/etc/test" "$SANDBOX/etc/test2" \
             "$SANDBOX/var/lib/cfg-update/backups/etc/test" \
             "$SANDBOX/var/lib/cfg-update/backups/etc/test2" \
             "$SANDBOX/bin"

    install_portageq_mock

    cp -a "$FIXTURES/stage1-unmodified-text/etc/." "$SANDBOX/etc/test/"
    cp -a "$FIXTURES/stage1-unmodified-binary/etc/." "$SANDBOX/etc/test2/"
    {
        echo "Portage:0"
        sed "s|/etc/test|${SANDBOX}/etc/test|g" \
            "$FIXTURES/stage1-unmodified-text/checksum.index.entry"
        sed "s|/etc/test|${SANDBOX}/etc/test2|g" \
            "$FIXTURES/stage1-unmodified-binary/checksum.index.entry"
    } >"$SANDBOX/var/lib/cfg-update/checksum.index"

    write_test_config \
        "$SANDBOX/etc/cfg-update.conf" \
        "$SANDBOX/var/lib/cfg-update/checksum.index" \
        "$SANDBOX/var/lib/cfg-update/backups" \
        "$stages"
}

run_cfg_update() {
    local extra_args=("$@")
    CFG_UPDATE_CONF="$SANDBOX/etc/cfg-update.conf" \
    PATH="$SANDBOX/bin:$PATH" \
    perl "$CFG_UPDATE" --ebuild --testsandbox "${extra_args[@]}"
}

run_cfg_update_stdin() {
    local keys="$1"
    shift
    local extra_args=("$@")
    printf '%b' "$keys" | run_cfg_update "${extra_args[@]}"
}

install_mock_kdiff3() {
    local golden_merge="${1:-}"
    cat >"$SANDBOX/bin/kdiff3" <<'EOF'
#!/bin/bash
log="${CFG_UPDATE_TEST_SANDBOX}/mock-kdiff3.log"
echo "$*" >>"$log"
outfile=""
ancestor=""
threeway="no"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) outfile="$2"; shift 2 ;;
        -b) ancestor="$2"; threeway="yes"; shift 2 ;;
        -m) shift ;;
        *) shift ;;
    esac
done
echo "THREE_WAY=$threeway" >>"$log"
if [[ -n "$outfile" && -f "${CFG_UPDATE_TEST_SANDBOX}/golden.merge" ]]; then
    cp "${CFG_UPDATE_TEST_SANDBOX}/golden.merge" "$outfile"
fi
exit 0
EOF
    chmod +x "$SANDBOX/bin/kdiff3"
    if [[ -n "$golden_merge" ]]; then
        cp "$golden_merge" "$SANDBOX/golden.merge"
    fi
}

assert_stage_output() {
    local desc="$1" stage="$2" output="$3"
    assert_output_matches "$desc: stage banner" \
        "<< Stage${stage} >>" "$output"
    case "$stage" in
        3)
            assert_output_matches "$desc: 3-way merge mode" \
                'manual 3-way merging, starting' "$output"
            assert_output_not_matches "$desc: not 2-way mode" \
                'manual 2-way merging, starting' "$output"
            assert_output_not_matches "$desc: no stage4 diff3 switch" \
                'diff3 cannot be used for this stage' "$output"
            assert_output_not_matches "$desc: offers merge tool" \
                'This update cannot be done with the diff/merge tool' "$output"
            ;;
        4)
            assert_output_matches "$desc: 2-way merge mode" \
                'manual 2-way merging, starting' "$output"
            assert_output_not_matches "$desc: not 3-way mode" \
                'manual 3-way merging, starting' "$output"
            assert_output_matches "$desc: stage4 diff3-to-sdiff switch" \
                'diff3 cannot be used for this stage, changing to sdiff' "$output"
            assert_output_not_matches "$desc: no stage5 non-merge path" \
                'This update cannot be done with the diff/merge tool' "$output"
            ;;
        5)
            assert_output_matches "$desc: manual update mode" \
                'manual updating, starting' "$output"
            assert_output_not_matches "$desc: not 3-way mode" \
                'manual 3-way merging, starting' "$output"
            assert_output_not_matches "$desc: not 2-way mode" \
                'manual 2-way merging, starting' "$output"
            assert_output_not_matches "$desc: no stage4 diff3 switch" \
                'diff3 cannot be used for this stage' "$output"
            assert_output_not_matches "$desc: no merge-tool offer" \
                'Merge manually with file' "$output"
            ;;
    esac
}

install_mock_sdiff() {
    local golden_merge="${1:-}"
    cat >"$SANDBOX/bin/sdiff" <<'EOF'
#!/bin/bash
log="${CFG_UPDATE_TEST_SANDBOX}/mock-sdiff.log"
echo "$*" >>"$log"
outfile=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) outfile="$2"; shift 2 ;;
        *) shift ;;
    esac
done
echo "TWO_WAY=yes" >>"$log"
if [[ -n "$outfile" && -f "${CFG_UPDATE_TEST_SANDBOX}/golden.merge" ]]; then
    cp "${CFG_UPDATE_TEST_SANDBOX}/golden.merge" "$outfile"
fi
exit 0
EOF
    chmod +x "$SANDBOX/bin/sdiff"
    if [[ -n "$golden_merge" ]]; then
        cp "$golden_merge" "$SANDBOX/golden.merge"
    fi
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

    mkdir -p "$SANDBOX/etc/test" "$SANDBOX/etc/test2" \
             "$SANDBOX/var/lib/cfg-update/backups" \
             "$SANDBOX/var/log" \
             "$SANDBOX/var/db/pkg/app-test/test-pkg-1.0" \
             "$SANDBOX/bin"

    install_portageq_mock

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
    if perl "$CFG_UPDATE" --test 2>&1 | grep -q "Nothing to test"; then
        fail "--test stub still present"
    else
        pass "--test stub removed"
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

tier0_bump_version_dry_run() {
    echo "=== Tier 0: bump-version dry-run ==="
    local script="$REPO_ROOT/scripts/bump-version.sh"
    [[ -f "$script" ]] || { skip "scripts/bump-version.sh not present"; return; }
    [[ -x "$script" ]] || chmod +x "$script"
    if bash -n "$script"; then
        pass "bash -n bump-version.sh"
    else
        fail "bash -n bump-version.sh"
        return
    fi
    local output
    output="$("$script" 9.9.9 --dry-run 2>&1)" || { fail "bump-version.sh --dry-run exited non-zero"; return; }
    if echo "$output" | grep -q 'git mv'; then
        pass "bump-version dry-run mentions git mv"
    else
        fail "bump-version dry-run missing git mv"
    fi
    if echo "$output" | grep -q 'cfg-update'; then
        pass "bump-version dry-run mentions cfg-update"
    else
        fail "bump-version dry-run missing cfg-update"
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

tier_a_no_index() {
    echo "=== Tier A: missing checksum index (no-index) ==="
    local output

    setup_sandbox_no_index stage0-no-index
    output="$(run_cfg_update -d -lv 2>&1)" || true
    assert_output_matches "no-index: debug shows unknown state" \
        'State of the current file : No index found' "$output"
    assert_output_not_matches "no-index: marker not routed to any stage" \
        'Stage\[[1-5]\][[:space:]].*_cfg0000_test_no_index_file' "$output"

    setup_sandbox_no_index stage0-no-index
    output="$(run_cfg_update -au 2>&1)" || true
    assert_output_matches "no-index: stage1 skips when index absent" \
        '<< Stage1 >>.*not found, skipping' "$output"
}

tier_a_removed_flags() {
    echo "=== Tier A: removed flags regression ==="
    local output f1 f2

    output="$(run_cfg_update -s 2>&1)" || true
    assert_output_not_matches "removed flag: -s not accepted" \
        'CONFIG_PROTECT|protected directories' "$output"
    assert_output_matches "removed flag: -s shows usage" \
        'missing valid options|USAGE' "$output"

    output="$(run_cfg_update --move-backups 2>&1)" || true
    assert_output_not_matches "removed flag: --move-backups not accepted" \
        'Moving backup|move your backups' "$output"
    assert_output_matches "removed flag: --move-backups shows usage" \
        'missing valid options|USAGE' "$output"

    f1="$FIXTURES/stage1-unmodified-text/etc/test_unmodified_file"
    f2="$FIXTURES/stage1-unmodified-text/etc/._cfg0000_test_unmodified_file"
    output="$(run_cfg_update "$f1" "$f2" 2>&1)" || true
    assert_output_not_matches "removed mode: ad-hoc 2-file diff not accepted" \
        'Merged output has been saved' "$output"
    assert_output_matches "removed mode: ad-hoc 2-file diff shows usage" \
        'missing valid options|USAGE' "$output"
}

tier_a_multi_config_protect() {
    echo "=== Tier A: multi CONFIG_PROTECT dirs ==="
    local output

    setup_multi_config_protect_sandbox auto
    output="$(run_cfg_update -lv 2>&1)" || true
    assert_output_matches "multi-dir: classifies marker in etc/test" \
        'Stage\[1\][[:space:]]+Unmodified File[[:space:]].*etc/test/._cfg0000_test_unmodified_file' "$output"
    assert_output_matches "multi-dir: classifies marker in etc/test2" \
        'Stage\[1\][[:space:]]+Unmodified Binary[[:space:]].*etc/test2/._cfg0000_test_unmodified_binary' "$output"

    run_cfg_update -au >/dev/null
    output="$(run_cfg_update -b 2>&1)" || true
    assert_output_matches "multi-dir: backup list includes etc/test file" \
        'etc/test/test_unmodified_file' "$output"
    assert_output_matches "multi-dir: backup list includes etc/test2 file" \
        'etc/test2/test_unmodified_binary' "$output"
    assert_output_matches "multi-dir: backup list has two numbered entries" \
        '^[[:space:]]*1[[:space:]]' "$output"
    assert_output_matches "multi-dir: backup list second entry" \
        '^[[:space:]]*2[[:space:]]' "$output"
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
    echo "=== Tier D: execute manual (-u, stage-isolated, stdin) ==="
    local output

    # Stage 3: replace path (MF + ancestor, no stage 4/5)
    setup_sandbox stage2-3way-merge-conflict stage3_only
    output="$(run_cfg_update_stdin $'1\n' -u 2>&1)" || true
    assert_stage_output "stage3 conflict replace" 3 "$output"
    assert_file_equals "stage3 conflict replace matches golden" \
        "$SANDBOX/etc/test/test_auto_3way_conflict" \
        "$FIXTURES/stage2-3way-merge-conflict/expected/test_auto_3way_conflict.after_replace"
    assert_missing "stage3 conflict replace removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_auto_3way_conflict"

    # Stage 3: mock kdiff3 must receive 3-way (-b ancestor) invocation
    setup_sandbox stage2-3way-merge-conflict stage3_only
    install_mock_kdiff3 \
        "$FIXTURES/stage2-3way-merge-conflict/expected/test_auto_3way_conflict.after_replace"
    sed -i "s|^MERGE_TOOL = .*|MERGE_TOOL = $SANDBOX/bin/kdiff3|" "$SANDBOX/etc/cfg-update.conf"
    output="$(run_cfg_update_stdin $'y\n1\n' -u 2>&1)" || true
    assert_stage_output "stage3 conflict mock merge" 3 "$output"
    assert_file_contains "stage3 mock kdiff3 used 3-way merge" \
        "$SANDBOX/mock-kdiff3.log" "THREE_WAY=yes"
    assert_file_equals "stage3 mock merge matches golden" \
        "$SANDBOX/etc/test/test_auto_3way_conflict" \
        "$FIXTURES/stage2-3way-merge-conflict/expected/test_auto_3way_conflict.after_replace"

    # Stage 4: mock sdiff must run 2-way merge (no -b ancestor)
    setup_sandbox stage4-manual-2way stage4_only
    install_mock_sdiff "$FIXTURES/stage4-manual-2way/expected/test_manual_2way"
    output="$(run_cfg_update_stdin $'y\n1\ny\n1\n' -u 2>&1)" || true
    assert_stage_output "stage4 manual mock merge" 4 "$output"
    assert_output_matches "stage4 switches diff3 to sdiff" \
        'diff3 cannot be used for this stage, changing to sdiff' "$output"
    assert_file_contains "stage4 mock sdiff used 2-way merge" \
        "$SANDBOX/mock-sdiff.log" "TWO_WAY=yes"
    assert_file_equals "stage4 mock merge matches golden" \
        "$SANDBOX/etc/test/test_manual_2way" \
        "$FIXTURES/stage4-manual-2way/expected/test_manual_2way"
    assert_missing "stage4 mock merge removed cfg0000 marker" \
        "$SANDBOX/etc/test/._cfg0000_test_manual_2way"

    # Stage 4: replace (MF, no ancestor — must not run stage 3/5 handlers)
    setup_sandbox stage4-manual-2way stage4_only
    output="$(run_cfg_update_stdin $'1\n1\n' -u 2>&1)" || true
    assert_stage_output "stage4 manual replace" 4 "$output"
    assert_output_matches "stage4 switches diff3 to sdiff" \
        'diff3 cannot be used for this stage, changing to sdiff' "$output"
    assert_file_equals "stage4 manual replace matches golden" \
        "$SANDBOX/etc/test/test_manual_2way" \
        "$FIXTURES/stage4-manual-2way/expected/test_manual_2way"
    assert_missing "stage4 manual replace removed cfg0000 marker" \
        "$SANDBOX/etc/test/._cfg0000_test_manual_2way"
    assert_missing "stage4 manual replace removed cfg0001 marker" \
        "$SANDBOX/etc/test/._cfg0001_test_manual_2way"

    setup_sandbox stage4-manual-2way stage4_only
    output="$(run_cfg_update_stdin $'2\n2\n' -u 2>&1)" || true
    assert_stage_output "stage4 manual keep" 4 "$output"
    assert_file_equals "stage4 manual keep matches golden" \
        "$SANDBOX/etc/test/test_manual_2way" \
        "$FIXTURES/stage4-manual-2way/expected/test_manual_2way.keep"
    assert_missing "stage4 manual keep removed cfg0000 marker" \
        "$SANDBOX/etc/test/._cfg0000_test_manual_2way"
    assert_missing "stage4 manual keep removed cfg0001 marker" \
        "$SANDBOX/etc/test/._cfg0001_test_manual_2way"

    setup_sandbox stage4-custom-file stage4_only
    output="$(run_cfg_update_stdin $'2\n' -u 2>&1)" || true
    assert_stage_output "stage4 custom keep" 4 "$output"
    assert_file_equals "stage4 custom keep matches golden" \
        "$SANDBOX/etc/test/test_custom_file" \
        "$FIXTURES/stage4-custom-file/expected/test_custom_file"
    assert_missing "stage4 custom keep removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_custom_file"

    # Stage 5: binaries and symlinks (must not run stage 3/4 merge handlers)
    setup_sandbox stage5-modified-binary stage5_only
    output="$(run_cfg_update_stdin $'1\n' -u 2>&1)" || true
    assert_stage_output "stage5 modified binary replace" 5 "$output"
    assert_output_matches "stage5 binary uses non-merge prompt" \
        'cannot be done with the diff/merge tool' "$output"
    assert_output_not_matches "stage5 binary not offered merge tool" \
        'to merge the current file and the ._cfg0000_' "$output"
    assert_file_equals "stage5 modified binary replace matches golden" \
        "$SANDBOX/etc/test/test_modified_binary" \
        "$FIXTURES/stage5-modified-binary/expected/test_modified_binary"
    assert_missing "stage5 modified binary removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_modified_binary"

    setup_sandbox stage5-custom-binary stage5_only
    output="$(run_cfg_update_stdin $'1\n' -u 2>&1)" || true
    assert_stage_output "stage5 custom binary replace" 5 "$output"
    assert_file_equals "stage5 custom binary replace matches golden" \
        "$SANDBOX/etc/test/test_custom_binary" \
        "$FIXTURES/stage5-custom-binary/expected/test_custom_binary"
    assert_missing "stage5 custom binary removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_custom_binary"

    setup_sandbox stage5-file-to-link stage5_only
    output="$(run_cfg_update_stdin $'1\n' -u 2>&1)" || true
    assert_stage_output "stage5 file-to-link replace" 5 "$output"
    assert_symlink "stage5 file-to-link replace is symlink" \
        "link_target_after_update" "$SANDBOX/etc/test/test_file_2_link"
    assert_missing "stage5 file-to-link removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_file_2_link"

    setup_sandbox stage5-link-to-file stage5_only
    output="$(run_cfg_update_stdin $'1\n' -u 2>&1)" || true
    assert_stage_output "stage5 link-to-file replace" 5 "$output"
    assert_file_equals "stage5 link-to-file replace matches golden" \
        "$SANDBOX/etc/test/test_link_2_file" \
        "$FIXTURES/stage5-link-to-file/expected/test_link_2_file"
    assert_missing "stage5 link-to-file removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_link_2_file"

    setup_sandbox stage5-link-to-link stage5_only
    output="$(run_cfg_update_stdin $'1\n' -u 2>&1)" || true
    assert_stage_output "stage5 link-to-link replace" 5 "$output"
    assert_symlink "stage5 link-to-link replace is symlink" \
        "link_target_after_update" "$SANDBOX/etc/test/test_link_2_link"
    assert_missing "stage5 link-to-link removed cfg marker" \
        "$SANDBOX/etc/test/._cfg0000_test_link_2_link"
}

tier_f_backups_maintenance() {
    echo "=== Tier F: backups and maintenance (-b, -r, --optimize-backups) ==="
    local output backup_root

    setup_sandbox stage2-3way-merge-success auto
    output="$(run_cfg_update -b 2>&1)" || true
    assert_output_matches "backup list empty before update" \
        'No \(._old-cfg_\*\) files found' "$output"

    run_cfg_update -au >/dev/null
    backup_root="$SANDBOX/var/lib/cfg-update/backups${SANDBOX}/etc/test"
    assert_file_exists "stage2 update created old backup" \
        "$backup_root/._old-cfg_test_auto_3way_success"
    assert_file_exists "stage2 update created new backup" \
        "$backup_root/._new-cfg_test_auto_3way_success"

    output="$(run_cfg_update -b 2>&1)" || true
    assert_output_matches "backup list shows restored target path" \
        'test_auto_3way_success' "$output"
    assert_output_matches "backup list shows numbered entry" \
        '^[[:space:]]*1[[:space:]]' "$output"

    output="$(run_cfg_update_stdin $'y\n' -r 1 2>&1)" || true
    assert_output_matches "restore completes" \
        'Restore complete' "$output"
    assert_file_equals "restore rewrote live config from backup" \
        "$SANDBOX/etc/test/test_auto_3way_success" \
        "$FIXTURES/stage2-3way-merge-success/etc/test_auto_3way_success"
    assert_file_equals "restore rewrote cfg marker from backup" \
        "$SANDBOX/etc/test/._cfg0000_test_auto_3way_success" \
        "$FIXTURES/stage2-3way-merge-success/etc/._cfg0000_test_auto_3way_success"
    assert_missing "restore removed old backup file" \
        "$backup_root/._old-cfg_test_auto_3way_success"
    assert_missing "restore removed new backup file" \
        "$backup_root/._new-cfg_test_auto_3way_success"

    setup_sandbox stage1-unmodified-text auto
    backup_root="$SANDBOX/var/lib/cfg-update/backups${SANDBOX}/etc/test"
    output="$(run_cfg_update --optimize-backups 2>&1)" || true
    assert_output_matches "optimize-backups creates ancestor for unmodified file" \
        'Make file.*_new-cfg_test_unmodified_file' "$output"
    assert_file_exists "optimize-backups wrote new-cfg backup" \
        "$backup_root/._new-cfg_test_unmodified_file"
    assert_file_contains "optimize-backups backup matches live file" \
        "$backup_root/._new-cfg_test_unmodified_file" "#version 1.0"

    setup_sandbox stage1-unmodified-text auto
    backup_root="$SANDBOX/var/lib/cfg-update/backups${SANDBOX}/etc/test"
    run_cfg_update -au >/dev/null
    assert_file_exists "stage1 update created old backup in BACKUP_PATH" \
        "$backup_root/._old-cfg_test_unmodified_file"
    assert_file_exists "stage1 update created new backup in BACKUP_PATH" \
        "$backup_root/._new-cfg_test_unmodified_file"
    assert_missing "stage1 backups not written inline under etc/test (old)" \
        "$SANDBOX/etc/test/._old-cfg_test_unmodified_file"
    assert_missing "stage1 backups not written inline under etc/test (new)" \
        "$SANDBOX/etc/test/._new-cfg_test_unmodified_file"

    setup_sandbox stage1-unmodified-text
    output="$(run_cfg_update --mount 2>&1)" || true
    assert_output_not_matches "removed flag: --mount not accepted" \
        'Mounts remote hosts|mount_hosts|sshfs' "$output"
    assert_output_matches "removed flag: --mount shows usage" \
        'missing valid options|USAGE' "$output"

    output="$(run_cfg_update -h1 -l 2>&1)" || true
    assert_output_not_matches "removed flag: -h1 not accepted" \
        'Value out of range in -h|sshfs|remote host' "$output"
    assert_output_matches "removed flag: -h1 shows usage" \
        'missing valid options|USAGE' "$output"
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
    tier0_bump_version_dry_run
    tier_a_classify_combined
    tier_a_per_scenario
    tier_a_no_index
    tier_a_removed_flags
    tier_a_multi_config_protect
    tier_a_ancestor_backups
    tier_b_pretend_auto
    tier_c_execute_auto
    tier_d_execute_manual
    tier_e_index_portage
    tier_f_backups_maintenance

    echo ""
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
    if [[ "$REQUIRE_FULL" -eq 1 && "$FULL_TIERS_SKIPPED" -gt 0 ]]; then
        fail "--full set but $FULL_TIERS_SKIPPED tier(s) were skipped"
    fi
    [[ "$FAIL" -eq 0 ]]
}

main "$@"