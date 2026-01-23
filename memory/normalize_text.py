#!/usr/bin/env python3
"""Normalize text for indexing - converts words to base forms.

Used at index build time to pre-normalize text, enabling fast word-boundary
matching at query time without runtime NLP overhead.

Usage:
    echo "user was running specs" | python3 normalize_text.py
    # Output: user be run specification

    python3 normalize_text.py "ran specifications"
    # Output: run specification
"""

import sys
import re
from functools import lru_cache

# Try to import NLTK
try:
    from nltk.stem import WordNetLemmatizer
    from nltk.corpus import wordnet
    NLTK_AVAILABLE = True
except ImportError:
    NLTK_AVAILABLE = False

# Initialize lemmatizer once
_lemmatizer = None

def get_lemmatizer():
    global _lemmatizer
    if _lemmatizer is None and NLTK_AVAILABLE:
        _lemmatizer = WordNetLemmatizer()
    return _lemmatizer


@lru_cache(maxsize=50000)
def normalize_word(word):
    """Normalize a single word to its base form."""
    word = word.lower()

    if not NLTK_AVAILABLE:
        return word

    lem = get_lemmatizer()
    if lem is None:
        return word

    # Try as verb first (handles ran->run, running->run)
    lemma = lem.lemmatize(word, pos='v')
    if lemma != word:
        return lemma

    # Try as noun (handles specifications->specification)
    lemma = lem.lemmatize(word, pos='n')
    if lemma != word:
        return lemma

    # Try as adjective
    lemma = lem.lemmatize(word, pos='a')
    if lemma != word:
        return lemma

    return word


def normalize_text(text):
    """Normalize all words in text to base forms."""
    # Extract words, normalize, rejoin
    words = re.findall(r'\b\w+\b', text.lower())
    normalized = [normalize_word(w) for w in words]
    return ' '.join(normalized)


def main():
    # Check for command line argument
    if len(sys.argv) > 1:
        text = ' '.join(sys.argv[1:])
        print(normalize_text(text))
        return

    # Read from stdin (for piping)
    for line in sys.stdin:
        line = line.rstrip('\n')
        if line:
            print(normalize_text(line))


if __name__ == '__main__':
    main()
