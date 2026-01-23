# Memory Search NLP Research

Benchmarks and analysis for text normalization in memory search.

## Problem

Word boundary matching misses morphological variations:
- "specification" vs "specifications" (plurals)
- "run" vs "runs" vs "running" vs "ran" (verb forms)

## Solutions Tested

| Solution | Accuracy | Speed (1000 texts) | Handles Irregulars |
|----------|----------|-------------------|-------------------|
| **NLTK WordNet** | **91.7%** | **26ms** | ✓ ran→run, mice→mouse |
| spaCy | 91.7% | 588ms | ✓ ran→run, mice→mouse |
| PyStemmer | 16.7% | 1ms | ✗ ran→ran |
| Whoosh | 8.3% | 10ms | ✗ ran→ran |
| Tantivy | N/A | 9ms | ✗ (search engine) |

## Conclusion

**NLTK is optimal** - best accuracy/speed balance. spaCy is 22x slower for same accuracy.

## Files

- `benchmark.py` - Tests normalizer modes (porter, snowball, lemma, hybrid)
- `benchmark_all.py` - Compares all solutions (NLTK, spaCy, PyStemmer, Whoosh, Tantivy)

## Run Benchmarks

```bash
cd memory/research
python3 benchmark.py          # Test our normalizer
python3 benchmark_all.py      # Compare all solutions
```

## Implementation

The normalizer is in `../normalizer.py` with modes:
- `none` - Exact matching (fastest)
- `porter` - Porter stemmer (fast, misses irregulars)
- `snowball` - Snowball stemmer (balanced)
- `lemma` - WordNet lemmatizer (accurate)
- `hybrid` - Lemma + stemming fallback (best accuracy)

## Usage

```bash
# Default (exact matching)
memory search "browser automation"

# With NLP normalization
memory search "ran specifications" --nlp hybrid
```
