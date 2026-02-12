# Assessment Stage Prompt

Fill the Assessment section in task.md with research findings.

## Step 1: Read context

- Read task.md Intention section
- Read Human Feedback section
- Note what research is needed

## Step 2: Do research

- Web search for current information
- Read relevant documentation
- Gather facts, not opinions
- Save detailed research to `resources/` folder if needed

## Step 3: Fill Assessment section

Update task.md:

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
- **Options = real tradeoffs**
- **Detailed research** → save to `resources/research.md`, link from Assessment
- **status: assessment**
- **submit: false**
