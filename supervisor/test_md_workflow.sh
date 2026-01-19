#!/usr/bin/env bash
# supervisor/test_md_workflow.sh
# End-to-end test for markdown-based task system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORLD_CMD="$PROJECT_DIR/world/run.sh"
SUPERVISOR_CMD="$SCRIPT_DIR/run.sh"
TASKS_DIR="$PROJECT_DIR/tasks"
WORLD_LOG="$PROJECT_DIR/world/world.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

echo "=== MD-Based Task System Test ==="
echo ""

# Setup
setup() {
    echo "Setting up test environment..."

    # Clean up any existing test tasks
    rm -f "$TASKS_DIR"/test-*.md

    # Clean up PID files
    rm -rf /tmp/supervisor/pids/test-*

    echo "✓ Setup complete"
    echo ""
}

# Test helpers
assert_file_exists() {
    local file="$1"
    local desc="$2"
    TESTS_RUN=$((TESTS_RUN + 1))

    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} PASS: $desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} FAIL: $desc"
        echo "  Expected file: $file"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_field_equals() {
    local file="$1"
    local field="$2"
    local expected="$3"
    local desc="$4"
    TESTS_RUN=$((TESTS_RUN + 1))

    if ! command -v yq >/dev/null 2>&1; then
        echo -e "${YELLOW}⊘${NC} SKIP: $desc (yq not installed)"
        return 0
    fi

    local actual
    actual=$(yq ".$field" "$file" 2>/dev/null || echo "")

    if [ "$actual" = "$expected" ]; then
        echo -e "${GREEN}✓${NC} PASS: $desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} FAIL: $desc"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local desc="$3"
    TESTS_RUN=$((TESTS_RUN + 1))

    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} PASS: $desc"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} FAIL: $desc"
        echo "  Expected pattern: $pattern"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test 1: Create task
test_create_task() {
    echo "Test 1: Creating task with world create --task"
    echo "---"

    "$WORLD_CMD" create --task "test-simple" "Simple test task" --need "tests pass"

    assert_file_exists "$TASKS_DIR/test-simple.md" "Task file created"
    assert_field_equals "$TASKS_DIR/test-simple.md" "id" "test-simple" "Task ID is correct"
    assert_field_equals "$TASKS_DIR/test-simple.md" "title" "Simple test task" "Task title is correct"
    assert_field_equals "$TASKS_DIR/test-simple.md" "status" "pending" "Initial status is pending"
    assert_field_equals "$TASKS_DIR/test-simple.md" "wait" "-" "Default wait is -"
    assert_field_equals "$TASKS_DIR/test-simple.md" "need" "tests pass" "Success criteria is set"

    echo ""
}

# Test 2: Verify/Cancel
test_verify_cancel() {
    echo "Test 2: Verify and cancel commands"
    echo "---"

    # Create a task for verification
    "$WORLD_CMD" create --task "test-verify" "Task to verify"

    # Verify it
    "$SUPERVISOR_CMD" verify "test-verify"
    assert_field_equals "$TASKS_DIR/test-verify.md" "status" "verified" "Status changed to verified"

    # Create a task for cancellation
    "$WORLD_CMD" create --task "test-cancel" "Task to cancel"

    # Cancel it
    "$SUPERVISOR_CMD" cancel "test-cancel"
    assert_field_equals "$TASKS_DIR/test-cancel.md" "status" "canceled" "Status changed to canceled"

    echo ""
}

# Test 3: MD file structure
test_md_structure() {
    echo "Test 3: MD file structure"
    echo "---"

    "$WORLD_CMD" create --task "test-structure" "Structure test" --wait "after:test-1" --need "all green"

    assert_contains "$TASKS_DIR/test-structure.md" "^---$" "Frontmatter delimiter present"
    assert_contains "$TASKS_DIR/test-structure.md" "# Structure test" "Title heading present"
    assert_contains "$TASKS_DIR/test-structure.md" "## Wait Condition" "Wait section present"
    assert_contains "$TASKS_DIR/test-structure.md" "## Execution Steps" "Steps section present"
    assert_contains "$TASKS_DIR/test-structure.md" "## Progress" "Progress section present"

    echo ""
}

# Test 4: List pending tasks
test_list_pending() {
    echo "Test 4: List pending tasks"
    echo "---"

    # Create multiple tasks
    "$WORLD_CMD" create --task "test-pending-1" "Pending task 1"
    "$WORLD_CMD" create --task "test-pending-2" "Pending task 2"

    # List should show both
    echo "Running: supervisor level1 list"
    "$SUPERVISOR_CMD" level1 list

    echo ""
}

# Test 5: Duplicate task detection
test_duplicate_detection() {
    echo "Test 5: Duplicate task detection"
    echo "---"

    # Ensure clean slate
    rm -f "$TASKS_DIR/test-duplicate.md"

    "$WORLD_CMD" create --task "test-duplicate" "First creation"

    # Try to create again (disable pipefail for this check since create will exit 1)
    set +e
    local output
    output=$("$WORLD_CMD" create --task "test-duplicate" "Second creation" 2>&1)
    set -e

    if echo "$output" | grep -q "already exists"; then
        echo -e "${GREEN}✓${NC} PASS: Duplicate task detected"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} FAIL: Duplicate task not detected"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    echo ""
}

# Run all tests
run_all_tests() {
    setup

    test_create_task
    test_verify_cancel
    test_md_structure
    test_list_pending
    test_duplicate_detection
}

# Summary
show_summary() {
    echo "=== Test Summary ==="
    echo "Total: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Failed: $TESTS_FAILED${NC}"
        exit 1
    else
        echo "Failed: 0"
        echo ""
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

# Run tests
run_all_tests
show_summary
