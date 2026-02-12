#!/usr/bin/env python3
"""
lesson - Learn behavioral rules from experience.

Pattern: WHEN [context] -> DO [action] -> BECAUSE [reason]
"""

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

# Storage paths
LESSONS_DIR = Path.home() / ".claude" / "lessons"
LESSONS_FILE = LESSONS_DIR / "lessons.jsonl"
INDEX_FILE = LESSONS_DIR / "index.json"

# Pattern regex
PATTERN_RE = re.compile(
    r"WHEN\s+\[?(.+?)\]?\s*->\s*DO\s*(NOT)?\s*\[?(.+?)\]?\s*->\s*BECAUSE\s+\[?(.+?)\]?$",
    re.IGNORECASE
)


def ensure_storage():
    """Ensure storage directory exists."""
    LESSONS_DIR.mkdir(parents=True, exist_ok=True)
    if not LESSONS_FILE.exists():
        LESSONS_FILE.touch()
    if not INDEX_FILE.exists():
        INDEX_FILE.write_text("{}")


def load_index() -> dict:
    """Load the lesson index."""
    ensure_storage()
    try:
        return json.loads(INDEX_FILE.read_text() or "{}")
    except json.JSONDecodeError:
        return {}


def save_index(index: dict):
    """Save the lesson index."""
    INDEX_FILE.write_text(json.dumps(index, indent=2))


def get_next_id(index: dict) -> str:
    """Get next lesson ID."""
    if not index:
        return "001"
    max_id = max(int(k) for k in index.keys() if k.isdigit())
    return f"{max_id + 1:03d}"


def parse_pattern(text: str) -> Optional[dict]:
    """Parse a WHEN->DO->BECAUSE pattern."""
    match = PATTERN_RE.match(text.strip())
    if not match:
        return None

    when, do_not, do, because = match.groups()
    return {
        "when": when.strip(),
        "action": "dont" if do_not else "do",
        "do": do.strip(),
        "because": because.strip(),
    }


def detect_source() -> str:
    """Detect if called by human or AI."""
    # Check if running in Claude Code context
    if os.environ.get("CLAUDE_CODE") or os.environ.get("ANTHROPIC_API_KEY"):
        return "ai"
    # Check if stdin is a TTY (human terminal)
    if sys.stdin.isatty():
        return "user"
    return "ai"


def append_lesson(lesson: dict):
    """Append lesson to JSONL file."""
    ensure_storage()
    with open(LESSONS_FILE, "a") as f:
        f.write(json.dumps(lesson) + "\n")


def get_all_lessons() -> list:
    """Get all lessons from JSONL, latest entry per ID wins."""
    ensure_storage()
    lessons = {}
    if LESSONS_FILE.exists():
        for line in LESSONS_FILE.read_text().strip().split("\n"):
            if line:
                try:
                    lesson = json.loads(line)
                    lessons[lesson["id"]] = lesson
                except json.JSONDecodeError:
                    continue
    return list(lessons.values())


def cmd_add(pattern: str, skill: str = "global"):
    """Add a new lesson."""
    parsed = parse_pattern(pattern)
    if not parsed:
        print("Error: Invalid pattern format.", file=sys.stderr)
        print("Expected: WHEN [context] -> DO [action] -> BECAUSE [reason]", file=sys.stderr)
        sys.exit(1)

    index = load_index()
    lesson_id = get_next_id(index)
    source = detect_source()

    lesson = {
        "id": lesson_id,
        "skill": skill,
        "from": source,
        "status": "active",
        "created": datetime.now().isoformat()[:10],
        **parsed,
    }

    # Update index
    index[lesson_id] = {
        "skill": skill,
        "status": "active",
        "from": source,
    }
    save_index(index)

    # Append to log
    append_lesson(lesson)

    print(f"Added lesson {lesson_id} ({source}): {pattern[:60]}...")


def cmd_list(skill: Optional[str] = None, from_filter: Optional[str] = None,
             show_all: bool = False, global_only: bool = False):
    """List lessons."""
    lessons = get_all_lessons()

    # Filter
    if not show_all:
        lessons = [l for l in lessons if l.get("status") == "active"]
    if skill:
        lessons = [l for l in lessons if l.get("skill") == skill]
    if global_only:
        lessons = [l for l in lessons if l.get("skill") == "global"]
    if from_filter:
        lessons = [l for l in lessons if l.get("from") == from_filter]

    if not lessons:
        print("No lessons found.")
        return

    # Print header
    print(f"{'ID':<5} {'SKILL':<10} {'FROM':<6} PATTERN")
    print("-" * 60)

    for l in sorted(lessons, key=lambda x: x["id"]):
        action = "DO NOT" if l.get("action") == "dont" else "DO"
        pattern = f"WHEN {l['when']} -> {action} {l['do']} -> BECAUSE {l['because']}"
        status = "" if l.get("status") == "active" else f" [{l.get('status')}]"
        print(f"{l['id']:<5} {l.get('skill', 'global'):<10} {l.get('from', '?'):<6} {pattern[:50]}...{status}")


def cmd_show(lesson_id: str):
    """Show lesson details."""
    lessons = get_all_lessons()
    lesson = next((l for l in lessons if l["id"] == lesson_id), None)

    if not lesson:
        print(f"Lesson {lesson_id} not found.", file=sys.stderr)
        sys.exit(1)

    # YAML-like output
    print(f"id: {lesson['id']}")
    print(f"skill: {lesson.get('skill', 'global')}")
    print(f"from: {lesson.get('from', 'unknown')}")
    print(f"status: {lesson.get('status', 'active')}")
    print(f"created: {lesson.get('created', '?')}")
    action = "DO NOT" if lesson.get("action") == "dont" else "DO"
    print(f'pattern: "WHEN {lesson["when"]} -> {action} {lesson["do"]} -> BECAUSE {lesson["because"]}"')
    print("parsed:")
    print(f'  when: "{lesson["when"]}"')
    print(f'  action: {lesson.get("action", "do")}')
    print(f'  do: "{lesson["do"]}"')
    print(f'  because: "{lesson["because"]}"')


def cmd_wrong(lesson_id: str, reason: Optional[str] = None):
    """Mark lesson as incorrect (delete)."""
    index = load_index()

    if lesson_id not in index:
        print(f"Lesson {lesson_id} not found.", file=sys.stderr)
        sys.exit(1)

    # Update index
    index[lesson_id]["status"] = "deleted"
    save_index(index)

    # Append deletion record
    deletion = {
        "id": lesson_id,
        "status": "deleted",
        "updated": datetime.now().isoformat()[:10],
    }
    if reason:
        deletion["reason"] = reason
    append_lesson(deletion)

    print(f"Deleted lesson {lesson_id}" + (f" ({reason})" if reason else ""))


def cmd_promote(lesson_id: str, to_skill: str):
    """Promote lesson to skill's SKILL.md."""
    lessons = get_all_lessons()
    lesson = next((l for l in lessons if l["id"] == lesson_id), None)

    if not lesson:
        print(f"Lesson {lesson_id} not found.", file=sys.stderr)
        sys.exit(1)

    # Find skill's SKILL.md
    skills_dir = Path(__file__).parent.parent
    skill_md = skills_dir / to_skill / "SKILL.md"

    if not skill_md.exists():
        print(f"Skill '{to_skill}' not found at {skill_md}", file=sys.stderr)
        sys.exit(1)

    # Format lesson
    action = "DO NOT" if lesson.get("action") == "dont" else "DO"
    lesson_line = f"- WHEN {lesson['when']} -> {action} {lesson['do']} -> BECAUSE {lesson['because']}"

    # Read current content
    content = skill_md.read_text()

    # Find or create Lessons section
    if "## Lessons" in content:
        # Append to existing section
        lines = content.split("\n")
        for i, line in enumerate(lines):
            if line.strip() == "## Lessons":
                # Find end of section (next ## or end of file)
                j = i + 1
                while j < len(lines) and not lines[j].startswith("## "):
                    j += 1
                # Insert before next section
                lines.insert(j, lesson_line)
                content = "\n".join(lines)
                break
    else:
        # Add new section at end
        content = content.rstrip() + f"\n\n## Lessons\n\n{lesson_line}\n"

    skill_md.write_text(content)

    # Update index
    index = load_index()
    index[lesson_id]["status"] = "promoted"
    index[lesson_id]["promoted_to"] = to_skill
    save_index(index)

    # Append promotion record
    append_lesson({
        "id": lesson_id,
        "status": "promoted",
        "promoted_to": to_skill,
        "updated": datetime.now().isoformat()[:10],
    })

    print(f"Promoted lesson {lesson_id} to {to_skill}/SKILL.md")


def cmd_search(query: str, skill: Optional[str] = None):
    """Search lessons."""
    lessons = get_all_lessons()
    query_lower = query.lower()

    results = []
    for l in lessons:
        if l.get("status") != "active":
            continue
        if skill and l.get("skill") != skill:
            continue

        # Search in pattern fields
        searchable = f"{l.get('when', '')} {l.get('do', '')} {l.get('because', '')}".lower()
        if query_lower in searchable:
            results.append(l)

    if not results:
        print(f"No lessons matching '{query}'")
        return

    print(f"{'ID':<5} {'SKILL':<10} PATTERN")
    for l in results:
        action = "DO NOT" if l.get("action") == "dont" else "DO"
        pattern = f"WHEN {l['when']} -> {action} {l['do']}"
        print(f"{l['id']:<5} {l.get('skill', 'global'):<10} {pattern[:50]}...")


def cmd_load(skill: str):
    """Load lessons for a skill (for embedding in SKILL.md)."""
    lessons = get_all_lessons()

    # Get global + skill-specific lessons
    global_lessons = [l for l in lessons if l.get("skill") == "global" and l.get("status") == "active"]
    skill_lessons = [l for l in lessons if l.get("skill") == skill and l.get("status") == "active"]

    total = len(global_lessons) + len(skill_lessons)
    if total == 0:
        print("No lessons loaded.")
        return

    print(f"## Lessons ({total} active)\n")

    if global_lessons:
        print("### Global")
        for l in global_lessons:
            action = "DO NOT" if l.get("action") == "dont" else "DO"
            src = f"[{l.get('from', '?')}]"
            print(f"- WHEN {l['when']} -> {action} {l['do']} -> BECAUSE {l['because']} {src}")
        print()

    if skill_lessons:
        print(f"### {skill}")
        for l in skill_lessons:
            action = "DO NOT" if l.get("action") == "dont" else "DO"
            src = f"[{l.get('from', '?')}]"
            print(f"- WHEN {l['when']} -> {action} {l['do']} -> BECAUSE {l['because']} {src}")


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Learn behavioral rules from experience")
    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # add
    add_p = subparsers.add_parser("add", help="Add a lesson")
    add_p.add_argument("pattern", help="WHEN->DO->BECAUSE pattern")
    add_p.add_argument("--skill", default="global", help="Skill scope (default: global)")

    # list
    list_p = subparsers.add_parser("list", help="List lessons")
    list_p.add_argument("--skill", help="Filter by skill")
    list_p.add_argument("--from", dest="from_filter", choices=["ai", "user"], help="Filter by source")
    list_p.add_argument("--all", dest="show_all", action="store_true", help="Include deleted/promoted")
    list_p.add_argument("--global", dest="global_only", action="store_true", help="Global lessons only")

    # show
    show_p = subparsers.add_parser("show", help="Show lesson details")
    show_p.add_argument("id", help="Lesson ID")

    # wrong
    wrong_p = subparsers.add_parser("wrong", help="Mark lesson as incorrect")
    wrong_p.add_argument("id", help="Lesson ID")
    wrong_p.add_argument("--reason", help="Reason for deletion")

    # promote
    promote_p = subparsers.add_parser("promote", help="Promote to skill definition")
    promote_p.add_argument("id", help="Lesson ID")
    promote_p.add_argument("--to", required=True, dest="to_skill", help="Target skill")

    # search
    search_p = subparsers.add_parser("search", help="Search lessons")
    search_p.add_argument("query", help="Search query")
    search_p.add_argument("--skill", help="Filter by skill")

    # load
    load_p = subparsers.add_parser("load", help="Load lessons for a skill")
    load_p.add_argument("--skill", required=True, help="Skill name")

    args = parser.parse_args()

    if args.command == "add":
        cmd_add(args.pattern, args.skill)
    elif args.command == "list":
        cmd_list(args.skill, args.from_filter, args.show_all, args.global_only)
    elif args.command == "show":
        cmd_show(args.id)
    elif args.command == "wrong":
        cmd_wrong(args.id, args.reason)
    elif args.command == "promote":
        cmd_promote(args.id, args.to_skill)
    elif args.command == "search":
        cmd_search(args.query, args.skill)
    elif args.command == "load":
        cmd_load(args.skill)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
