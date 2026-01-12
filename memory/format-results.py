#!/usr/bin/env python3
"""Fast formatting of memory search results using pandas.

Two modes:
- simple: Rank by keyword hits → match count → recency
- strict: Rank by match count → recency (hits not relevant since AND-filtered)
"""

import sys
import re
import pandas as pd
from pathlib import Path

def shorten_path(path):
    """Replace $HOME with ~"""
    home = str(Path.home())
    return path.replace(home, "~")

def count_keyword_hits(text, keywords):
    """Count how many unique keywords appear in the text."""
    text_lower = text.lower()
    hits = 0
    for keyword in keywords:
        # Convert underscore to regex pattern (same as shell script)
        pattern = keyword.replace('_', '.')
        if re.search(pattern, text_lower, re.IGNORECASE):
            hits += 1
    return hits

def parse_keywords(query, mode):
    """Extract keywords from query based on mode."""
    if mode == 'strict':
        # For strict mode, extract individual terms from pipe groups
        # "chrome|browser automation|workflow" → [chrome, browser, automation, workflow]
        terms = []
        for group in query.split():
            terms.extend(group.split('|'))
        return [t.lower() for t in terms]
    else:
        # Simple mode: just split by spaces
        return [k.lower() for k in query.split()]

def main():
    if len(sys.argv) < 6:
        print("Usage: format-results.py <sessions> <messages> <context> <query> <mode>", file=sys.stderr)
        sys.exit(1)

    sessions = int(sys.argv[1])
    messages = int(sys.argv[2])
    context = int(sys.argv[3])
    query = sys.argv[4]
    mode = sys.argv[5]  # 'simple' or 'strict'

    # Parse keywords based on mode
    keywords = parse_keywords(query, mode)

    # Read TSV from stdin manually (text field may contain tabs)
    # Columns: session_id, timestamp, type, text, project_path
    rows = []
    for line in sys.stdin:
        parts = line.rstrip('\n').split('\t', 4)  # Max split 4 times
        if len(parts) == 5:
            rows.append(parts)

    df = pd.DataFrame(rows, columns=['session_id', 'timestamp', 'type', 'text', 'project_path'])

    if df.empty:
        print("No matches found.")
        return

    # Group by session and calculate stats
    if mode == 'simple':
        # Simple mode: count keyword hits for ranking
        def session_stats(group):
            all_text = ' '.join(group['text'].tolist())
            unique_hits = count_keyword_hits(all_text, keywords)
            return pd.Series({
                'hits': unique_hits,
                'matches': len(group),
                'timestamp': group['timestamp'].max(),
                'project_path': group['project_path'].iloc[0]
            })

        session_stats_df = df.groupby('session_id').apply(session_stats, include_groups=False)

        # Sort by: hits → matches → timestamp
        session_stats_df = session_stats_df.sort_values(
            ['hits', 'matches', 'timestamp'],
            ascending=[False, False, False]
        )
    else:
        # Strict mode: just count matches (AND-filtering already done)
        def session_stats(group):
            return pd.Series({
                'hits': 0,  # Not used in strict mode
                'matches': len(group),
                'timestamp': group['timestamp'].max(),
                'project_path': group['project_path'].iloc[0]
            })

        session_stats_df = df.groupby('session_id').apply(session_stats, include_groups=False)

        # Filter: require minimum 5 matches to avoid trivial mentions
        session_stats_df = session_stats_df[session_stats_df['matches'] >= 5]

        # Sort by: matches → timestamp
        session_stats_df = session_stats_df.sort_values(
            ['matches', 'timestamp'],
            ascending=[False, False]
        )

    # Limit to top N sessions
    session_stats_df = session_stats_df.head(sessions)

    # Print results
    total_sessions = len(session_stats_df)
    total_keywords = len(keywords)

    for session_id in session_stats_df.index:
        stats = session_stats_df.loc[session_id]
        project = shorten_path(stats['project_path'])
        hits = int(stats['hits'])
        matches = int(stats['matches'])
        timestamp = stats['timestamp']

        # Format header based on mode
        if mode == 'simple':
            print(f"{project} | {session_id} | {hits}/{total_keywords} keywords, {matches} matches | {timestamp}")
        else:
            print(f"{project} | {session_id} | {matches} matches | {timestamp}")

        # Get messages for this session
        session_msgs = df[df['session_id'] == session_id].head(messages)

        for _, row in session_msgs.iterrows():
            role = "[user]" if row['type'] == 'user' else "[asst]"
            text = row['text']

            # Extract snippet around a matched keyword if text is long
            if len(text) > context:
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
                    text = snippet
                else:
                    text = text[:context] + "..."

            print(f"{role} {text}")

        if matches > messages:
            print(f"... and {matches - messages} more matches")

        print()

    if mode == 'simple':
        print(f"\nFound matches in {total_sessions} sessions (searched {total_keywords} keywords)")
    else:
        print(f"\nFound matches in {total_sessions} sessions (strict mode)")

if __name__ == '__main__':
    main()
