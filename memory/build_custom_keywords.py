#!/usr/bin/env python3
"""Auto-discover domain keywords via co-occurrence analysis.

Analyzes the memory index to find words that frequently co-occur with
known seed keywords. These are likely domain-specific terms that should
be added to the custom keywords list.

Strategy:
1. Start with seed keywords (known domain terms)
2. Find messages containing seed keywords
3. Extract other words that frequently co-occur
4. Filter by frequency threshold and not in general stopwords
5. Write to data/custom_keywords.txt

Usage:
    python3 build_custom_keywords.py           # Analyze and suggest
    python3 build_custom_keywords.py --write   # Write to file

Run weekly or after significant index growth.
"""

import sys
import re
from pathlib import Path
from collections import Counter, defaultdict

# Try to import jieba
try:
    import jieba
    jieba.setLogLevel(jieba.logging.INFO)
    JIEBA_AVAILABLE = True
except ImportError:
    JIEBA_AVAILABLE = False

SCRIPT_DIR = Path(__file__).parent
INDEX_FILE = SCRIPT_DIR / 'data' / 'memory-index.tsv'
OUTPUT_FILE = SCRIPT_DIR / 'data' / 'custom_keywords.txt'

# Seed keywords - known domain terms to find co-occurrences with
SEED_KEYWORDS = {
    # English
    'feishu', 'lark', 'bitable', 'oauth', 'chrome', 'browser', 'cdp',
    'headless', 'playwright', 'automation', 'calendar', 'gmail', 'api',
    # Chinese
    '飞书', '多维表格', '审批', '浏览器', '自动化', '日历', '机器人',
}

# General stopwords to exclude (supplement to hint_keywords.py)
GENERAL_STOPWORDS = {
    # English
    'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'to', 'for', 'of', 'in', 'on', 'at', 'by', 'with', 'from', 'as',
    'and', 'or', 'but', 'if', 'then', 'else', 'this', 'that', 'it',
    'you', 'we', 'they', 'have', 'has', 'had', 'do', 'does', 'did',
    'will', 'would', 'can', 'could', 'should', 'may', 'might', 'must',
    'not', 'no', 'yes', 'just', 'also', 'only', 'more', 'some', 'any',
    'all', 'each', 'every', 'both', 'few', 'many', 'much', 'most',
    'other', 'such', 'same', 'new', 'first', 'last', 'next', 'right',
    'now', 'then', 'here', 'there', 'when', 'where', 'why', 'how',
    'what', 'which', 'who', 'whom', 'whose', 'one', 'two', 'three',
    'use', 'used', 'using', 'file', 'files', 'code', 'like', 'want',
    'need', 'get', 'got', 'make', 'made', 'set', 'see', 'look', 'find',
    'run', 'running', 'test', 'error', 'message', 'result', 'value',
    'data', 'name', 'type', 'text', 'line', 'time', 'user', 'path',
    # Chinese
    '的', '地', '得', '了', '着', '过', '吗', '呢', '啊', '吧', '呀',
    '我', '你', '他', '她', '它', '我们', '你们', '他们', '这', '那',
    '是', '有', '没有', '不', '会', '能', '可以', '要', '想', '做',
    '看', '说', '知道', '帮', '帮我', '请', '什么', '怎么', '为什么',
    '很', '太', '最', '更', '就', '才', '都', '也', '还', '又', '再',
    '个', '些', '点', '下', '次', '好', '行', '那', '然后',
}

# Minimum frequency to consider a word as a candidate
MIN_FREQUENCY = 5

# Minimum co-occurrence count with seed keywords
MIN_COOCCURRENCE = 3


def load_index():
    """Load messages from the memory index."""
    if not INDEX_FILE.exists():
        print(f"Error: Index file not found: {INDEX_FILE}", file=sys.stderr)
        print("Run 'memory search' first to build the index.", file=sys.stderr)
        sys.exit(1)

    messages = []
    with open(INDEX_FILE, 'r', encoding='utf-8') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) >= 4:
                session_id, timestamp, msg_type, text = parts[:4]
                messages.append({
                    'session_id': session_id,
                    'text': text,
                })
    return messages


def extract_words(text):
    """Extract words from text (both English and Chinese)."""
    words = set()

    # English words (3+ chars)
    en_words = re.findall(r'\b[a-zA-Z]{3,}\b', text.lower())
    words.update(en_words)

    # Chinese words (using jieba if available)
    zh_text = ''.join(re.findall(r'[\u4e00-\u9fff]+', text))
    if zh_text:
        if JIEBA_AVAILABLE:
            zh_words = [w for w in jieba.lcut(zh_text) if len(w) >= 2]
            words.update(zh_words)
        else:
            # Fallback: bigrams
            for i in range(len(zh_text) - 1):
                words.add(zh_text[i:i+2])

    return words


def find_cooccurrences(messages):
    """Find words that co-occur with seed keywords."""
    # Count global word frequency
    global_counts = Counter()

    # Count co-occurrences with each seed keyword
    cooccurrence = defaultdict(Counter)

    for msg in messages:
        text = msg['text']
        words = extract_words(text)

        # Update global counts
        global_counts.update(words)

        # Check which seed keywords appear in this message
        text_lower = text.lower()
        matching_seeds = set()
        for seed in SEED_KEYWORDS:
            if seed.lower() in text_lower or seed in text:
                matching_seeds.add(seed)

        # Update co-occurrence counts
        if matching_seeds:
            for word in words:
                for seed in matching_seeds:
                    if word.lower() != seed.lower() and word != seed:
                        cooccurrence[seed][word] += 1

    return global_counts, cooccurrence


def score_candidates(global_counts, cooccurrence):
    """Score candidate keywords by co-occurrence strength."""
    candidates = Counter()

    for seed, cooc_counts in cooccurrence.items():
        for word, count in cooc_counts.items():
            if count >= MIN_COOCCURRENCE:
                # Skip stopwords
                if word.lower() in GENERAL_STOPWORDS or word in GENERAL_STOPWORDS:
                    continue
                # Skip seed keywords themselves
                if word.lower() in {s.lower() for s in SEED_KEYWORDS} or word in SEED_KEYWORDS:
                    continue
                # Score by co-occurrence count weighted by inverse frequency
                # (rare words that co-occur often are more interesting)
                global_freq = global_counts.get(word, 1)
                score = count * (1 + 1.0 / (global_freq ** 0.5))
                candidates[word] += score

    return candidates


def load_existing_keywords():
    """Load existing custom keywords."""
    existing = set()
    if OUTPUT_FILE.exists():
        with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
            for line in f:
                word = line.strip()
                if word and not word.startswith('#'):
                    existing.add(word)
    return existing


def main():
    write_mode = '--write' in sys.argv

    print("=" * 60)
    print("Custom Keyword Discovery via Co-occurrence")
    print("=" * 60)
    print()

    # Load index
    print("Loading index...")
    messages = load_index()
    print(f"  {len(messages)} messages loaded")
    print()

    # Find co-occurrences
    print("Analyzing co-occurrences with seed keywords...")
    print(f"  Seeds: {', '.join(list(SEED_KEYWORDS)[:10])}...")
    global_counts, cooccurrence = find_cooccurrences(messages)
    print()

    # Score candidates
    print("Scoring candidates...")
    candidates = score_candidates(global_counts, cooccurrence)
    print()

    # Load existing
    existing = load_existing_keywords()

    # Show top candidates
    print("=" * 60)
    print("TOP CANDIDATE KEYWORDS")
    print("=" * 60)
    print()

    new_keywords = []
    for word, score in candidates.most_common(50):
        if word in existing:
            status = "(already in list)"
        else:
            status = "NEW"
            new_keywords.append(word)
        freq = global_counts.get(word, 0)
        print(f"  {word:<20} score={score:.1f}  freq={freq}  {status}")

    print()
    print(f"Found {len(new_keywords)} new candidate keywords")
    print()

    if write_mode:
        # Write to file
        print("=" * 60)
        print(f"Writing to {OUTPUT_FILE}")
        print("=" * 60)

        # Combine existing + new (top 30)
        all_keywords = sorted(existing | set(new_keywords[:30]))

        OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
            f.write("# Custom keywords for memory hint\n")
            f.write("# Auto-generated by build_custom_keywords.py\n")
            f.write("# One keyword per line\n")
            f.write("#\n")
            for word in all_keywords:
                f.write(f"{word}\n")

        print(f"  Wrote {len(all_keywords)} keywords")
        print()
    else:
        print("Run with --write to save to file:")
        print(f"  python3 {Path(__file__).name} --write")
        print()


if __name__ == '__main__':
    main()
