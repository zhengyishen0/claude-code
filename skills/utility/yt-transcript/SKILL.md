---
name: yt-transcript
description: Extract YouTube video transcripts to text
---

# yt-transcript

Extract transcripts from YouTube videos.

## Usage

```bash
/yt-transcript <video_id_or_url>
```

## Examples

```bash
/yt-transcript dQw4w9WgXcQ
/yt-transcript https://www.youtube.com/watch?v=dQw4w9WgXcQ
```

## Options

- `-l, --lang <code>`: Language code (default: en)
- `-o, --output <file>`: Save to file instead of stdout
- `--json`: Output as JSON with timestamps

## Requirements

- Python 3
- youtube-transcript-api (`pip install youtube-transcript-api`)
