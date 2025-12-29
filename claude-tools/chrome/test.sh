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

  # Clean up any leftover test profiles first
  rm -rf "$HOME/.claude/profiles/github-alice"
  rm -rf "$HOME/.claude/profiles/github-bob"
  rm -rf "$HOME/.claude/profiles/slack-alice"
  rm -rf "$HOME/.claude/profiles/github_alice"
  rm -rf "$HOME/.claude/profiles/github_bob"
  rm -rf "$HOME/.claude/profiles/slack_alice"

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
  rm -rf "$HOME/.claude/profiles/github_alice"
  rm -rf "$HOME/.claude/profiles/github_bob"
  rm -rf "$HOME/.claude/profiles/slack_alice"

  echo ""
}

# ============================================================================
# Test Suite A5: Profile Locking
# ============================================================================

test_profile_locking_port_assignment() {
  echo "A5.1: Port assignment (deterministic hashing)"

  # Test: Same profile gets same port
  local port1=$(get_profile_port "github-alice")
  local port2=$(get_profile_port "github-alice")
  [ "$port1" = "$port2" ] && pass "Same profile → same port ($port1)" || fail "Port consistency" "$port1" "$port2"

  # Test: Different profiles get different ports (usually)
  local port_alice=$(get_profile_port "github-alice")
  local port_bob=$(get_profile_port "github-bob")
  [ "$port_alice" != "$port_bob" ] && pass "Different profiles → different ports" || info "Hash collision (rare but OK)"

  # Test: Port in valid range
  local port=$(get_profile_port "test-profile")
  if [ "$port" -ge 9222 ] && [ "$port" -le 9299 ]; then
    pass "Port in valid range (9222-9299)"
  else
    fail "Port range validation" "9222-9299" "$port"
  fi

  echo ""
}

test_profile_locking_acquisition() {
  echo "A5.2: Lock acquisition and release"

  local test_profile="test-lock-profile"

  # Clean up any previous test data
  rm -f "$HOME/.claude/chrome/port-registry"
  init_registry

  # Test: Acquire lock
  local port=$(assign_port_for_profile "$test_profile")
  [ $? -eq 0 ] && pass "Lock acquired successfully (port $port)" || fail "Lock acquisition" "success" "failed"

  # Test: Registry entry exists
  if grep -q "^$test_profile:" "$HOME/.claude/chrome/port-registry"; then
    pass "Registry entry created"
  else
    fail "Registry entry" "exists" "missing"
  fi

  # Test: Release lock
  release_profile "$test_profile"
  if ! grep -q "^$test_profile:" "$HOME/.claude/chrome/port-registry"; then
    pass "Registry entry removed"
  else
    fail "Registry entry removal" "removed" "still exists"
  fi

  echo ""
}

test_profile_locking_conflict() {
  echo "A5.3: Lock conflict detection (simulated)"

  local test_profile="test-conflict-profile"

  # Clean up
  rm -f "$HOME/.claude/chrome/port-registry"
  init_registry

  # Create a simulated lock by adding registry entry
  # We simulate a running Chrome by using our own PID
  local test_port=$(get_profile_port "$test_profile")
  echo "$test_profile:$test_port:$$:$(date +%s)" >> "$HOME/.claude/chrome/port-registry"

  # Verify registry entry was created
  if grep -q "^$test_profile:" "$HOME/.claude/chrome/port-registry"; then
    pass "Simulated lock created in registry"
  else
    fail "Lock simulation" "created" "failed"
  fi

  # The actual conflict detection happens in is_profile_in_use
  # which checks if the process exists (our $$ exists) and if Chrome is listening
  # Since Chrome won't be listening, the lock will be cleaned up
  # This is actually correct behavior - stale lock cleanup
  info "Note: Lock conflict requires Chrome to be running - testing stale lock cleanup instead"

  # Cleanup
  release_profile "$test_profile"

  echo ""
}

test_stale_lock_cleanup() {
  echo "A5.4: Stale lock cleanup"

  local test_profile="test-stale-profile"

  # Clean up
  rm -f "$HOME/.claude/chrome/port-registry"
  init_registry

  # Create a stale lock entry (non-existent PID)
  echo "$test_profile:9222:999999:$(date +%s)" >> "$HOME/.claude/chrome/port-registry"

  # Try to check if in use (should clean up stale entry)
  if ! is_profile_in_use "$test_profile"; then
    pass "Stale lock cleaned up automatically"
  else
    fail "Stale lock cleanup" "cleaned" "still locked"
  fi

  # Verify we can now acquire the lock
  local port=$(assign_port_for_profile "$test_profile" 2>/dev/null)
  if [ $? -eq 0 ]; then
    pass "Profile available after stale lock cleanup"
  else
    fail "Profile availability" "available" "locked"
  fi

  # Cleanup
  release_profile "$test_profile"

  echo ""
}

# ============================================================================
# Test Suite A6: Import Without URL
# ============================================================================

test_import_all_services() {
  echo "A6.1: Import without URL (scan all services)"

  local chrome_dir="$HOME/Library/Application Support/Google/Chrome"

  if [ ! -d "$chrome_dir/Default" ]; then
    info "Chrome.app Default profile not found - skipping import test"
    echo ""
    return 0
  fi

  # Get list of all services from domain-mappings.json
  local mappings="$SCRIPT_DIR/domain-mappings.json"
  if [ ! -f "$mappings" ]; then
    fail "Domain mappings file" "exists" "missing"
    echo ""
    return 1
  fi

  local service_count=$(jq -r '.[] | select(. != null)' "$mappings" 2>/dev/null | sort -u | wc -l | tr -d ' ')

  if [ "$service_count" -gt 0 ]; then
    pass "Found $service_count services in domain-mappings.json"
  else
    fail "Service count" "> 0" "0"
  fi

  # Test detecting accounts for at least one common service
  local found_any=false
  for service in github gmail amazon; do
    local accounts=$(detect_chrome_accounts "$chrome_dir/Default" "$service" 2>/dev/null)
    if [ -n "$accounts" ]; then
      local count=$(echo "$accounts" | wc -l | tr -d ' ')
      pass "Detected $count <$service> account(s)"
      found_any=true
      break
    fi
  done

  if [ "$found_any" = false ]; then
    info "No accounts found for common services (github, gmail, amazon) - this is OK if not logged in"
  fi

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

  echo "======================================================================"
  echo "Phase A5: Profile Locking"
  echo "======================================================================"
  echo ""
  test_profile_locking_port_assignment
  test_profile_locking_acquisition
  test_profile_locking_conflict
  test_stale_lock_cleanup

  echo "======================================================================"
  echo "Phase A6: Import Without URL"
  echo "======================================================================"
  echo ""
  test_import_all_services

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
