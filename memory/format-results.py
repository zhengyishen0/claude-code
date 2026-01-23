#!/usr/bin/env python3
"""Fast formatting of memory search results using pure Python (no pandas).

Two modes:
- simple: Rank by keyword hits -> match count -> recency
- strict: Rank by match count -> recency (hits not relevant since AND-filtered)

Uses pre-normalized index for NLP matching with zero query-time overhead.
Index format: session_id | timestamp | type | text | text_normalized | project_path

Optimized: Removed pandas dependency for 2.5x faster startup.
"""

import sys
import re
from collections import defaultdict
from pathlib import Path


def shorten_path(path):
    """Replace $HOME with ~"""
    home = str(Path.home())
    return path.replace(home, "~")


def get_keyword_counts(text, text_normalized, keywords, keywords_normalized):
    """Return dict of keyword -> occurrence count in text.

    Uses word boundary matching on normalized text for ASCII keywords.
    For non-ASCII (Chinese, etc.), searches original text directly.
    """
    counts = {}

    for keyword, keyword_norm in zip(keywords, keywords_normalized):
        if not keyword.isascii():
            # Non-ASCII (Chinese, etc.): search original text, no word boundary
            matches = re.findall(re.escape(keyword), text, re.IGNORECASE)
        else:
            # ASCII: word boundary match on normalized text
            pattern = rf'\b{re.escape(keyword_norm)}\b'
            matches = re.findall(pattern, text_normalized, re.IGNORECASE)

        if matches:
            counts[keyword] = len(matches)

    return counts


def count_keyword_hits(text, text_normalized, keywords, keywords_normalized):
    """Count how many unique keywords appear in the text."""
    return len(get_keyword_counts(text, text_normalized, keywords, keywords_normalized))


def parse_keywords(query, mode):
    """Extract keywords from query based on mode."""
    if mode == 'strict':
        terms = []
        for group in query.split():
            terms.extend(group.split('|'))
        return [t.lower() for t in terms]
    else:
        return [k.lower() for k in query.split()]


def extract_snippet(text, text_normalized, keywords, keywords_normalized, context):
    """Extract snippet around a matched keyword if text is long."""
    if len(text) <= context:
        return text

    text_lower = text.lower()
    pos = -1

    # Try to find keyword in original text first
    for keyword in keywords:
        pattern = keyword.replace('_', '.')
        match = re.search(pattern, text_lower, re.IGNORECASE)
        if match:
            pos = match.start()
            break

    # If not found, find via normalized text word position
    if pos < 0:
        words = text_lower.split()
        norm_words = text_normalized.split()

        for keyword_norm in keywords_normalized:
            if keyword_norm in norm_words:
                idx = norm_words.index(keyword_norm)
                # Map normalized word index to character position in original
                if idx < len(words):
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
        print("Usage: format-results.py <sessions> <messages> <context> <query> <mode> <query_normalized>", file=sys.stderr)
        sys.exit(1)

    sessions_limit = int(sys.argv[1])
    messages_limit = int(sys.argv[2])
    context = int(sys.argv[3])
    query = sys.argv[4]
    mode = sys.argv[5]
    query_normalized = sys.argv[6] if len(sys.argv) > 6 else query.lower()

    keywords = parse_keywords(query, mode)
    keywords_normalized = query_normalized.lower().split()

    sessions = defaultdict(dict)
    for line in sys.stdin:
        parts = line.rstrip('\n').split('\t', 5)
        if len(parts) == 6:
            session_id, timestamp, msg_type, text, text_normalized, project_path = parts
            key = (timestamp, msg_type, text)
            if key not in sessions[session_id]:
                sessions[session_id][key] = {
                    'timestamp': timestamp,
                    'type': msg_type,
                    'text': text,
                    'text_normalized': text_normalized,
                    'project_path': project_path
                }

    if not sessions:
        print("No matches found.")
        return

    session_stats = []
    for session_id, msgs_dict in sessions.items():
        msgs = list(msgs_dict.values())

        for msg in msgs:
            msg['keyword_counts'] = get_keyword_counts(
                msg['text'], msg['text_normalized'], keywords, keywords_normalized
            )
            msg['keyword_hits'] = len(msg['keyword_counts'])

        session_keyword_counts = defaultdict(int)
        for msg in msgs:
            for kw, count in msg['keyword_counts'].items():
                session_keyword_counts[kw] += count

        hits = len(session_keyword_counts) if mode == 'simple' else 0
        max_ts = max(m['timestamp'] for m in msgs)

        # Calculate weighted score: first keyword = n, last keyword = 1
        # This prioritizes core keywords (listed first) over less confident ones
        weighted_score = 0
        n = len(keywords)
        for i, kw in enumerate(keywords):
            weight = n - i  # First keyword gets highest weight
            weighted_score += session_keyword_counts.get(kw, 0) * weight

        session_stats.append({
            'session_id': session_id,
            'hits': hits,
            'matches': len(msgs),
            'weighted_score': weighted_score,
            'timestamp': max_ts,
            'project_path': msgs[0]['project_path'],
            'messages': msgs,
            'keyword_counts': dict(session_keyword_counts)
        })

    if mode == 'simple':
        # Rank by weighted score (core keywords matter more), then hits, then matches
        session_stats.sort(key=lambda x: (x['weighted_score'], x['hits'], x['matches'], x['timestamp']), reverse=True)
    else:
        session_stats = [s for s in session_stats if s['matches'] >= 5]
        session_stats.sort(key=lambda x: (x['matches'], x['timestamp']), reverse=True)

    # Auto-cutoff: 70% cumulative score, min=3, max=8
    if session_stats:
        total_score = sum(s['weighted_score'] for s in session_stats)
        cumsum = 0
        cutoff_idx = 0
        for i, s in enumerate(session_stats):
            cumsum += s['weighted_score']
            cutoff_idx = i + 1
            if cumsum >= total_score * 0.7:
                break
        # Apply min/max bounds
        cutoff_idx = max(3, min(8, cutoff_idx))
        session_stats = session_stats[:cutoff_idx]
    else:
        session_stats = session_stats[:sessions_limit]

    total_sessions = len(session_stats)
    total_keywords = len(keywords)

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
            text = extract_snippet(
                msg['text'], msg['text_normalized'], keywords, keywords_normalized, context
            )
            print(f"{role} {text}")

        if matches > messages_limit:
            print(f"... and {matches - messages_limit} more matches")

        print()

    if mode == 'simple':
        print(f"\nFound matches in {total_sessions} sessions (searched {total_keywords} keywords)")
    else:
        print(f"\nFound matches in {total_sessions} sessions (strict mode)")

    session_ids = [s['session_id'] for s in session_stats]
    print(','.join(session_ids), file=sys.stderr)


if __name__ == '__main__':
    main()
