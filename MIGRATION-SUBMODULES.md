# Submodule Migration Plan

Convert each skill into a separate private GitHub repo, managed as git submodules.

## Overview

```
Before:
~/.claude/skills/
├── browser/     # All in one repo
├── memory/
└── ...

After:
~/.claude-code/skills/
├── browser/     → github.com/zhengyi/skill-browser (submodule)
├── memory/      → github.com/zhengyi/skill-memory (submodule)
└── ...
```

## Skills to Migrate (16 total)

| # | Skill | Repo Name | Has Data? |
|---|-------|-----------|-----------|
| 1 | browser | skill-browser | Yes - move to data/ |
| 2 | cli | skill-cli | No |
| 3 | daily | skill-daily | No |
| 4 | diagnose | skill-diagnose | No |
| 5 | feishu | skill-feishu | No (creds in ~/.config) |
| 6 | google | skill-google | No (creds in ~/.config) |
| 7 | jj | skill-jj | No |
| 8 | lesson | skill-lesson | No |
| 9 | md2pdf | skill-md2pdf | No |
| 10 | memory | skill-memory | Yes - move to data/ |
| 11 | proxy | skill-proxy | No |
| 12 | screenshot | skill-screenshot | No |
| 13 | vault | skill-vault | No |
| 14 | watchers | skill-watchers | No |
| 15 | wechat | skill-wechat | No |
| 16 | yt-transcript | skill-yt-transcript | No |

## Prerequisites

- [ ] Complete data migration (see MIGRATION-DATA.md)
- [ ] Ensure no secrets in skill folders
- [ ] GitHub CLI authenticated (`gh auth status`)

## Step 1: Create GitHub Repos

```bash
# Create all 16 private repos
for skill in browser cli daily diagnose feishu google jj lesson md2pdf memory proxy screenshot vault watchers wechat yt-transcript; do
  gh repo create "skill-$skill" --private --description "Claude Code skill: $skill"
done
```

## Step 2: Initialize Each Skill as Repo

For each skill:

```bash
SKILL="browser"  # repeat for each skill

cd ~/.claude-code/skills/$SKILL

# Initialize git
git init
git add .
git commit -m "Initial commit"

# Add remote and push
git remote add origin git@github.com:zhengyi/skill-$SKILL.git
git branch -M main
git push -u origin main

cd ..
```

Or as a batch script:

```bash
cd ~/.claude-code/skills

for skill in browser cli daily diagnose feishu google jj lesson md2pdf memory proxy screenshot vault watchers wechat yt-transcript; do
  echo "=== Processing $skill ==="
  cd $skill

  git init
  git add .
  git commit -m "Initial commit"
  git remote add origin git@github.com:zhengyi/skill-$skill.git
  git branch -M main
  git push -u origin main

  cd ..
done
```

## Step 3: Convert to Submodules

From the main project:

```bash
cd ~/.claude-code

# Remove the skill folders (keep backup first)
cp -r skills skills.bak

for skill in browser cli daily diagnose feishu google jj lesson md2pdf memory proxy screenshot vault watchers wechat yt-transcript; do
  rm -rf skills/$skill
  git submodule add git@github.com:zhengyi/skill-$skill.git skills/$skill
done

# Commit the submodule configuration
git add .gitmodules skills/
git commit -m "Convert skills to submodules"
```

## Step 4: Add .gitignore to Each Skill Repo

Each skill repo should have:

```gitignore
# Runtime data (lives in ~/.claude-code/data/)
data/
profiles/
cache/

# Node
node_modules/

# Python
__pycache__/
*.pyc
.venv/

# OS
.DS_Store

# IDE
.idea/
.vscode/
```

## Post-Migration Workflow

### Clone Project with Skills

```bash
git clone --recurse-submodules git@github.com:zhengyi/claude-code.git
```

### Pull Updates

```bash
# Update main project
git pull

# Update all submodules to latest
git submodule update --remote --merge
```

### Edit a Skill

```bash
cd ~/.claude-code/skills/browser

# Make changes
git add .
git commit -m "Fix: something"
git push

# Update parent reference
cd ~/.claude-code
git add skills/browser
git commit -m "Update browser skill"
```

### Add New Skill

```bash
# Create repo first
gh repo create skill-newskill --private

# Add as submodule
git submodule add git@github.com:zhengyi/skill-newskill.git skills/newskill
```

## Rollback Plan

If something goes wrong:

```bash
# Restore from backup
rm -rf skills
mv skills.bak skills

# Or reset submodules
git submodule deinit -f skills/
rm -rf .git/modules/skills
git rm -rf skills/
```

## Verification Checklist

- [ ] All 16 repos created on GitHub
- [ ] All skills pushed with full history
- [ ] Submodules configured in .gitmodules
- [ ] Clone test: `git clone --recurse-submodules` works
- [ ] Skills still load in Claude Code
- [ ] No secrets committed
