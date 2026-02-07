#!/bin/bash
# PostToolUse hook: PDSD stage guidance
# Outputs prompts after jj commits to guide agent through PDSD cycle
#
# Exit code 0 = always allow (this is guidance, not blocking)

set -eo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')

# Only trigger on Bash
if [[ "$tool_name" != "Bash" ]]; then
    exit 0
fi

command=$(echo "$input" | jq -r '.tool_input.command // ""')

# Only trigger on jj new -m or jj describe -m
if [[ ! "$command" =~ jj[[:space:]]+(new|describe)[[:space:]].*-m ]]; then
    exit 0
fi

# Extract commit message
if [[ "$command" =~ -m[[:space:]]+[\"\']([^\"\']+)[\"\'] ]]; then
    commit_msg="${BASH_REMATCH[1]}"
elif [[ "$command" =~ -m[[:space:]]+([^[:space:]]+) ]]; then
    commit_msg="${BASH_REMATCH[1]}"
else
    exit 0
fi

# Extract type
if [[ "$commit_msg" =~ ^\[([a-z]+)\] ]]; then
    commit_type="${BASH_REMATCH[1]}"
else
    exit 0
fi

# Output stage-specific guidance
echo "" >&2

case "$commit_type" in
    "task")
        cat >&2 << 'EOF'
┌─ PDSD: [task] created ─────────────────────────────────────────────┐
│ Next: Create [plan] with your hypothesis                           │
│                                                                     │
│ Your plan should answer:                                            │
│ • What's your hypothesis? (testable prediction)                     │
│ • How will you test it? (specific steps)                            │
│ • What does success look like? (measurable outcome)                 │
└─────────────────────────────────────────────────────────────────────┘
EOF
        ;;
    "plan")
        cat >&2 << 'EOF'
┌─ PDSD: [plan] created ─────────────────────────────────────────────┐
│ Next: Execute with [try]                                            │
│                                                                     │
│ Execution guidelines:                                               │
│ • Independent operations → parallel tool calls                      │
│ • Dependent operations → sequential                                 │
│ • Multiple bash with no deps → chain with &&                        │
│ • Need intermediate output → separate calls                         │
│                                                                     │
│ Create [try] commits as you make progress.                          │
└─────────────────────────────────────────────────────────────────────┘
EOF
        ;;
    "try")
        cat >&2 << 'EOF'
┌─ PDSD: [try] logged ───────────────────────────────────────────────┐
│ Continue executing, or move to [reflect] when ready to analyze.       │
│                                                                     │
│ Move to [reflect] when:                                               │
│ • You have results (success or failure)                             │
│ • You've hit an unexpected obstacle                                 │
│ • You need to reflect before continuing                             │
└─────────────────────────────────────────────────────────────────────┘
EOF
        ;;
    "reflect")
        cat >&2 << 'EOF'
┌─ PDSD: [reflect] - Time to reflect ──────────────────────────────────┐
│                                                                     │
│ Answer these questions:                                             │
│ 1. What worked as expected?                                         │
│ 2. What surprised you?                                              │
│ 3. What's the root cause of any failures?                           │
│ 4. What would you do differently?                                   │
│                                                                     │
│ Then decide:                                                        │
│ • [done]   - Hypothesis confirmed, task complete                    │
│ • [adjust] - Refine approach, same direction (→ new [plan])         │
│ • [pivot]  - Different approach entirely (→ new [plan])             │
│ • [drop]   - Task not feasible, abandon                             │
│                                                                     │
│ Difference between adjust and pivot:                                │
│ • [adjust] = "right direction, needs refinement"                    │
│ • [pivot]  = "wrong direction, try something else"                  │
└─────────────────────────────────────────────────────────────────────┘
EOF
        ;;
    "done")
        cat >&2 << 'EOF'
┌─ PDSD: [done] - Task complete ─────────────────────────────────────┐
│                                                                     │
│ Merge to main:                                                      │
│   cd /path/to/main/repo                                             │
│   jj new main <change-id> -m "[done] description (session-id)"      │
│   jj bookmark set main -r @                                         │
│   jj workspace forget <workspace-name>                              │
│   jj abandon 'heads(all()) ~ @ ~ main ~ immutable()'                │
└─────────────────────────────────────────────────────────────────────┘
EOF
        ;;
    "adjust")
        cat >&2 << 'EOF'
┌─ PDSD: [adjust] - Refining approach ───────────────────────────────┐
│                                                                     │
│ You're staying the course but improving execution.                  │
│                                                                     │
│ Next: Create new [plan] with:                                       │
│ • What specific changes based on learnings?                         │
│ • What will you do differently this time?                           │
│ • How will you know if the refinement worked?                       │
└─────────────────────────────────────────────────────────────────────┘
EOF
        ;;
    "pivot")
        cat >&2 << 'EOF'
┌─ PDSD: [pivot] - Changing direction ───────────────────────────────┐
│                                                                     │
│ Previous approach didn't work. Time for a new hypothesis.           │
│                                                                     │
│ Next: Create new [plan] with:                                       │
│ • What's fundamentally different about this approach?               │
│ • Why do you think this will succeed where the other failed?        │
│ • What can you reuse from the previous attempt?                     │
└─────────────────────────────────────────────────────────────────────┘
EOF
        ;;
    "drop")
        cat >&2 << 'EOF'
┌─ PDSD: [drop] - Task abandoned ────────────────────────────────────┐
│                                                                     │
│ Document why in the commit message for future reference.            │
│                                                                     │
│ Clean up:                                                           │
│   jj workspace forget <workspace-name>                              │
│   # Keep files for reference, or:                                   │
│   rm -rf ../.workspaces/claude-code/<workspace-name>                │
└─────────────────────────────────────────────────────────────────────┘
EOF
        ;;
esac

exit 0
