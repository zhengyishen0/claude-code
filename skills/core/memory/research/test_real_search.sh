#!/bin/bash
# Real-world comparison: NLP vs non-NLP search
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEARCH="$SCRIPT_DIR/search.sh"

echo "============================================================"
echo "MEMORY SEARCH: NLP vs NON-NLP COMPARISON"
echo "============================================================"

# Test queries that benefit from NLP
QUERIES=(
    "ran"                    # irregular verb -> should match "run"
    "specifications"         # plural -> should match "specification"
    "configured"             # past tense -> should match "configure"
    "went"                   # irregular verb -> should match "go"
)

echo ""
echo "SPEED TEST (3 runs each)"
echo "------------------------------------------------------------"

for mode in none hybrid; do
    total=0
    for i in 1 2 3; do
        start=$(python3 -c "import time; print(int(time.time()*1000))")
        /bin/bash "$SEARCH" "browser automation" --nlp $mode --sessions 3 >/dev/null 2>&1
        end=$(python3 -c "import time; print(int(time.time()*1000))")
        elapsed=$((end - start))
        total=$((total + elapsed))
    done
    avg=$((total / 3))
    echo "  --nlp $mode: ${avg}ms avg"
done

echo ""
echo "QUALITY TEST (keyword hit comparison)"
echo "------------------------------------------------------------"

for query in "${QUERIES[@]}"; do
    echo ""
    echo "Query: '$query'"

    # Run both modes and extract keyword stats
    none_result=$(/bin/bash "$SEARCH" "$query" --nlp none --sessions 3 --messages 1 2>&1 | grep -E "keywords|Found" | head -2)
    hybrid_result=$(/bin/bash "$SEARCH" "$query" --nlp hybrid --sessions 3 --messages 1 2>&1 | grep -E "keywords|Found" | head -2)

    echo "  none:   $none_result"
    echo "  hybrid: $hybrid_result"
done

echo ""
echo "============================================================"
echo "DETAILED EXAMPLE: 'ran' query"
echo "============================================================"

echo ""
echo "--- Without NLP (--nlp none) ---"
/bin/bash "$SEARCH" "ran" --nlp none --sessions 2 --messages 2 2>&1 | head -20

echo ""
echo "--- With NLP (--nlp hybrid) ---"
/bin/bash "$SEARCH" "ran" --nlp hybrid --sessions 2 --messages 2 2>&1 | head -20
