#!/usr/bin/env python3
"""Fast formatting of memory search results using pure Python (no pandas).

Two modes:
- simple: Rank by keyword hits -> match count -> recency
- strict: Rank by match count -> recency (hits not relevant since AND-filtered)

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


def get_keyword_counts(text, keywords):
    """Return dict of keyword -> occurrence count in text."""
    text_lower = text.lower()
    counts = {}
    for keyword in keywords:
        pattern = keyword.replace('_', '.')
        matches = re.findall(pattern, text_lower, re.IGNORECASE)
        if matches:
            counts[keyword] = len(matches)
    return counts


def count_keyword_hits(text, keywords):
    """Count how many unique keywords appear in the text."""
    return len(get_keyword_counts(text, keywords))


def parse_keywords(query, mode):
    """Extract keywords from query based on mode."""
    if mode == 'strict':
        # For strict mode, extract individual terms from pipe groups
        # "chrome|browser automation|workflow" -> [chrome, browser, automation, workflow]
        terms = []
        for group in query.split():
            terms.extend(group.split('|'))
        return [t.lower() for t in terms]
    else:
        # Simple mode: just split by spaces
        return [k.lower() for k in query.split()]


def extract_snippet(text, keywords, context):
    """Extract snippet around a matched keyword if text is long."""
    if len(text) <= context:
        return text

    text_lower = text.lower()
    # Find first matching keyword
    pos = -1
    for keyword in keywords:
        pattern = keyword.replace('_', '.')
        match = re.search(pattern, text_lower, re.IGNORECASE)
        if match:
            pos = match.start()
            break

    if pos >= 0:
        # Show context around the match (1/3 before, 2/3 after)
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
        print("Usage: format-results.py <sessions> <messages> <context> <query> <mode>", file=sys.stderr)
        sys.exit(1)

    sessions_limit = int(sys.argv[1])
    messages_limit = int(sys.argv[2])
    context = int(sys.argv[3])
    query = sys.argv[4]
    mode = sys.argv[5]  # 'simple' or 'strict'

    # Parse keywords based on mode
    keywords = parse_keywords(query, mode)

    # Read TSV from stdin and group by session
    # Columns: session_id, timestamp, type, text, project_path
    # Use dict to deduplicate by (timestamp, type, text) - fixes duplicate counting from incremental updates
    sessions = defaultdict(dict)
    for line in sys.stdin:
        parts = line.rstrip('\n').split('\t', 4)  # Max split 4 times
        if len(parts) == 5:
            session_id, timestamp, msg_type, text, project_path = parts
            # Deduplicate using (timestamp, type, text) as key
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

    # Calculate stats for each session
    session_stats = []
    for session_id, msgs_dict in sessions.items():
        # Convert dict values to list (deduplication was done during parsing)
        msgs = list(msgs_dict.values())

        # Calculate keyword hits for each message (for sorting)
        for msg in msgs:
            msg['keyword_counts'] = get_keyword_counts(msg['text'], keywords)
            msg['keyword_hits'] = len(msg['keyword_counts'])

        # Aggregate keyword counts across all messages in session
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

    # Filter and sort based on mode
    if mode == 'simple':
        # Sort by: hits (desc) -> matches (desc) -> timestamp (desc)
        # ISO timestamps sort correctly as strings, use reverse for descending
        session_stats.sort(key=lambda x: (x['hits'], x['matches'], x['timestamp']), reverse=True)
    else:
        # Strict mode: filter minimum 5 matches, sort by matches -> timestamp
        session_stats = [s for s in session_stats if s['matches'] >= 5]
        session_stats.sort(key=lambda x: (x['matches'], x['timestamp']), reverse=True)

    # Limit to top N sessions
    session_stats = session_stats[:sessions_limit]

    # Print results
    total_sessions = len(session_stats)
    total_keywords = len(keywords)

    for s in session_stats:
        short_id = s['session_id'][:8]
        project = shorten_path(s['project_path'])
        hits = s['hits']
        matches = s['matches']
        date = s['timestamp'][:10]  # YYYY-MM-DD

        # Format: [session_id] keyword[count]... (matches | date | path)
        kw_counts = s['keyword_counts']
        kw_parts = ' '.join(f"{kw}[{kw_counts[kw]}]" for kw in keywords if kw in kw_counts)
        print(f"[{short_id}] {kw_parts} ({matches} matches | {date} | {project})")

        # Get messages with most keyword hits (not just first N)
        sorted_msgs = sorted(s['messages'], key=lambda m: m['keyword_hits'], reverse=True)
        for msg in sorted_msgs[:messages_limit]:
            role = "[user]" if msg['type'] == 'user' else "[asst]"
            text = extract_snippet(msg['text'], keywords, context)
            print(f"{role} {text}")

        if matches > messages_limit:
            print(f"... and {matches - messages_limit} more matches")

        print()

    if mode == 'simple':
        print(f"\nFound matches in {total_sessions} sessions (searched {total_keywords} keywords)")
    else:
        print(f"\nFound matches in {total_sessions} sessions (strict mode)")

    # Output session IDs to stderr for --recall integration
    session_ids = [s['session_id'] for s in session_stats]
    print(','.join(session_ids), file=sys.stderr)


if __name__ == '__main__':
    main()
