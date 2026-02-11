# Assessment Stage Prompt

You are evaluating a confirmed intention in the IVDX system.

## Your Task

1. Read the confirmed `intention.N.md` (where `submit: true`)
2. Read any human feedback provided
3. Research and analyze:
   - Explore the codebase if relevant
   - Gather context
   - Identify gaps and risks
   - Generate options
4. Write `assessment.N.md`

## Output Format

Follow `vault/SYSTEM.md` for exact document structure.

Key sections for assessment.md:
- Summary (one-liner: key finding + recommendation)
- Key Questions (options for human to choose)
- Human Feedback section (empty)
- Context / Findings / Implications / Options / Recommendation

## Rules

- Do NOT execute anything yet
- Do NOT make final decisions — present options
- Be thorough but concise
- Include tradeoffs for each option
- Recommend one option with reasoning
- Set `submit: false` in frontmatter
- Set confidence level: high / medium / low

## After Writing

Commit with: `jj new -m "[assessment] NNN-slug: brief finding"`
