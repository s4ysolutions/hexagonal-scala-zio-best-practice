# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Claude Code plugin (`hexagonal-scala-zio-best-practices`) for Scala/ZIO hexagonal-architecture projects.

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
- `metadata.tags` — searchable labels (array, under the `metadata` key)

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
  ↓ specializes for identity
domain-identity-types          ← ID type shape; Identified[Id, E]; carry/resolve/construct
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

Scaffolding entry point:
```
create-usecase                 ← end-to-end walkthrough; drives the spines above when adding a use case
```

Frontend spine (Scala.js — a separate hexagon, NOT the backend patterns):
```
client-gateway-port            ← driven port + HTTP adapter; no TX parameter
  ↓ consumed by
frontend-usecase-airstream-bridge ← frontend use case: ZIO effect → Airstream Signal
```
Backend and frontend use cases are totally different concepts. Backend: Command + `UseCase[C]`, TX, ZLayer (`usecase-command`). Frontend: class owning UI state, folds `E` to `Nothing`, bridges into Airstream (`frontend-usecase-airstream-bridge`). Never apply one skill's rules to the other side.

## Critical Architecture Invariants

These cross-skill rules are the most commonly violated — verify them when editing any skill:

1. **`feature.domain` is ZIO-free** — port interfaces (which return `ZIO[...]`) and domain workflows live in `feature.domain.workflows`, not `feature.domain`. `feature.domain` depends on zio-prelude only.

2. **Concrete infra types named only at the composition root** — no other module imports `PostgresRepo`, `TransactionContextPg`, etc. This rule is owned by `composition-root`; other skills cross-reference it rather than restate it.

3. **"Domain service" is a retired term** — everything is either an Operation (pure, no effect type) or a Workflow (ZIO[R, E, A], R = domain port only). No skill should use the term "domain service."

4. **`provide` is banned for layer wiring** — explicit `>>>` / `++` only. The one exception: local `.provide(ZLayer.succeed(x))` wrapping an already-constructed value. Rule owned by `zio-layer-composition`.

5. **No `Dto` suffix on DTO class names** — zio-http uses the class name as the OpenAPI component name; the suffix leaks into the public spec. Name the DTO after the domain concept, let the package qualify it, alias imports where both are in scope. Rule owned by `endpoint-contract-separation`.

## Rule Ownership

Each cross-skill rule has one owner skill that states it in full; every other skill cross-references, never restates:

| Rule | Owner |
|------|-------|
| Module-by-module dependency lists | `module-separation` |
| domain / domain.workflows split decision | `layers-to-modules` |
| Shape 1 / Shape 2 layer wiring (`makeLayer` / `bundledLayer`) | `zio-layer-composition` |
| Shape A / Shape B workflow (static fn vs ZIO service) | `domain-operations-and-workflows` |
| Concrete types only at composition root | `composition-root` |
| `provide` ban + its exception | `zio-layer-composition` |
| DTO naming (no `Dto` suffix) | `endpoint-contract-separation` |
| ID type shape + where the ID lives (`Identified` vs field) | `domain-identity-types` |

## Editing Skills

When revising a skill, check:
- Does the `description` trigger on the prompts a user would actually type?
- Does the skill cross-reference rather than restate rules owned by another skill?
- Are code examples consistent with the ZIO 2.x / Scala 3 / Mill 1.x stack?
- Does the skill avoid the retired term "domain service"?

## Install

Add marketplace to `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "hexagonal-scala-zio-best-practice": {
      "source": { "source": "github", "repo": "s4ysolutions/hexagonal-scala-zio-best-practice" }
    }
  }
}
```

```bash
claude plugin install hexagonal-scala-zio-best-practices@hexagonal-scala-zio-best-practice --scope project
```
