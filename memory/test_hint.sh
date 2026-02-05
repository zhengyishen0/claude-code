#!/bin/bash
# Comprehensive tests for memory hint command
# Run: ./test_hint.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "Memory Hint Comprehensive Test Suite"
echo "========================================"
echo ""

# Test counter
TESTS=0
PASS=0

run_test() {
    local name="$1"
    local query="$2"
    TESTS=$((TESTS + 1))

    echo "--- Test $TESTS: $name ---"
    echo "Query: $query"
    echo ""

    # Run hint and capture output
    local output
    local start_time=$(python3 -c "import time; print(time.time())")
    output=$("$SCRIPT_DIR/hint.sh" "$query" 2>&1) || true
    local end_time=$(python3 -c "import time; print(time.time())")
    local duration=$(python3 -c "print(f'{$end_time - $start_time:.2f}s')")

    if [ -n "$output" ]; then
        echo "$output"
        echo ""
        echo "Time: $duration"
        echo "Lines: $(echo "$output" | wc -l | tr -d ' ')"
        PASS=$((PASS + 1))
        echo "Result: PASS (found results)"
    else
        echo "(no results)"
        echo "Time: $duration"
        echo "Result: NO RESULTS"
    fi
    echo ""
}

echo "========================================"
echo "1. ENGLISH QUERIES"
echo "========================================"
echo ""

run_test "Simple English" "browser automation"
run_test "Technical terms" "OAuth authentication"
run_test "Action request" "help me debug the error"
run_test "Feature question" "how to configure calendar sync"
run_test "Specific tool" "chrome headless mode"
run_test "Error debugging" "TypeError undefined property"

echo "========================================"
echo "2. CHINESE QUERIES"
echo "========================================"
echo ""

run_test "Simple Chinese" "飞书审批"
run_test "Technical Chinese" "浏览器自动化"
run_test "Action Chinese" "帮我看看日历同步"
run_test "Question Chinese" "怎么配置机器人"
run_test "Error Chinese" "接口调用失败"

echo "========================================"
echo "3. MIXED EN/ZH QUERIES"
echo "========================================"
echo ""

run_test "Mixed simple" "feishu API 调用"
run_test "Mixed technical" "OAuth 认证配置"
run_test "Mixed action" "debug 飞书 bot"
run_test "Mixed error" "browser 报错了"
run_test "Brand + tech" "Claude 自动化"

echo "========================================"
echo "4. EDGE CASES"
echo "========================================"
echo ""

run_test "Single word EN" "authentication"
run_test "Single word ZH" "审批"
run_test "Very long query" "I need help debugging the browser automation workflow that integrates with feishu calendar and sends notifications"
run_test "Only stopwords" "I want to do this thing"
run_test "Numbers and code" "error 404 in api response"
run_test "Special chars" "user.authentication failed"

echo "========================================"
echo "5. DOMAIN-SPECIFIC QUERIES"
echo "========================================"
echo ""

run_test "Google services" "gmail calendar drive"
run_test "Feishu services" "飞书 bitable 多维表格"
run_test "Browser automation" "CDP chrome cookies profile"
run_test "Memory system" "session recall search"
run_test "Version control" "jj workspace commit"

echo "========================================"
echo "6. QUALITY ASSESSMENT"
echo "========================================"
echo ""

echo "Checking topic relevance for 'browser automation':"
echo ""
"$SCRIPT_DIR/hint.sh" "browser automation" | head -5 | while read line; do
    echo "$line"
    # Extract topics after →
    topics=$(echo "$line" | sed 's/.*→ //' | tr -d '\n')
    if [ -n "$topics" ]; then
        echo "  Topics: $topics"
        echo "  Assessment: Are these topics relevant to browser automation?"
    fi
    echo ""
done

echo "========================================"
echo "SUMMARY"
echo "========================================"
echo ""
echo "Total tests: $TESTS"
echo "With results: $PASS"
echo "No results: $((TESTS - PASS))"
echo ""

echo "========================================"
echo "TIMING TEST"
echo "========================================"
echo ""

echo "Running 5 queries to measure average time..."
total_time=0
for i in 1 2 3 4 5; do
    start=$(python3 -c "import time; print(time.time())")
    "$SCRIPT_DIR/hint.sh" "browser automation" > /dev/null 2>&1
    end=$(python3 -c "import time; print(time.time())")
    duration=$(python3 -c "print($end - $start)")
    total_time=$(python3 -c "print($total_time + $duration)")
    echo "  Run $i: ${duration}s"
done
avg=$(python3 -c "print(f'{$total_time / 5:.2f}')")
echo ""
echo "Average time: ${avg}s"
