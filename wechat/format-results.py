#!/usr/bin/env python3
"""Format wechat search results grouped by chat with keyword hit stats."""

import sys
from collections import defaultdict


def count_keyword_hits(text, keywords):
    """Count how many unique keywords appear in the text."""
    text_lower = text.lower()
    return sum(1 for k in keywords if k.lower() in text_lower)


def extract_snippet(text, keywords, max_len=60):
    """Extract snippet around matched keyword."""
    if len(text) <= max_len:
        return text

    text_lower = text.lower()
    for keyword in keywords:
        pos = text_lower.find(keyword.lower())
        if pos >= 0:
            start = max(0, pos - 20)
            end = min(len(text), pos + max_len - 20)
            snippet = text[start:end]
            if start > 0:
                snippet = "..." + snippet
            if end < len(text):
                snippet = snippet + "..."
            return snippet

    return text[:max_len] + "..."


def main():
    if len(sys.argv) < 2:
        print("Usage: format-results.py <keywords>", file=sys.stderr)
        sys.exit(1)

    keywords = sys.argv[1].split()
    messages_per_chat = 3
    max_chats = 10

    # Read pipe-separated from stdin: timestamp|talker|content
    chats = defaultdict(list)
    for line in sys.stdin:
        line = line.rstrip('\n')
        if not line:
            continue
        parts = line.split('|', 2)
        if len(parts) >= 3:
            timestamp, talker, content = parts[0], parts[1], parts[2]
            chats[talker].append({
                'timestamp': timestamp,
                'content': content
            })

    if not chats:
        print("No matches found.")
        return

    # Calculate stats per chat
    chat_stats = []
    for talker, msgs in chats.items():
        all_text = talker + ' ' + ' '.join(m['content'] for m in msgs)
        hits = count_keyword_hits(all_text, keywords)
        max_ts = max(m['timestamp'] for m in msgs)

        chat_stats.append({
            'talker': talker,
            'hits': hits,
            'matches': len(msgs),
            'timestamp': max_ts,
            'messages': sorted(msgs, key=lambda x: x['timestamp'], reverse=True)
        })

    # Sort by: hits desc -> matches desc -> timestamp desc
    chat_stats.sort(key=lambda x: (x['hits'], x['matches'], x['timestamp']), reverse=True)
    chat_stats = chat_stats[:max_chats]

    total_keywords = len(keywords)

    # Print results
    for chat in chat_stats:
        talker = chat['talker'][:30] + "..." if len(chat['talker']) > 30 else chat['talker']
        hits = chat['hits']
        matches = chat['matches']
        ts = chat['timestamp']

        print(f"{'─' * 60}")
        print(f"{talker} | {hits}/{total_keywords} keywords, {matches} messages | {ts}")
        print()

        for msg in chat['messages'][:messages_per_chat]:
            snippet = extract_snippet(msg['content'], keywords)
            snippet = ' '.join(snippet.split())  # clean multiline
            print(f"  [{msg['timestamp'][11:16]}] {snippet}")

        if matches > messages_per_chat:
            print(f"  ... and {matches - messages_per_chat} more")
        print()

    print(f"Found {sum(c['matches'] for c in chat_stats)} messages in {len(chat_stats)} chats")


if __name__ == '__main__':
    main()
