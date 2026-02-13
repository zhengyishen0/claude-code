#!/usr/bin/env python3
"""Benchmark memory search with different NLP modes.

Tests accuracy and speed of:
- none: Exact matching (baseline)
- porter: Porter stemmer
- snowball: Snowball stemmer
- lemma: WordNet lemmatizer
- hybrid: Lemmatization + stemming fallback

Usage:
    python3 benchmark.py [--index path/to/memory-index.tsv]
"""

import sys
import os
import time
import subprocess
from pathlib import Path

# Add current directory for imports
sys.path.insert(0, str(Path(__file__).parent))

try:
    from normalizer import TextNormalizer, ensure_nltk_data
    NORMALIZER_AVAILABLE = True
except ImportError:
    NORMALIZER_AVAILABLE = False
    print("Warning: normalizer module not available")

# Test cases: (query, expected_matches_description)
# These test morphological variations that exact matching would miss
TEST_CASES = [
    # Plurals
    ("specification", "should also match 'specifications'"),
    ("specifications", "should also match 'specification'"),

    # Verb forms - regular
    ("running", "should also match 'run', 'runs'"),
    ("configured", "should also match 'configure', 'configuring'"),

    # Verb forms - irregular (lemmatizer strength)
    ("ran", "should match 'run' - irregular verb"),
    ("went", "should match 'go' - irregular verb"),

    # Mixed
    ("run specification", "should match 'running specifications'"),
]


def test_normalizer_accuracy():
    """Test normalizer accuracy on known word pairs."""
    if not NORMALIZER_AVAILABLE:
        print("Normalizer not available, skipping accuracy test")
        return

    ensure_nltk_data()

    # Ground truth: (word, expected_normalized_form)
    ground_truth = [
        # Plurals
        ("specifications", "specification"),
        ("specification", "specification"),
        ("files", "file"),
        ("indices", "index"),

        # Regular verbs
        ("running", "run"),
        ("runs", "run"),
        ("configured", "configure"),
        ("configuring", "configure"),

        # Irregular verbs
        ("ran", "run"),
        ("went", "go"),
        ("was", "be"),
        ("were", "be"),
        ("had", "have"),
        ("saw", "see"),

        # Adjectives
        ("better", "better"),  # comparative - lemmatizer may not handle
        ("best", "best"),      # superlative
    ]

    modes = ['porter', 'snowball', 'lemma', 'hybrid']
    results = {mode: {'correct': 0, 'total': len(ground_truth)} for mode in modes}

    print("\n" + "=" * 80)
    print("ACCURACY TEST: Word Normalization")
    print("=" * 80)
    print(f"\n{'Word':<20} {'Expected':<15} {'Porter':<12} {'Snowball':<12} {'Lemma':<12} {'Hybrid':<12}")
    print("-" * 80)

    for word, expected in ground_truth:
        row = f"{word:<20} {expected:<15}"

        for mode in modes:
            normalizer = TextNormalizer(mode)
            result = normalizer.normalize_word(word)

            if result == expected:
                results[mode]['correct'] += 1
                marker = "✓"
            else:
                marker = ""

            row += f" {result:<10}{marker:<2}"

        print(row)

    print("-" * 80)
    print("\nAccuracy Summary:")
    for mode in modes:
        accuracy = results[mode]['correct'] / results[mode]['total'] * 100
        print(f"  {mode:<10}: {results[mode]['correct']}/{results[mode]['total']} ({accuracy:.1f}%)")

    return results


def test_search_speed(index_file, iterations=3):
    """Benchmark search speed across different NLP modes."""
    if not os.path.exists(index_file):
        print(f"Index file not found: {index_file}")
        return

    script_dir = Path(__file__).parent
    search_script = script_dir / "search.sh"

    if not search_script.exists():
        print(f"Search script not found: {search_script}")
        return

    modes = ['none', 'porter', 'snowball', 'lemma', 'hybrid']
    queries = ["browser automation", "running specification", "configure install"]

    print("\n" + "=" * 80)
    print("SPEED TEST: Search Performance")
    print("=" * 80)

    results = {}

    for mode in modes:
        times = []

        for query in queries:
            for _ in range(iterations):
                start = time.perf_counter()

                try:
                    subprocess.run(
                        [str(search_script), query, "--nlp", mode, "--sessions", "5"],
                        capture_output=True,
                        text=True,
                        timeout=30,
                        cwd=str(script_dir)
                    )
                except subprocess.TimeoutExpired:
                    times.append(30.0)
                    continue
                except Exception as e:
                    print(f"  Error with {mode}: {e}")
                    continue

                elapsed = time.perf_counter() - start
                times.append(elapsed)

        if times:
            avg_time = sum(times) / len(times)
            results[mode] = avg_time
            print(f"  {mode:<10}: {avg_time*1000:.1f}ms avg ({len(times)} runs)")

    # Calculate slowdown relative to baseline
    if 'none' in results:
        baseline = results['none']
        print("\nSlowdown vs baseline (none):")
        for mode, time_val in results.items():
            if mode != 'none':
                slowdown = time_val / baseline
                print(f"  {mode:<10}: {slowdown:.2f}x")

    return results


def test_recall_improvement(index_file):
    """Test if NLP modes find more relevant results."""
    if not os.path.exists(index_file):
        print(f"Index file not found: {index_file}")
        return

    script_dir = Path(__file__).parent
    search_script = script_dir / "search.sh"

    # Queries that should benefit from NLP
    test_queries = [
        ("ran", "Test irregular verb 'ran' -> 'run'"),
        ("specifications", "Test plural matching"),
        ("configured", "Test past tense matching"),
    ]

    modes = ['none', 'hybrid']

    print("\n" + "=" * 80)
    print("RECALL TEST: Finding More Matches")
    print("=" * 80)

    for query, description in test_queries:
        print(f"\nQuery: '{query}' ({description})")

        for mode in modes:
            try:
                result = subprocess.run(
                    [str(search_script), query, "--nlp", mode, "--sessions", "3", "--messages", "2"],
                    capture_output=True,
                    text=True,
                    timeout=30,
                    cwd=str(script_dir)
                )

                # Count matches from output
                output = result.stdout
                match_lines = [l for l in output.split('\n') if 'matches' in l.lower() or 'keywords' in l.lower()]

                print(f"  {mode:<10}:")
                for line in match_lines[:3]:
                    print(f"    {line.strip()}")

            except Exception as e:
                print(f"  {mode:<10}: Error - {e}")


def main():
    script_dir = Path(__file__).parent
    default_index = script_dir / "data" / "memory-index.tsv"

    index_file = sys.argv[1] if len(sys.argv) > 1 else str(default_index)

    print("Memory Search NLP Benchmark")
    print("=" * 80)

    # Test 1: Normalizer accuracy
    test_normalizer_accuracy()

    # Test 2: Search speed
    test_search_speed(index_file)

    # Test 3: Recall improvement
    test_recall_improvement(index_file)

    print("\n" + "=" * 80)
    print("RECOMMENDATIONS")
    print("=" * 80)
    print("""
Based on typical results:

1. For SPEED-CRITICAL use cases:
   - Use 'none' (exact matching) - fastest
   - Use 'snowball' - good balance of speed and coverage

2. For ACCURACY-CRITICAL use cases:
   - Use 'hybrid' - best handling of irregular forms
   - Use 'lemma' - if you need dictionary-valid words

3. For GENERAL use:
   - 'hybrid' is recommended as default
   - Falls back gracefully if NLTK not available
""")


if __name__ == '__main__':
    main()
