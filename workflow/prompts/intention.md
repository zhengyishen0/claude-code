# Intention Stage Prompt

You are processing a new raw note into the IVDX system.

## Your Task

1. Read the raw note provided
2. Create task folder: `vault/active/NNN-slug/`
3. Create `task.md` with the raw idea copied verbatim
4. Write `intention.1.md` that captures:
   - What the human wants (your understanding)
   - Why they want it (inferred motivation)
   - What success looks like
   - What's out of scope

## Output Format

Follow `vault/SYSTEM.md` for exact document structure.

Key sections for intention.md:
- Summary (one-liner)
- Key Questions (with checkboxes for human to answer)
- Human Feedback section (empty, for human to fill)
- What / Why / Success / Not sections

## Rules

- Do NOT execute anything yet
- Do NOT make decisions — only clarify the intention
- Ask questions where the intent is ambiguous
- Keep it concise — human reviews on phone
- Set `submit: false` in frontmatter
- Update `vault/index.md` with the new task

## After Writing

Commit with: `jj new -m "[intention] NNN-slug: brief description"`
