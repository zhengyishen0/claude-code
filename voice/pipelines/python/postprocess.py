#!/usr/bin/env python3
"""
Post-processing for transcription output.

Features:
1. Custom words correction - fix commonly misheard words
2. Filler word removal - remove "um", "uh", "er", etc.
3. Duplicate word removal - remove stuttering like "I I went"
4. Punctuation cleanup - fix spacing around punctuation

Usage:
    from voice.postprocess import TranscriptProcessor

    processor = TranscriptProcessor()
    processor.add_custom_words(["Claude", "CoreML", "iPhone"])

    text = "I use clod code and um I really like it it"
    clean = processor.process(text)
    # Result: "I use Claude code and I really like it"
"""

import re
from dataclasses import dataclass, field
from typing import List, Set, Optional, Tuple
from difflib import SequenceMatcher


@dataclass
class ProcessorConfig:
    """Configuration for transcript post-processing."""
    # Filler words to remove (case-insensitive)
    # Note: Be conservative - only include words that are ALWAYS fillers
    filler_words: Set[str] = field(default_factory=lambda: {
        # English fillers (very conservative list)
        "um", "uh", "er", "ah", "eh", "hmm", "hm", "mm", "umm", "uhh",
        # Chinese fillers (standalone only)
        "嗯", "呃", "额", "唔",
    })

    # Multi-word phrases that are fillers
    filler_phrases: Set[str] = field(default_factory=lambda: {
        "you know", "i mean", "sort of", "kind of",
    })

    # Enable/disable features
    remove_fillers: bool = True
    remove_duplicates: bool = True
    fix_custom_words: bool = True
    fix_punctuation: bool = True

    # Fuzzy matching threshold (0-1, higher = stricter)
    similarity_threshold: float = 0.75

    # Phonetic matching for English
    use_phonetic_matching: bool = True


class PhoneticMatcher:
    """Simple phonetic matching using Soundex-like algorithm."""

    @staticmethod
    def encode(word: str) -> str:
        """
        Simple phonetic encoding for English words.
        Maps similar-sounding letters to same code.
        """
        if not word:
            return ""

        word = word.upper()

        # Keep first letter
        result = word[0]

        # Mapping for similar sounds
        mapping = {
            'B': '1', 'F': '1', 'P': '1', 'V': '1',
            'C': '2', 'G': '2', 'J': '2', 'K': '2', 'Q': '2', 'S': '2', 'X': '2', 'Z': '2',
            'D': '3', 'T': '3',
            'L': '4',
            'M': '5', 'N': '5',
            'R': '6',
        }

        prev_code = mapping.get(word[0], '0')

        for char in word[1:]:
            code = mapping.get(char, '0')
            if code != '0' and code != prev_code:
                result += code
            prev_code = code

        # Pad or truncate to 4 characters
        return (result + '000')[:4]

    @staticmethod
    def matches(word1: str, word2: str) -> bool:
        """Check if two words sound similar."""
        return PhoneticMatcher.encode(word1) == PhoneticMatcher.encode(word2)


class TranscriptProcessor:
    """Post-process transcription output."""

    def __init__(self, config: Optional[ProcessorConfig] = None):
        self.config = config or ProcessorConfig()
        self.custom_words: List[str] = []
        self.custom_phrases: List[Tuple[str, str]] = []  # (pattern, replacement)
        self._phonetic_cache: dict = {}

    def add_custom_words(self, words: List[str]):
        """
        Add custom words for correction.

        For multi-word terms, you can specify the misheard version:
        - "CoreML" - will match "coreml", "core ml", "core-ml" etc.
        - ("eye phone", "iPhone") - explicit mapping
        """
        for word in words:
            if isinstance(word, tuple):
                # Explicit mapping: (pattern, replacement)
                self.custom_phrases.append(word)
            else:
                self.custom_words.append(word)
                self._phonetic_cache[word] = PhoneticMatcher.encode(word)

                # Auto-generate common misspellings for CamelCase words
                # "CoreML" -> also match "core ml", "coreml"
                if any(c.isupper() for c in word[1:]):  # Has uppercase after first char
                    # Split on CamelCase boundaries
                    # "CoreML" -> ["Core", "ML"], "iPhone" -> ["i", "Phone"]
                    parts = re.findall(r'[A-Z]+[a-z]*|[a-z]+', word)
                    if len(parts) > 1:
                        # Generate variations
                        spaced = ' '.join(parts).lower()  # "core ml"
                        joined = ''.join(parts).lower()   # "coreml"
                        self.custom_phrases.append((spaced, word))
                        self.custom_phrases.append((joined, word))

    def clear_custom_words(self):
        """Clear custom words list."""
        self.custom_words.clear()
        self.custom_phrases.clear()
        self._phonetic_cache.clear()

    def process(self, text: str) -> str:
        """
        Process transcript with all enabled features.

        Args:
            text: Raw transcription text

        Returns:
            Cleaned text
        """
        if not text:
            return text

        result = text

        # Order matters:
        # 1. Remove fillers first (they can interfere with other processing)
        if self.config.remove_fillers:
            result = self._remove_fillers(result)

        # 2. Remove duplicate words
        if self.config.remove_duplicates:
            result = self._remove_duplicates(result)

        # 3. Fix custom words (fuzzy matching)
        if self.config.fix_custom_words and self.custom_words:
            result = self._fix_custom_words(result)

        # 4. Fix punctuation spacing
        if self.config.fix_punctuation:
            result = self._fix_punctuation(result)

        return result.strip()

    def _remove_fillers(self, text: str) -> str:
        """Remove filler words from text."""
        result = text

        # Handle multi-word filler phrases first (case-insensitive)
        for phrase in sorted(self.config.filler_phrases, key=len, reverse=True):
            pattern = r'\b' + re.escape(phrase) + r'\b'
            result = re.sub(pattern, '', result, flags=re.IGNORECASE)

        # Handle single-word fillers
        words = result.split()
        cleaned = []
        for word in words:
            # Strip punctuation for comparison
            word_clean = re.sub(r'[^\w\u4e00-\u9fff]', '', word)
            word_lower = word_clean.lower()
            # Check both the word and Chinese characters
            if word_lower not in self.config.filler_words and word_clean not in self.config.filler_words:
                cleaned.append(word)

        return ' '.join(cleaned)

    def _remove_duplicates(self, text: str) -> str:
        """
        Remove duplicate adjacent words (stuttering).
        Examples: "I I went" -> "I went", "the the cat" -> "the cat"
        """
        words = text.split()
        if len(words) < 2:
            return text

        result = [words[0]]
        for word in words[1:]:
            # Compare lowercase versions, but keep original case
            if word.lower() != result[-1].lower():
                result.append(word)

        return ' '.join(result)

    def _fix_custom_words(self, text: str) -> str:
        """Fix commonly misheard words using fuzzy matching."""
        result = text

        # First, handle multi-word phrase replacements
        for pattern, replacement in self.custom_phrases:
            # Case-insensitive replacement with word boundaries
            regex = r'\b' + re.escape(pattern) + r'\b'
            result = re.sub(regex, replacement, result, flags=re.IGNORECASE)

        # Then handle single-word fuzzy matching
        words = result.split()
        output = []

        for word in words:
            # Strip punctuation for matching, preserve for output
            punct_before = ''
            punct_after = ''
            clean_word = word

            # Extract leading/trailing punctuation
            match = re.match(r'^([^\w\u4e00-\u9fff]*)(.+?)([^\w\u4e00-\u9fff]*)$', word)
            if match:
                punct_before, clean_word, punct_after = match.groups()

            # Try to match against custom words
            best_match = None
            best_score = self.config.similarity_threshold

            for custom_word in self.custom_words:
                # Skip if lengths are too different
                len_diff = abs(len(clean_word) - len(custom_word))
                if len_diff > 3:
                    continue

                # Skip very short words (too many false positives)
                if len(clean_word) < 3:
                    continue

                # Calculate similarity
                score = self._similarity(clean_word, custom_word)

                if score > best_score:
                    best_score = score
                    best_match = custom_word

            if best_match:
                # Preserve original case pattern if possible
                if clean_word.isupper():
                    corrected = best_match.upper()
                elif clean_word.islower():
                    corrected = best_match.lower()
                elif clean_word.istitle():
                    corrected = best_match.title()
                else:
                    # Keep custom word's original case
                    corrected = best_match

                output.append(punct_before + corrected + punct_after)
            else:
                output.append(word)

        return ' '.join(output)

    def _similarity(self, word1: str, word2: str) -> float:
        """
        Calculate similarity between two words.
        Uses both string similarity and phonetic matching.
        """
        word1_lower = word1.lower()
        word2_lower = word2.lower()

        # Exact match
        if word1_lower == word2_lower:
            return 1.0

        # String similarity (Levenshtein-based)
        str_sim = SequenceMatcher(None, word1_lower, word2_lower).ratio()

        # Phonetic similarity (bonus)
        if self.config.use_phonetic_matching:
            if PhoneticMatcher.matches(word1, word2):
                str_sim = min(1.0, str_sim + 0.2)  # Boost by 0.2

        return str_sim

    def _fix_punctuation(self, text: str) -> str:
        """Fix punctuation spacing issues."""
        result = text

        # Remove space before punctuation
        result = re.sub(r'\s+([,.!?;:)])', r'\1', result)

        # Add space after punctuation if missing (except for abbreviations)
        result = re.sub(r'([,.!?;:])([A-Za-z\u4e00-\u9fff])', r'\1 \2', result)

        # Remove space after opening brackets
        result = re.sub(r'([(])\s+', r'\1', result)

        # Fix multiple spaces
        result = re.sub(r'\s+', ' ', result)

        return result


# Convenience function
def clean_transcript(
    text: str,
    custom_words: Optional[List[str]] = None,
    remove_fillers: bool = True,
    remove_duplicates: bool = True
) -> str:
    """
    Quick function to clean a transcript.

    Args:
        text: Raw transcription
        custom_words: List of words to correct (e.g., ["Claude", "CoreML"])
        remove_fillers: Remove filler words like "um", "uh"
        remove_duplicates: Remove stuttering like "I I went"

    Returns:
        Cleaned transcript
    """
    config = ProcessorConfig(
        remove_fillers=remove_fillers,
        remove_duplicates=remove_duplicates
    )
    processor = TranscriptProcessor(config)

    if custom_words:
        processor.add_custom_words(custom_words)

    return processor.process(text)


# Demo
if __name__ == "__main__":
    print("=" * 60)
    print("Transcript Post-Processing Demo")
    print("=" * 60)

    processor = TranscriptProcessor()
    processor.add_custom_words([
        # CamelCase words auto-generate phrase mappings
        "Claude", "CoreML", "iPhone", "macOS", "iOS",
        "SenseVoice", "SepReformer", "FluidAudio",
        # Explicit mappings for tricky cases
        ("eye phone", "iPhone"),
        ("clod", "Claude"),
        ("claud", "Claude"),
    ])

    test_cases = [
        # Filler removal
        ("I um really like this product", "Filler removal"),
        ("嗯，我觉得很好", "Chinese fillers"),

        # Duplicate removal
        ("I I went to the the store", "Duplicate words"),
        ("The the cat sat on on the mat", "Multiple duplicates"),

        # Custom word correction
        ("I use clod code for programming", "Misheard: clod -> Claude"),
        ("The core ml model is fast", "Spacing: core ml -> CoreML"),
        ("I have an eye phone", "Misheard: eye phone -> iPhone"),
        ("The sense voice model works well", "Spacing: sense voice -> SenseVoice"),
        ("We're using fluid audio for VAD", "Spacing: fluid audio -> FluidAudio"),

        # Combined
        ("I um use clod code and and um it it works great", "Combined fixes"),

        # Punctuation
        ("Hello , world .How are you ?", "Punctuation spacing"),

        # Real-world examples
        ("um I think uh the core ml model is is really fast you know", "Real-world mix"),
    ]

    for text, description in test_cases:
        result = processor.process(text)
        print(f"\n{description}:")
        print(f"  Input:  '{text}'")
        print(f"  Output: '{result}'")
