#!/usr/bin/env python3
"""Comprehensive benchmark of all text normalization solutions.

Tests:
1. NLTK WordNet Lemmatizer (current)
2. spaCy (industrial-strength NLP)
3. Whoosh (full-text search with stemming)
4. PyStemmer (fast C-based stemming)
5. Tantivy (Rust-based full-text search)

Metrics:
- Accuracy: Correct handling of irregular forms
- Speed: Time to process N texts
- Memory: Approximate memory usage
"""

import time
import sys

# Test data
TEST_WORDS = [
    # (word, expected_lemma)
    ("running", "run"),
    ("runs", "run"),
    ("ran", "run"),         # Irregular verb - key test
    ("went", "go"),         # Irregular verb
    ("was", "be"),          # Irregular verb
    ("specifications", "specification"),
    ("specification", "specification"),
    ("configured", "configure"),
    ("better", "good"),     # Comparative adjective
    ("mice", "mouse"),      # Irregular plural
    ("children", "child"),  # Irregular plural
    ("feet", "foot"),       # Irregular plural
]

SAMPLE_TEXTS = [
    "The user was running multiple specifications for the configured system",
    "She ran quickly through the specifications and configured everything",
    "Running tests on specifications that were previously configured",
    "The children went to see the mice with their feet",
    "Better configurations are running on the new systems",
] * 200  # 1000 texts for speed test


def test_nltk():
    """Test NLTK WordNet Lemmatizer."""
    print("\n" + "=" * 60)
    print("1. NLTK WordNet Lemmatizer")
    print("=" * 60)

    try:
        from nltk.stem import WordNetLemmatizer
        from nltk.corpus import wordnet
        import nltk

        # Ensure data is downloaded
        try:
            wordnet.synsets('test')
        except LookupError:
            nltk.download('wordnet', quiet=True)
            nltk.download('omw-1.4', quiet=True)

        lem = WordNetLemmatizer()

        # Accuracy test
        correct = 0
        print("\nAccuracy:")
        for word, expected in TEST_WORDS:
            # Try verb, then noun
            result = lem.lemmatize(word, pos='v')
            if result == word:
                result = lem.lemmatize(word, pos='n')

            status = "✓" if result == expected else f"✗ got '{result}'"
            print(f"  {word:<15} → {result:<15} {status}")
            if result == expected:
                correct += 1

        accuracy = correct / len(TEST_WORDS) * 100
        print(f"\nAccuracy: {correct}/{len(TEST_WORDS)} ({accuracy:.1f}%)")

        # Speed test
        start = time.perf_counter()
        for text in SAMPLE_TEXTS:
            words = text.lower().split()
            normalized = []
            for w in words:
                lemma = lem.lemmatize(w, pos='v')
                if lemma == w:
                    lemma = lem.lemmatize(w, pos='n')
                normalized.append(lemma)
        elapsed = time.perf_counter() - start
        print(f"Speed: {len(SAMPLE_TEXTS)} texts in {elapsed*1000:.0f}ms ({elapsed/len(SAMPLE_TEXTS)*1000:.2f}ms/text)")

        return {"accuracy": accuracy, "time_ms": elapsed * 1000, "name": "NLTK"}

    except ImportError as e:
        print(f"  Not available: {e}")
        return None


def test_spacy():
    """Test spaCy lemmatizer."""
    print("\n" + "=" * 60)
    print("2. spaCy (en_core_web_sm)")
    print("=" * 60)

    try:
        import spacy

        # Load minimal pipeline
        nlp = spacy.load("en_core_web_sm", disable=["ner", "parser"])

        # Accuracy test
        correct = 0
        print("\nAccuracy:")
        for word, expected in TEST_WORDS:
            doc = nlp(word)
            result = doc[0].lemma_

            status = "✓" if result == expected else f"✗ got '{result}'"
            print(f"  {word:<15} → {result:<15} {status}")
            if result == expected:
                correct += 1

        accuracy = correct / len(TEST_WORDS) * 100
        print(f"\nAccuracy: {correct}/{len(TEST_WORDS)} ({accuracy:.1f}%)")

        # Speed test - using nlp.pipe for batch processing
        start = time.perf_counter()
        docs = list(nlp.pipe(SAMPLE_TEXTS, batch_size=50))
        for doc in docs:
            normalized = [token.lemma_ for token in doc]
        elapsed = time.perf_counter() - start
        print(f"Speed: {len(SAMPLE_TEXTS)} texts in {elapsed*1000:.0f}ms ({elapsed/len(SAMPLE_TEXTS)*1000:.2f}ms/text)")

        return {"accuracy": accuracy, "time_ms": elapsed * 1000, "name": "spaCy"}

    except Exception as e:
        print(f"  Error: {e}")
        return None


def test_spacy_batch_optimized():
    """Test spaCy with maximum optimization."""
    print("\n" + "=" * 60)
    print("2b. spaCy (optimized: blank + lemmatizer only)")
    print("=" * 60)

    try:
        import spacy

        # Create blank pipeline with just lemmatizer
        nlp = spacy.blank("en")
        nlp.add_pipe("lemmatizer", config={"mode": "lookup"})
        nlp.initialize()

        # Speed test
        start = time.perf_counter()
        docs = list(nlp.pipe(SAMPLE_TEXTS, batch_size=100, n_process=1))
        for doc in docs:
            normalized = [token.lemma_ for token in doc]
        elapsed = time.perf_counter() - start
        print(f"Speed: {len(SAMPLE_TEXTS)} texts in {elapsed*1000:.0f}ms ({elapsed/len(SAMPLE_TEXTS)*1000:.2f}ms/text)")

        return {"accuracy": None, "time_ms": elapsed * 1000, "name": "spaCy-opt"}

    except Exception as e:
        print(f"  Error: {e}")
        return None


def test_pystemmer():
    """Test PyStemmer (C-based Snowball)."""
    print("\n" + "=" * 60)
    print("3. PyStemmer (Snowball in C)")
    print("=" * 60)

    try:
        import Stemmer

        stemmer = Stemmer.Stemmer('english')

        # Accuracy test
        correct = 0
        print("\nAccuracy:")
        for word, expected in TEST_WORDS:
            result = stemmer.stemWord(word.lower())

            status = "✓" if result == expected else f"✗ got '{result}'"
            print(f"  {word:<15} → {result:<15} {status}")
            if result == expected:
                correct += 1

        accuracy = correct / len(TEST_WORDS) * 100
        print(f"\nAccuracy: {correct}/{len(TEST_WORDS)} ({accuracy:.1f}%)")

        # Speed test - batch stemming
        start = time.perf_counter()
        for text in SAMPLE_TEXTS:
            words = text.lower().split()
            normalized = stemmer.stemWords(words)
        elapsed = time.perf_counter() - start
        print(f"Speed: {len(SAMPLE_TEXTS)} texts in {elapsed*1000:.0f}ms ({elapsed/len(SAMPLE_TEXTS)*1000:.2f}ms/text)")

        return {"accuracy": accuracy, "time_ms": elapsed * 1000, "name": "PyStemmer"}

    except ImportError as e:
        print(f"  Not available: {e}")
        return None


def test_whoosh():
    """Test Whoosh stemming analyzer."""
    print("\n" + "=" * 60)
    print("4. Whoosh (StemmingAnalyzer)")
    print("=" * 60)

    try:
        from whoosh.analysis import StemmingAnalyzer

        analyzer = StemmingAnalyzer()

        # Accuracy test
        correct = 0
        print("\nAccuracy:")
        for word, expected in TEST_WORDS:
            tokens = list(analyzer(word.lower()))
            result = tokens[0].text if tokens else word

            status = "✓" if result == expected else f"✗ got '{result}'"
            print(f"  {word:<15} → {result:<15} {status}")
            if result == expected:
                correct += 1

        accuracy = correct / len(TEST_WORDS) * 100
        print(f"\nAccuracy: {correct}/{len(TEST_WORDS)} ({accuracy:.1f}%)")

        # Speed test
        start = time.perf_counter()
        for text in SAMPLE_TEXTS:
            tokens = list(analyzer(text.lower()))
            normalized = [t.text for t in tokens]
        elapsed = time.perf_counter() - start
        print(f"Speed: {len(SAMPLE_TEXTS)} texts in {elapsed*1000:.0f}ms ({elapsed/len(SAMPLE_TEXTS)*1000:.2f}ms/text)")

        return {"accuracy": accuracy, "time_ms": elapsed * 1000, "name": "Whoosh"}

    except ImportError as e:
        print(f"  Not available: {e}")
        return None


def test_tantivy():
    """Test Tantivy tokenizer."""
    print("\n" + "=" * 60)
    print("5. Tantivy (Rust-based)")
    print("=" * 60)

    try:
        import tantivy

        # Create schema and index
        schema_builder = tantivy.SchemaBuilder()
        schema_builder.add_text_field("content", stored=True)
        schema = schema_builder.build()

        index = tantivy.Index(schema)

        print("\n  Tantivy is a search engine, not a standalone lemmatizer.")
        print("  Testing indexing + search speed instead...")

        # Speed test - index all texts
        writer = index.writer()
        start = time.perf_counter()
        for text in SAMPLE_TEXTS:
            writer.add_document(tantivy.Document(content=text))
        writer.commit()
        index.reload()
        elapsed = time.perf_counter() - start

        print(f"Speed: Indexed {len(SAMPLE_TEXTS)} texts in {elapsed*1000:.0f}ms ({elapsed/len(SAMPLE_TEXTS)*1000:.2f}ms/text)")

        # Search test
        searcher = index.searcher()
        start = time.perf_counter()
        query = index.parse_query("running specifications", ["content"])
        results = searcher.search(query, 10)
        search_time = time.perf_counter() - start
        print(f"Search: 'running specifications' in {search_time*1000:.2f}ms, {results.count} hits")

        return {"accuracy": None, "time_ms": elapsed * 1000, "name": "Tantivy"}

    except Exception as e:
        print(f"  Error: {e}")
        return None


def main():
    print("=" * 60)
    print("TEXT NORMALIZATION BENCHMARK")
    print(f"Test data: {len(TEST_WORDS)} words, {len(SAMPLE_TEXTS)} texts")
    print("=" * 60)

    results = []

    # Run all tests
    r = test_nltk()
    if r: results.append(r)

    r = test_spacy()
    if r: results.append(r)

    r = test_spacy_batch_optimized()
    if r: results.append(r)

    r = test_pystemmer()
    if r: results.append(r)

    r = test_whoosh()
    if r: results.append(r)

    r = test_tantivy()
    if r: results.append(r)

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"\n{'Solution':<15} {'Accuracy':<12} {'Speed (1000 texts)':<20} {'Per-text'}")
    print("-" * 60)

    for r in sorted(results, key=lambda x: x['time_ms']):
        acc = f"{r['accuracy']:.1f}%" if r['accuracy'] is not None else "N/A"
        print(f"{r['name']:<15} {acc:<12} {r['time_ms']:.0f}ms{'':<14} {r['time_ms']/len(SAMPLE_TEXTS):.2f}ms")

    print("\n" + "=" * 60)
    print("RECOMMENDATIONS")
    print("=" * 60)
    print("""
┌─────────────────┬─────────────┬──────────────────────────────────┐
│ Use Case        │ Best Choice │ Why                              │
├─────────────────┼─────────────┼──────────────────────────────────┤
│ Speed-critical  │ PyStemmer   │ C-based, batch stemWords()       │
│ Accuracy-first  │ spaCy       │ Best irregular verb handling     │
│ Full-text search│ Tantivy     │ Rust-based, built-in stemming    │
│ Pure Python     │ Whoosh      │ No compilation, good stemming    │
│ Balanced        │ spaCy+pipe  │ Good accuracy + batch processing │
└─────────────────┴─────────────┴──────────────────────────────────┘
""")


if __name__ == '__main__':
    main()
