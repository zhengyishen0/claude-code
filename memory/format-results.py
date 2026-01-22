#!/usr/bin/env python3
"""Fast formatting of memory search results using pure Python (no pandas).

Two modes:
- simple: Rank by keyword hits -> match count -> recency
- strict: Rank by match count -> recency (hits not relevant since AND-filtered)

NLP modes (--nlp):
- none: Exact matching only (default, fastest)
- porter: Porter stemmer
- snowball: Snowball stemmer (balanced)
- lemma: WordNet lemmatizer (handles irregular forms)
- hybrid: Lemmatization + stemming fallback (best accuracy)

Optimized: Removed pandas dependency for 2.5x faster startup.
"""

import sys
import re
from collections import defaultdict
from pathlib import Path

# Import normalizer (graceful fallback if NLTK not available)
try:
    from normalizer import TextNormalizer
    NORMALIZER_AVAILABLE = True
except ImportError:
    NORMALIZER_AVAILABLE = False


def shorten_path(path):
    """Replace $HOME with ~"""
    home = str(Path.home())
    return path.replace(home, "~")


def get_keyword_counts(text, keywords, normalizer=None):
    """Return dict of keyword -> occurrence count in text.
    
    If normalizer is provided, also matches normalized forms.
    """
    text_lower = text.lower()
    counts = {}

    if normalizer and normalizer.mode != 'none':
        text_normalized = normalizer.normalize(text)
        
        for keyword in keywords:
            pattern = keyword.replace('_', '.')
            # Check original text
            matches = re.findall(pattern, text_lower, re.IGNORECASE)
            if matches:
                counts[keyword] = len(matches)
                continue
            
            # Check normalized text
            keyword_normalized = normalizer.normalize_word(keyword.replace('_', ''))
            norm_matches = text_normalized.split().count(keyword_normalized)
            if norm_matches:
                counts[keyword] = norm_matches
                continue
            
            # Check variations
            variations = normalizer.get_variations(keyword.replace('_', ''))
            for var in variations:
                var_matches = len(re.findall(rf'\b{re.escape(var)}\b', text_normalized, re.IGNORECASE))
                if var_matches:
                    counts[keyword] = var_matches
                    break
    else:
        for keyword in keywords:
            pattern = keyword.replace('_', '.')
            matches = re.findall(pattern, text_lower, re.IGNORECASE)
            if matches:
                counts[keyword] = len(matches)

    return counts


def count_keyword_hits(text, keywords, normalizer=None):
    """Count how many unique keywords appear in the text."""
    return len(get_keyword_counts(text, keywords, normalizer))


def parse_keywords(query, mode):
    """Extract keywords from query based on mode."""
    if mode == 'strict':
        terms = []
        for group in query.split():
            terms.extend(group.split('|'))
        return [t.lower() for t in terms]
    else:
        return [k.lower() for k in query.split()]


def extract_snippet(text, keywords, context, normalizer=None):
    """Extract snippet around a matched keyword if text is long."""
    if len(text) <= context:
        return text

    text_lower = text.lower()
    pos = -1

    for keyword in keywords:
        pattern = keyword.replace('_', '.')
        match = re.search(pattern, text_lower, re.IGNORECASE)
        if match:
            pos = match.start()
            break

    if pos < 0 and normalizer and normalizer.mode != 'none':
        text_normalized = normalizer.normalize(text)
        words = text_lower.split()
        norm_words = text_normalized.split()

        for keyword in keywords:
            keyword_norm = normalizer.normalize_word(keyword.replace('_', ''))
            if keyword_norm in norm_words:
                idx = norm_words.index(keyword_norm)
                pos = sum(len(w) + 1 for w in words[:idx])
                break

    if pos >= 0:
        before = context // 3
        after = context - before
        start = max(0, pos - before)
        end = min(len(text), pos + after)
        snippet = text[start:end]
        if start > 0:
            snippet = "..." + snippet
        if end < len(text):
            snippet = snippet + "..."
        return snippet
    else:
        return text[:context] + "..."


def main():
    if len(sys.argv) < 6:
        print("Usage: format-results.py <sessions> <messages> <context> <query> <mode> [nlp_mode]", file=sys.stderr)
        sys.exit(1)

    sessions_limit = int(sys.argv[1])
    messages_limit = int(sys.argv[2])
    context = int(sys.argv[3])
    query = sys.argv[4]
    mode = sys.argv[5]
    nlp_mode = sys.argv[6] if len(sys.argv) > 6 else 'none'

    normalizer = None
    if nlp_mode != 'none':
        if NORMALIZER_AVAILABLE:
            normalizer = TextNormalizer(nlp_mode)
            if normalizer.mode == 'none':
                nlp_mode = 'none'
        else:
            print(f"Warning: Normalizer not available, using exact matching", file=sys.stderr)
            nlp_mode = 'none'

    keywords = parse_keywords(query, mode)

    if normalizer and normalizer.mode != 'none':
        expanded_keywords = []
        for kw in keywords:
            expanded_keywords.append(kw)
            normalized = normalizer.normalize_word(kw)
            if normalized != kw and normalized not in expanded_keywords:
                expanded_keywords.append(normalized)
        keywords_for_matching = expanded_keywords
    else:
        keywords_for_matching = keywords

    sessions = defaultdict(dict)
    for line in sys.stdin:
        parts = line.rstrip('\n').split('\t', 4)
        if len(parts) == 5:
            session_id, timestamp, msg_type, text, project_path = parts
            key = (timestamp, msg_type, text)
            if key not in sessions[session_id]:
                sessions[session_id][key] = {
                    'timestamp': timestamp,
                    'type': msg_type,
                    'text': text,
                    'project_path': project_path
                }

    if not sessions:
        print("No matches found.")
        return

    session_stats = []
    for session_id, msgs_dict in sessions.items():
        msgs = list(msgs_dict.values())

        for msg in msgs:
            msg['keyword_counts'] = get_keyword_counts(msg['text'], keywords, normalizer)
            msg['keyword_hits'] = len(msg['keyword_counts'])

        session_keyword_counts = defaultdict(int)
        for msg in msgs:
            for kw, count in msg['keyword_counts'].items():
                session_keyword_counts[kw] += count

        hits = len(session_keyword_counts) if mode == 'simple' else 0
        max_ts = max(m['timestamp'] for m in msgs)

        session_stats.append({
            'session_id': session_id,
            'hits': hits,
            'matches': len(msgs),
            'timestamp': max_ts,
            'project_path': msgs[0]['project_path'],
            'messages': msgs,
            'keyword_counts': dict(session_keyword_counts)
        })

    if mode == 'simple':
        session_stats.sort(key=lambda x: (x['hits'], x['matches'], x['timestamp']), reverse=True)
    else:
        session_stats = [s for s in session_stats if s['matches'] >= 5]
        session_stats.sort(key=lambda x: (x['matches'], x['timestamp']), reverse=True)

    session_stats = session_stats[:sessions_limit]

    total_sessions = len(session_stats)
    total_keywords = len(keywords)
    nlp_indicator = f" [{nlp_mode}]" if nlp_mode != 'none' else ""

    for s in session_stats:
        short_id = s['session_id'][:8]
        project = shorten_path(s['project_path'])
        matches = s['matches']
        date = s['timestamp'][:10]

        kw_counts = s['keyword_counts']
        kw_parts = ' '.join(f"{kw}[{kw_counts[kw]}]" for kw in keywords if kw in kw_counts)
        print(f"[{short_id}] {kw_parts} ({matches} matches | {date} | {project})")

        sorted_msgs = sorted(s['messages'], key=lambda m: m['keyword_hits'], reverse=True)
        for msg in sorted_msgs[:messages_limit]:
            role = "[user]" if msg['type'] == 'user' else "[asst]"
            text = extract_snippet(msg['text'], keywords_for_matching, context, normalizer)
            print(f"{role} {text}")

        if matches > messages_limit:
            print(f"... and {matches - messages_limit} more matches")

        print()

    if mode == 'simple':
        print(f"\nFound matches in {total_sessions} sessions (searched {total_keywords} keywords){nlp_indicator}")
    else:
        print(f"\nFound matches in {total_sessions} sessions (strict mode){nlp_indicator}")

    session_ids = [s['session_id'] for s in session_stats]
    print(','.join(session_ids), file=sys.stderr)


if __name__ == '__main__':
    main()
