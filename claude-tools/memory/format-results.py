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
    if len(sys.argv) < 3:
        print("Usage: format-results.py <limit> <query>", file=sys.stderr)
        sys.exit(1)

    limit = int(sys.argv[1])
    query = sys.argv[2].lower()

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

    # Sort by latest timestamp descending
    session_stats = session_stats.sort_values('timestamp', ascending=False)

    # Limit to top N sessions
    session_stats = session_stats.head(limit)

    # Print results
    total_sessions = len(session_stats)
    msg_limit = 3  # Show up to 3 messages per session

    for session_id in session_stats.index:
        project = shorten_path(session_stats.loc[session_id, 'project_path'])
        count = session_stats.loc[session_id, 'count']

        print(f"{project} | {session_id}")
        print(f"Matches: {count}")

        # Get messages for this session (these already match the search query)
        session_msgs = df[df['session_id'] == session_id].head(msg_limit)

        for _, row in session_msgs.iterrows():
            role = "[user]" if row['type'] == 'user' else "[asst]"
            text = row['text']

            # Extract snippet around the query term if text is long
            if len(text) > 200:
                text_lower = text.lower()
                pos = text_lower.find(query)
                if pos >= 0:
                    # Show context around the match
                    start = max(0, pos - 75)
                    end = min(len(text), pos + 125)
                    snippet = text[start:end]
                    if start > 0:
                        snippet = "..." + snippet
                    if end < len(text):
                        snippet = snippet + "..."
                    text = snippet
                else:
                    text = text[:200] + "..."

            print(f"{role} {text}")

        if count > msg_limit:
            print(f"... and {count - msg_limit} more")

        print()

    print(f"Found matches in {total_sessions} sessions")

if __name__ == '__main__':
    main()
