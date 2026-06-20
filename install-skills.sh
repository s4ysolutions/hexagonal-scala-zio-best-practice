#!/usr/bin/env bash
set -euo pipefail

SKILLS_SRC="$HOME/s4y/skills-draft"
SKILLS_DST=".claude/skills"

mkdir -p "$SKILLS_DST"

for skill_dir in "$SKILLS_SRC"/*/; do
  skill_file="$skill_dir/SKILL.md"
  if [[ -f "$skill_file" ]]; then
    skill_name="$(basename "$skill_dir")"
    cp -r "$skill_dir" "$SKILLS_DST/$skill_name"
    echo "installed: $skill_name"
  fi
done

echo "done → $(pwd)/$SKILLS_DST"
