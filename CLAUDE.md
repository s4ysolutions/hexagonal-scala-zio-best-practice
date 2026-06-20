# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Claude Code plugin (`hexagonal-scala-zio-best-practices`) extracted from a Scala/ZIO hexagonal-architecture project. Skills are drafted here and reviewed before the plugin is installed.

No build system. No runnable code. Each skill is a standalone `SKILL.md` file.

## Skill Structure

Each skill lives under `skills/`:

```
skills/
  <skill-name>/
    SKILL.md   ← the skill; frontmatter + markdown body
```

`SKILL.md` frontmatter fields that matter:
- `name` — machine identifier, must match directory name
- `description` — used by Claude to decide when to invoke this skill; write it as trigger conditions, not a summary
- `tags` — searchable labels

## Skill Relationships

Skills form a dependency graph — many cross-reference each other. Key spine:

```
hexagonal-feature-layout       ← logical layer map (domain/app/infra/presentation)
  ↓ physical enforcement
module-separation              ← build-module split rules (compiler-enforced layer rules)
  ↓ decision logic
layers-to-modules              ← how many modules per layer; domain split default
  ↓ Mill syntax
mill-module-layout             ← build.mill idioms for the module graph
```

Domain model spine:
```
domain-value-objects           ← VOs, typed errors, layer-pure types
  ↓ uses
zio-prelude-domain-patterns    ← Validation vs Either, Subtype/Newtype, Equal/Ord
  ↓ governs
domain-operations-and-workflows ← pure Operation vs effectful Workflow; R/E discipline
```

Wiring spine:
```
composition-root               ← single wiring point; concrete types named nowhere else
  ↓ ZIO expression
zio-layer-composition          ← ZLayer grammar (>>>, ++, fromFunction vs fromZIO)
  ↓ use case boundary
usecase-command                ← Command + UseCase[C] abstraction; TX-agnostic presentation
```

## Critical Architecture Invariants

These cross-skill rules are the most commonly violated — verify them when editing any skill:

1. **`feature.domain` is ZIO-free** — port interfaces (which return `ZIO[...]`) and domain workflows live in `feature.domain.workflows`, not `feature.domain`. `feature.domain` depends on zio-prelude only.

2. **Concrete infra types named only at the composition root** — no other module imports `PostgresRepo`, `TransactionContextPg`, etc. This rule is owned by `composition-root`; other skills cross-reference it rather than restate it.

3. **"Domain service" is a retired term** — everything is either an Operation (pure, no effect type) or a Workflow (ZIO[R, E, A], R = domain port only). No skill should use the term "domain service."

## Editing Skills

When revising a skill, check:
- Does the `description` trigger on the prompts a user would actually type?
- Does the skill cross-reference rather than restate rules owned by another skill?
- Are code examples consistent with the ZIO 2.x / Scala 3 / Mill 1.x stack?
- Does the skill avoid the retired term "domain service"?

All skills carry `⚠️ TESTING PENDING` until pressure-tested with a subagent.

## Install

```bash
# Install plugin (all skills namespaced as hexagonal-scala-zio-best-practices:<skill-name>)
claude plugin install ~/s4y/skills-draft

# Install single skill manually (legacy)
cp -r ~/s4y/skills-draft/skills/<skill-name> ~/.claude/skills/
```
