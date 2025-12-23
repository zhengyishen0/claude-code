#!/usr/bin/env python3
"""Fast formatting of memory search results using pandas."""

import sys
import pandas as pd
from pathlib import Path

def shorten_path(path):
    """Replace $HOME with ~"""
    home = str(Path.home())
    return path.replace(home, "~")

def main():
    if len(sys.argv) < 5:
        print("Usage: format-results.py <sessions> <messages> <context> <query>", file=sys.stderr)
        sys.exit(1)

    sessions = int(sys.argv[1])
    messages = int(sys.argv[2])
    context = int(sys.argv[3])
    query = sys.argv[4].lower()

    # Read TSV from stdin manually (text field may contain tabs)
    # Columns: session_id, timestamp, type, text, project_path
    # NOTE: These are already filtered by search terms, so all rows match the query
    rows = []
    for line in sys.stdin:
        parts = line.rstrip('\n').split('\t', 4)  # Max split 4 times
        if len(parts) == 5:
            rows.append(parts)

    df = pd.DataFrame(rows, columns=['session_id', 'timestamp', 'type', 'text', 'project_path'])

    if df.empty:
        print("No matches found.")
        return

    # No need for session chain deduplication - the indexer now uses filename as session ID,
    # so all compacted sessions in the same file are automatically grouped together

    # Group by session and get stats
    session_stats = df.groupby('session_id').agg({
        'timestamp': 'max',  # Latest timestamp
        'project_path': 'first',  # First project path
        'session_id': 'count'  # Count of matches
    }).rename(columns={'session_id': 'count'})

    # Sort by relevance (match count) first, then by recency (timestamp)
    # This prioritizes sessions with more matches as they're likely more relevant
    session_stats = session_stats.sort_values(['count', 'timestamp'], ascending=[False, False])

    # Limit to top N sessions
    session_stats = session_stats.head(sessions)

    # Print results
    total_sessions = len(session_stats)

    for session_id in session_stats.index:
        project = shorten_path(session_stats.loc[session_id, 'project_path'])
        count = session_stats.loc[session_id, 'count']

        print(f"{project} | {session_id} | {count} matches")

        # Get messages for this session (these already match the search query)
        session_msgs = df[df['session_id'] == session_id].head(messages)

        for _, row in session_msgs.iterrows():
            role = "[user]" if row['type'] == 'user' else "[asst]"
            text = row['text']

            # Extract snippet around the query term if text is long
            if len(text) > context:
                text_lower = text.lower()
                pos = text_lower.find(query)
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

        if count > messages:
            print(f"... and {count - messages} more matches")

        print()

    print(f"\nFound matches in {total_sessions} sessions")

if __name__ == '__main__':
    main()
