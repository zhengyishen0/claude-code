# Assessment Stage Prompt

Fill the Assessment section in task file with research findings.

## Step 1: Read context

- Read task file Intention section
- Read Human Feedback section
- Note what research is needed

## Step 2: Do research

- Web search for current information
- Read relevant documentation
- Gather facts, not opinions
- Save detailed research to `vault/resources/NNN-slug/` if needed

## Step 3: Fill Assessment section

Update task file:

```markdown
## Assessment

**Oneliner:** [Key finding + recommendation]

**Findings:** [Research results — facts, not fluff]

**Options:**
- Option A: [tradeoff]
- Option B: [tradeoff]

**Recommendation:** [What AI suggests and why]

**Questions:** [Only if human needs to decide, otherwise "None — recommendation is clear"]
```

## Step 4: Update frontmatter

```yaml
status: assessment
submit: false
```

## Rules

- **Findings = facts** from research
- **Detailed research** → save to `vault/resources/NNN-slug/research.md`
- **status: assessment**
- **submit: false**
