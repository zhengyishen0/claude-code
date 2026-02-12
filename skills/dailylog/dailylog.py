#!/usr/bin/env python3
"""
dailylog - Unified daily log for sessions, lessons, and jj changes.

Combines episodic (sessions, jj) and procedural (lessons) memory in one place.
"""

import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

# Paths
VAULT_DIR = Path(__file__).parent.parent.parent / "vault"
LOGS_DIR = VAULT_DIR / "logs"


def get_today() -> str:
    """Get today's date as YYYY-MM-DD."""
    return datetime.now().strftime("%Y-%m-%d")


def get_log_path(date: Optional[str] = None) -> Path:
    """Get path to daily log file."""
    date = date or get_today()
    return LOGS_DIR / f"{date}.md"


def ensure_log_exists(date: Optional[str] = None) -> Path:
    """Ensure today's log file exists with template."""
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    log_path = get_log_path(date)

    if not log_path.exists():
        date = date or get_today()
        template = f"""---
date: {date}
---

# {date}

## Sessions

## Lessons

## JJ Changes

## JJ Graph
"""
        log_path.write_text(template)

    return log_path


def append_to_section(section: str, content: str, date: Optional[str] = None):
    """Append content to a specific section in the daily log."""
    log_path = ensure_log_exists(date)
    log_content = log_path.read_text()

    # Find the section
    section_header = f"## {section}"
    if section_header not in log_content:
        # Add section if missing
        log_content = log_content.rstrip() + f"\n\n{section_header}\n\n"

    # Find where to insert (before next section or at end)
    lines = log_content.split("\n")
    insert_idx = None
    in_section = False

    for i, line in enumerate(lines):
        if line.strip() == section_header:
            in_section = True
            continue
        if in_section and line.startswith("## "):
            insert_idx = i
            break

    if insert_idx is None:
        # Append at end
        log_content = log_content.rstrip() + f"\n{content}\n"
    else:
        # Insert before next section
        lines.insert(insert_idx, content)
        log_content = "\n".join(lines)

    log_path.write_text(log_content)
    return log_path


def cmd_session(title: str, content: str = ""):
    """Add a session entry to today's log."""
    time = datetime.now().strftime("%H:%M")
    entry = f"\n### {time} - {title}\n"
    if content:
        entry += f"{content}\n"

    log_path = append_to_section("Sessions", entry)
    print(f"Added session to {log_path}")


def cmd_lesson(lesson_id: str, pattern: str, context: str = ""):
    """Add a lesson entry to today's log."""
    entry = f"- [{lesson_id}] {pattern}"
    if context:
        entry = f"\n{context}\n\n**Lesson:** {entry}"

    log_path = append_to_section("Lessons", entry)
    print(f"Added lesson to {log_path}")


def cmd_jj(change_id: str, message: str, tag: str = ""):
    """Add a jj commit entry to today's log."""
    tag_str = f"[{tag}] " if tag else ""
    entry = f"- `{change_id}` {tag_str}{message}"

    log_path = append_to_section("JJ Changes", entry)
    print(f"Added jj change to {log_path}")


def cmd_jj_graph():
    """Dump current jj graph to today's log."""
    try:
        # Get jj log (last 10 commits)
        result = subprocess.run(
            ["jj", "log", "-r", "::@", "-n", "10"],
            capture_output=True,
            text=True,
            cwd=VAULT_DIR.parent  # Run from repo root
        )
        graph = result.stdout.strip()
    except Exception as e:
        graph = f"Error getting jj graph: {e}"

    log_path = ensure_log_exists()
    log_content = log_path.read_text()

    # Replace JJ Graph section content
    section_header = "## JJ Graph"
    if section_header in log_content:
        # Find and replace section content
        lines = log_content.split("\n")
        new_lines = []
        in_section = False
        section_replaced = False

        for line in lines:
            if line.strip() == section_header:
                in_section = True
                new_lines.append(line)
                new_lines.append("")
                new_lines.append("```")
                new_lines.append(graph)
                new_lines.append("```")
                section_replaced = True
                continue
            if in_section and line.startswith("## "):
                in_section = False
            if not in_section:
                new_lines.append(line)

        log_content = "\n".join(new_lines)
    else:
        log_content += f"\n{section_header}\n\n```\n{graph}\n```\n"

    log_path.write_text(log_content)
    print(f"Updated jj graph in {log_path}")


def cmd_show(date: Optional[str] = None):
    """Show today's (or specified date's) log."""
    log_path = get_log_path(date)
    if log_path.exists():
        print(log_path.read_text())
    else:
        print(f"No log for {date or get_today()}")


def cmd_list(n: int = 7):
    """List recent daily logs."""
    if not LOGS_DIR.exists():
        print("No logs yet.")
        return

    logs = sorted(LOGS_DIR.glob("*.md"), reverse=True)[:n]
    if not logs:
        print("No logs yet.")
        return

    print(f"Recent logs ({len(logs)}):")
    for log in logs:
        # Count sections with content
        content = log.read_text()
        sessions = content.count("### ")
        lessons = len(re.findall(r"- \[L?\d+\]", content))
        jj = content.count("- `")
        print(f"  {log.stem}  ({sessions} sessions, {lessons} lessons, {jj} jj)")


def cmd_search(query: str, lessons_only: bool = False):
    """Search across all daily logs."""
    if not LOGS_DIR.exists():
        print("No logs yet.")
        return

    query_lower = query.lower()
    results = []

    for log_path in sorted(LOGS_DIR.glob("*.md"), reverse=True):
        content = log_path.read_text()

        if lessons_only:
            # Only search lesson lines
            for line in content.split("\n"):
                if re.match(r"- \[L?\d+\]", line) and query_lower in line.lower():
                    results.append((log_path.stem, line.strip()))
        else:
            # Search all content
            for i, line in enumerate(content.split("\n")):
                if query_lower in line.lower():
                    results.append((log_path.stem, line.strip()))

    if not results:
        print(f"No matches for '{query}'")
        return

    print(f"Found {len(results)} matches:")
    for date, line in results[:20]:  # Limit output
        print(f"  [{date}] {line[:70]}...")


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Daily log management")
    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # session
    session_p = subparsers.add_parser("session", help="Add session entry")
    session_p.add_argument("title", help="Session title")
    session_p.add_argument("--content", "-c", default="", help="Session content")

    # lesson
    lesson_p = subparsers.add_parser("lesson", help="Add lesson entry")
    lesson_p.add_argument("id", help="Lesson ID (e.g., L001)")
    lesson_p.add_argument("pattern", help="WHEN->DO->BECAUSE pattern")
    lesson_p.add_argument("--context", "-c", default="", help="Context for the lesson")

    # jj
    jj_p = subparsers.add_parser("jj", help="Add jj commit entry")
    jj_p.add_argument("change_id", help="jj change ID")
    jj_p.add_argument("message", help="Commit message")
    jj_p.add_argument("--tag", "-t", default="", help="Progress tag (e.g., decision, execution)")

    # jj-graph
    subparsers.add_parser("jj-graph", help="Dump jj graph to log")

    # show
    show_p = subparsers.add_parser("show", help="Show daily log")
    show_p.add_argument("date", nargs="?", help="Date (YYYY-MM-DD), default today")

    # list
    list_p = subparsers.add_parser("list", help="List recent logs")
    list_p.add_argument("-n", type=int, default=7, help="Number of logs to show")

    # search
    search_p = subparsers.add_parser("search", help="Search logs")
    search_p.add_argument("query", help="Search query")
    search_p.add_argument("--lessons", "-l", action="store_true", help="Search lessons only")

    args = parser.parse_args()

    if args.command == "session":
        cmd_session(args.title, args.content)
    elif args.command == "lesson":
        cmd_lesson(args.id, args.pattern, args.context)
    elif args.command == "jj":
        cmd_jj(args.change_id, args.message, args.tag)
    elif args.command == "jj-graph":
        cmd_jj_graph()
    elif args.command == "show":
        cmd_show(args.date)
    elif args.command == "list":
        cmd_list(args.n)
    elif args.command == "search":
        cmd_search(args.query, args.lessons)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
