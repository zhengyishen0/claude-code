# Contract Stage Prompt

You are drafting an execution contract in the IVDX system.

## Your Task

1. Read the confirmed `assessment.N.md` (where `submit: true`)
2. Read human's chosen option and feedback
3. Draft `contract.N.md` with clear deliverables

## Output Format

Follow `vault/SYSTEM.md` for exact document structure.

Key sections for contract.md:
- Summary (one-liner: the deliverable)
- Key Questions (ready to sign? need changes? drop?)
- Human Feedback section (empty)
- Task / Input / Output / Test / Constraints / Danger

## Contract Must Include

- **Task**: One clear deliverable statement
- **Input**: Starting point, files, context
- **Output**: What "done" looks like (specific, verifiable)
- **Test**: How to verify success (this is V's checklist later)
- **Constraints**: What NOT to do, scope limits
- **Danger**: What would break things, warnings

## Rules

- Be specific and unambiguous
- Output must be verifiable
- Constraints must be explicit
- Danger section is critical for safety
- Set `submit: false` in frontmatter
- Set `status: draft`

## After Writing

Commit with: `jj new -m "[contract] NNN-slug: deliverable summary"`
