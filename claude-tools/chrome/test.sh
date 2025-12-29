#!/bin/bash
# Automated tests for Chrome profile system
# Tests pure functions and file operations

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="/tmp/claude-chrome-test-$$"
PASSED=0
FAILED=0

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Source the functions we need to test
source_functions() {
  # Extract just the helper functions from run.sh
  # We'll source them in a controlled way
  source <(grep -A 500 "^# ============================================================================" "$SCRIPT_DIR/run.sh" | grep -B 500 "^# ============================================================================" | head -n -1)
}

# Test result tracking
pass() {
  echo -e "${GREEN}✓ PASS${NC}: $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo -e "${RED}✗ FAIL${NC}: $1"
  echo -e "  ${RED}Expected${NC}: $2"
  echo -e "  ${RED}Got${NC}: $3"
  FAILED=$((FAILED + 1))
}

info() {
  echo -e "${YELLOW}ℹ INFO${NC}: $1"
}

# Setup test environment
setup() {
  mkdir -p "$TEST_DIR"
  info "Test directory: $TEST_DIR"
  echo ""
}

# Cleanup test environment
cleanup() {
  rm -rf "$TEST_DIR"
}

# ============================================================================
# Test Suite A1: Pure Functions
# ============================================================================

test_normalize_profile_name() {
  echo "A1.1: normalize_profile_name()"

  # Test: Lowercase conversion
  result=$(normalize_profile_name "GitHub-Alice")
  [ "$result" = "github_alice" ] && pass "Lowercase + dash to underscore" || fail "Lowercase conversion" "github_alice" "$result"

  # Test: Email normalization
  result=$(normalize_profile_name "alice@gmail.com")
  [ "$result" = "alice_gmail_com" ] && pass "Email normalization" || fail "Email normalization" "alice_gmail_com" "$result"

  # Test: Special char removal
  result=$(normalize_profile_name "user!@#name")
  [ "$result" = "user_name" ] && pass "Special char removal" || fail "Special char removal" "user_name" "$result"

  # Test: Multiple spaces/dashes
  result=$(normalize_profile_name "my--profile  name")
  [ "$result" = "my_profile_name" ] && pass "Multiple separators" || fail "Multiple separators" "my_profile_name" "$result"

  echo ""
}

test_get_service_name() {
  echo "A1.2: get_service_name()"

  # Test: Domain mapping (requires domain-mappings.json)
  result=$(get_service_name "https://mail.google.com")
  [ "$result" = "gmail" ] && pass "Domain mapping: mail.google.com → gmail" || fail "Domain mapping" "gmail" "$result"

  result=$(get_service_name "https://github.com/user/repo")
  [ "$result" = "github" ] && pass "Domain mapping: github.com → github" || fail "Domain mapping" "github" "$result"

  result=$(get_service_name "https://amazon.co.uk/products")
  [ "$result" = "amazon" ] && pass "Domain mapping: amazon.co.uk → amazon" || fail "Domain mapping" "amazon" "$result"

  # Test: Fallback TLD stripping
  result=$(get_service_name "https://example.com")
  [ "$result" = "example" ] && pass "TLD stripping fallback: example.com → example" || fail "TLD stripping" "example" "$result"

  result=$(get_service_name "https://www.mysite.org")
  [ "$result" = "mysite" ] && pass "www + TLD stripping: www.mysite.org → mysite" || fail "www stripping" "mysite" "$result"

  echo ""
}

test_format_time_ago() {
  echo "A1.3: format_time_ago()"

  # Test: Just now
  result=$(format_time_ago 30)
  [ "$result" = "just now" ] && pass "< 60s → just now" || fail "Just now" "just now" "$result"

  # Test: Minutes
  result=$(format_time_ago 180)
  [ "$result" = "3m ago" ] && pass "180s → 3m ago" || fail "Minutes" "3m ago" "$result"

  # Test: Hours
  result=$(format_time_ago 7200)
  [ "$result" = "2h ago" ] && pass "7200s → 2h ago" || fail "Hours" "2h ago" "$result"

  # Test: Days
  result=$(format_time_ago 172800)
  [ "$result" = "2d ago" ] && pass "172800s → 2d ago" || fail "Days" "2d ago" "$result"

  echo ""
}

test_expand_profile_path() {
  echo "A1.4: expand_profile_path()"

  # Test: Relative path (should expand to ~/.claude/profiles/)
  result=$(expand_profile_path "test-profile")
  expected="$HOME/.claude/profiles/test_profile"
  [ "$result" = "$expected" ] && pass "Relative path expansion" || fail "Relative path" "$expected" "$result"

  # Test: Absolute path (should stay as-is)
  result=$(expand_profile_path "/tmp/my-profile")
  [ "$result" = "/tmp/my-profile" ] && pass "Absolute path unchanged" || fail "Absolute path" "/tmp/my-profile" "$result"

  echo ""
}

# ============================================================================
# Test Suite A2: Metadata Operations
# ============================================================================

test_metadata_write_read() {
  echo "A2.1: write_profile_metadata() + read_profile_metadata()"

  local test_profile="$TEST_DIR/test-profile"
  mkdir -p "$test_profile"

  # Write metadata
  write_profile_metadata "$test_profile" "github" "alice" "manual" "manual" ""

  [ -f "$test_profile/.profile-meta.json" ] && pass "Metadata file created" || fail "Metadata file creation" "file exists" "file missing"

  # Read metadata fields
  local service=$(read_profile_metadata "$test_profile" "service")
  [ "$service" = "github" ] && pass "Read service field" || fail "Service field" "github" "$service"

  local account=$(read_profile_metadata "$test_profile" "account")
  [ "$account" = "alice" ] && pass "Read account field" || fail "Account field" "alice" "$account"

  local display=$(read_profile_metadata "$test_profile" "display")
  [ "$display" = "<github> alice (manual)" ] && pass "Display format correct" || fail "Display format" "<github> alice (manual)" "$display"

  local status=$(read_profile_metadata "$test_profile" "status")
  [ "$status" = "enabled" ] && pass "Default status is enabled" || fail "Default status" "enabled" "$status"

  echo ""
}

test_metadata_update() {
  echo "A2.2: update_profile_metadata()"

  local test_profile="$TEST_DIR/test-profile-update"
  mkdir -p "$test_profile"

  # Write initial metadata
  write_profile_metadata "$test_profile" "slack" "bob" "manual" "manual" ""

  # Update status field
  update_profile_metadata "$test_profile" "status" "disabled"

  local status=$(read_profile_metadata "$test_profile" "status")
  [ "$status" = "disabled" ] && pass "Update status field" || fail "Update status" "disabled" "$status"

  # Verify other fields unchanged
  local account=$(read_profile_metadata "$test_profile" "account")
  [ "$account" = "bob" ] && pass "Other fields unchanged" || fail "Field preservation" "bob" "$account"

  echo ""
}

# ============================================================================
# Test Suite A3: Chrome.app Integration (If Available)
# ============================================================================

test_chrome_app_discovery() {
  echo "A3.1: get_chrome_app_profiles()"

  local chrome_dir="$HOME/Library/Application Support/Google/Chrome"

  if [ ! -d "$chrome_dir" ]; then
    info "Chrome.app not installed - skipping Chrome.app tests"
    echo ""
    return 0
  fi

  local profiles=$(get_chrome_app_profiles)

  if [ -n "$profiles" ]; then
    local count=$(echo "$profiles" | wc -l | tr -d ' ')
    pass "Found $count Chrome.app profile(s)"
    echo "$profiles" | while read -r profile; do
      info "  - $(basename "$profile")"
    done
  else
    fail "Chrome.app profile discovery" "at least one profile" "none found"
  fi

  echo ""
}

test_detect_chrome_accounts() {
  echo "A3.2: detect_chrome_accounts()"

  local chrome_dir="$HOME/Library/Application Support/Google/Chrome"

  if [ ! -d "$chrome_dir/Default" ]; then
    info "Chrome.app Default profile not found - skipping account detection test"
    echo ""
    return 0
  fi

  # Test with GitHub (most developers have this)
  local accounts=$(detect_chrome_accounts "$chrome_dir/Default" "github")

  if [ -n "$accounts" ]; then
    pass "Detected GitHub accounts in Default profile"
    echo "$accounts" | while IFS='|' read -r domain seconds_ago visit_count; do
      local time_str=$(format_time_ago "$seconds_ago")
      info "  - $domain ($time_str, $visit_count visits)"
    done
  else
    info "No GitHub accounts found in Default profile (this is OK if not logged in)"
  fi

  echo ""
}

# ============================================================================
# Test Suite A4: Fuzzy Matching
# ============================================================================

test_fuzzy_match_profile() {
  echo "A4.1: fuzzy_match_profile()"

  # Create test profiles
  mkdir -p "$HOME/.claude/profiles/github-alice"
  mkdir -p "$HOME/.claude/profiles/github-bob"
  mkdir -p "$HOME/.claude/profiles/slack-alice"

  # Test: Exact substring match
  local matches=$(fuzzy_match_profile "github")
  local count=$(echo "$matches" | wc -l | tr -d ' ')
  [ "$count" = "2" ] && pass "Found 2 matches for 'github'" || fail "Fuzzy match count" "2" "$count"

  # Test: Partial match
  matches=$(fuzzy_match_profile "alice")
  count=$(echo "$matches" | wc -l | tr -d ' ')
  [ "$count" = "2" ] && pass "Found 2 matches for 'alice'" || fail "Fuzzy match count" "2" "$count"

  # Test: Case insensitive
  matches=$(fuzzy_match_profile "GITHUB")
  count=$(echo "$matches" | wc -l | tr -d ' ')
  [ "$count" = "2" ] && pass "Case insensitive matching" || fail "Case insensitive" "2" "$count"

  # Test: No match
  matches=$(fuzzy_match_profile "nonexistent" || true)
  [ -z "$matches" ] && pass "No match returns empty" || fail "No match" "empty" "$matches"

  # Cleanup test profiles
  rm -rf "$HOME/.claude/profiles/github-alice"
  rm -rf "$HOME/.claude/profiles/github-bob"
  rm -rf "$HOME/.claude/profiles/slack-alice"

  echo ""
}

# ============================================================================
# Main Test Runner
# ============================================================================

main() {
  echo "======================================================================"
  echo "Chrome Profile System - Automated Test Suite"
  echo "======================================================================"
  echo ""

  setup

  # Source functions from run.sh
  info "Loading functions from run.sh..."
  TOOL_NAME="chrome"
  source "$SCRIPT_DIR/run.sh"
  echo ""

  echo "======================================================================"
  echo "Phase A1: Pure Function Tests"
  echo "======================================================================"
  echo ""
  test_normalize_profile_name
  test_get_service_name
  test_format_time_ago
  test_expand_profile_path

  echo "======================================================================"
  echo "Phase A2: Metadata Operations"
  echo "======================================================================"
  echo ""
  test_metadata_write_read
  test_metadata_update

  echo "======================================================================"
  echo "Phase A3: Chrome.app Integration"
  echo "======================================================================"
  echo ""
  test_chrome_app_discovery
  test_detect_chrome_accounts

  echo "======================================================================"
  echo "Phase A4: Fuzzy Matching"
  echo "======================================================================"
  echo ""
  test_fuzzy_match_profile

  cleanup

  echo "======================================================================"
  echo "Test Summary"
  echo "======================================================================"
  echo -e "${GREEN}PASSED${NC}: $PASSED"
  echo -e "${RED}FAILED${NC}: $FAILED"
  echo ""

  if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    echo "Ready for Phase B (Human-Required Interactive Tests)"
    exit 0
  else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
  fi
}

main "$@"
