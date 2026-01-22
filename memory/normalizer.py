#!/usr/bin/env python3
"""Text normalization for memory search using stemming and lemmatization.

Supports three normalization strategies:
- porter: Porter stemmer (fast, aggressive)
- snowball: Snowball stemmer (balanced, multi-language capable)
- lemma: WordNet lemmatizer (accurate, handles irregular forms)
- hybrid: Combines lemmatization + stemming fallback (best accuracy)

Usage:
    from normalizer import TextNormalizer

    norm = TextNormalizer(mode='hybrid')
    norm.normalize("running specifications")  # -> "run specification"
    norm.normalize_query("ran specs")         # -> ["run", "spec", "ran", "specs"]
"""

import re
import sys
from functools import lru_cache

# Try to import NLTK components
try:
    from nltk.stem import PorterStemmer, SnowballStemmer, WordNetLemmatizer
    from nltk.corpus import wordnet
    NLTK_AVAILABLE = True
except ImportError:
    NLTK_AVAILABLE = False

# Try faster PyStemmer if available
try:
    import Stemmer as PyStemmer
    PYSTEMMER_AVAILABLE = True
except ImportError:
    PYSTEMMER_AVAILABLE = False


class TextNormalizer:
    """Normalize text using stemming and/or lemmatization."""

    def __init__(self, mode='hybrid'):
        """
        Initialize normalizer with specified mode.

        Args:
            mode: 'porter', 'snowball', 'lemma', 'hybrid', or 'none'
        """
        self.mode = mode
        self._porter = None
        self._snowball = None
        self._lemmatizer = None
        self._pystemmer = None

        if mode == 'none':
            return

        if not NLTK_AVAILABLE and mode != 'none':
            print("Warning: NLTK not available, falling back to no normalization", file=sys.stderr)
            self.mode = 'none'
            return

        # Initialize stemmers based on mode
        if mode in ('porter', 'hybrid'):
            self._porter = PorterStemmer()

        if mode in ('snowball', 'hybrid'):
            if PYSTEMMER_AVAILABLE:
                self._pystemmer = PyStemmer.Stemmer('english')
            else:
                self._snowball = SnowballStemmer('english')

        if mode in ('lemma', 'hybrid'):
            self._lemmatizer = WordNetLemmatizer()

    @lru_cache(maxsize=10000)
    def _stem_porter(self, word):
        """Apply Porter stemmer."""
        return self._porter.stem(word)

    @lru_cache(maxsize=10000)
    def _stem_snowball(self, word):
        """Apply Snowball stemmer."""
        if self._pystemmer:
            return self._pystemmer.stemWord(word)
        return self._snowball.stem(word)

    @lru_cache(maxsize=10000)
    def _is_known_word(self, word):
        """Check if word exists in WordNet dictionary."""
        if not NLTK_AVAILABLE:
            return False
        return bool(wordnet.synsets(word))

    @lru_cache(maxsize=10000)
    def _lemmatize(self, word):
        """Apply WordNet lemmatizer with POS guessing."""
        if not self._lemmatizer:
            return word

        # Try as verb first (handles ran->run, running->run)
        lemma = self._lemmatizer.lemmatize(word, pos='v')
        if lemma != word:
            return lemma

        # Try as noun (handles specifications->specification)
        lemma = self._lemmatizer.lemmatize(word, pos='n')
        if lemma != word:
            return lemma

        # Try as adjective
        lemma = self._lemmatizer.lemmatize(word, pos='a')
        if lemma != word:
            return lemma

        return word

    @lru_cache(maxsize=10000)
    def normalize_word(self, word):
        """
        Normalize a single word based on mode.

        Args:
            word: Word to normalize (lowercase)

        Returns:
            Normalized word
        """
        word = word.lower()

        if self.mode == 'none':
            return word

        if self.mode == 'porter':
            return self._stem_porter(word)

        if self.mode == 'snowball':
            return self._stem_snowball(word)

        if self.mode == 'lemma':
            return self._lemmatize(word)

        if self.mode == 'hybrid':
            # First try lemmatization (accurate for irregular forms)
            lemma = self._lemmatize(word)
            if lemma != word:
                return lemma

            # Check if word is a known dictionary word (valid lemma)
            # If so, don't stem it further to avoid over-stemming
            # e.g., "specification" should stay as "specification", not become "specif"
            if self._is_known_word(word):
                return word

            # Fall back to snowball stemming (handles regular suffixes)
            return self._stem_snowball(word)

        return word

    def normalize(self, text):
        """
        Normalize all words in text.

        Args:
            text: Text to normalize

        Returns:
            Normalized text with original word order
        """
        if self.mode == 'none':
            return text.lower()

        # Split on non-word characters, normalize, rejoin
        words = re.findall(r'\b\w+\b', text.lower())
        normalized = [self.normalize_word(w) for w in words]
        return ' '.join(normalized)

    def normalize_query(self, query):
        """
        Normalize query and return both original and normalized forms.

        This expands the query to match both exact and normalized forms,
        improving recall without losing precision.

        Args:
            query: Search query string

        Returns:
            List of unique terms (original + normalized)
        """
        words = re.findall(r'\b\w+\b', query.lower())
        terms = set()

        for word in words:
            terms.add(word)  # Keep original
            normalized = self.normalize_word(word)
            if normalized != word:
                terms.add(normalized)

        return list(terms)

    def get_variations(self, word):
        """
        Get all normalized variations of a word.

        Useful for building search patterns that match all forms.

        Args:
            word: Word to get variations for

        Returns:
            Set of variations including original
        """
        word = word.lower()
        variations = {word}

        if self.mode == 'none':
            return variations

        # Add lemmatized form
        if self._lemmatizer:
            for pos in ['v', 'n', 'a', 'r']:
                lemma = self._lemmatizer.lemmatize(word, pos=pos)
                if lemma:
                    variations.add(lemma)

        # Add stemmed forms
        if self._porter:
            variations.add(self._stem_porter(word))

        if self._snowball or self._pystemmer:
            variations.add(self._stem_snowball(word))

        return variations


def ensure_nltk_data():
    """Download required NLTK data if not present."""
    if not NLTK_AVAILABLE:
        print("NLTK not installed. Install with: pip install nltk", file=sys.stderr)
        return False

    import nltk
    required = ['wordnet', 'omw-1.4']

    for resource in required:
        try:
            nltk.data.find(f'corpora/{resource}')
        except LookupError:
            print(f"Downloading NLTK resource: {resource}", file=sys.stderr)
            nltk.download(resource, quiet=True)

    return True


# Quick test
if __name__ == '__main__':
    ensure_nltk_data()

    test_words = [
        ('running', 'run'),
        ('runs', 'run'),
        ('ran', 'run'),
        ('specifications', 'specification'),
        ('specification', 'specification'),
        ('specified', 'specify'),
    ]

    print("Testing normalizers:\n")
    print(f"{'Word':<20} {'Porter':<15} {'Snowball':<15} {'Lemma':<15} {'Hybrid':<15}")
    print("-" * 80)

    normalizers = {
        'porter': TextNormalizer('porter'),
        'snowball': TextNormalizer('snowball'),
        'lemma': TextNormalizer('lemma'),
        'hybrid': TextNormalizer('hybrid'),
    }

    for word, expected in test_words:
        row = f"{word:<20}"
        for name, norm in normalizers.items():
            result = norm.normalize_word(word)
            marker = "✓" if result == expected else ""
            row += f"{result:<15}"
        print(row)

    print("\n\nQuery expansion test:")
    hybrid = TextNormalizer('hybrid')
    queries = ["running specifications", "ran specs", "configure configured"]
    for q in queries:
        expanded = hybrid.normalize_query(q)
        print(f"  '{q}' -> {expanded}")
