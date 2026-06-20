# Skills Draft — Staging Area

Drafted from best-practice patterns extracted from a Scala/ZIO hexagonal-architecture project.
**Not installed.** Copy to `~/.claude/skills/` after review + pressure-testing.

> ⚠️ All skills are in DRAFT state: authored without TDD baseline runs.
> Before installing, each needs a pressure-test with a subagent (see superpowers:writing-skills).

---

## Language-Agnostic

| Skill | Purpose |
|-------|---------|
| [hexagonal-feature-layout](hexagonal-feature-layout/SKILL.md) | domain/app/infra/presentation layering rules, what belongs where |
| [module-separation](module-separation/SKILL.md) | physical build-module split for hexagonal architecture; compiler-enforced layer rules |
| [layers-to-modules](layers-to-modules/SKILL.md) | deciding how many modules one layer maps to; Operations vs Workflows split analysis; naming conventions |
| [domain-operations-and-workflows](domain-operations-and-workflows/SKILL.md) | pure Domain Operation vs. effectful Domain Workflow, `R`/`E` discipline, testing litmus test |
| [composition-root](composition-root/SKILL.md) | single wiring point for all adapters; concrete types named nowhere else |
| [usecase-command](usecase-command/SKILL.md) | Command object + abstract UseCase handler; presentation stays TX-agnostic |
| [domain-value-objects](domain-value-objects/SKILL.md) | VO with internal validation, typed error boundary, layer-pure types |
| [per-feature-sql-migrations](per-feature-sql-migrations/SKILL.md) | Sqitch per-bounded-context, numbered migrations, pgTAP tests |
| [endpoint-contract-separation](endpoint-contract-separation/SKILL.md) | OpenAPI endpoint definition separate from route handler |
| [static-data-memory-adapter](static-data-memory-adapter/SKILL.md) | In-memory adapter for static/read-only data, avoids DB overhead |

## Scala-Specific

| Skill | Purpose |
|-------|---------|
| [mill-module-layout](mill-module-layout/SKILL.md) | Mill `build.mill` idioms for the module-separation layout; `moduleDeps`, test sub-modules, base traits |
| [scala3-tx-parameterized-repository](scala3-tx-parameterized-repository/SKILL.md) | `Repository[TX <: TransactionContext]` with `using ctx: TX` context params |
| [module-i18n](module-i18n/SKILL.md) | `private[pkg] given translationResolver`, `t"..."` interpolator per layer |

## ZIO-Specific

| Skill | Purpose |
|-------|---------|
| [zio-layer-composition](zio-layer-composition/SKILL.md) | `>>>` / `++` layer grammar, `fromFunction` vs `fromZIO`, composition root graph |
| [zio-http-feature-adapter](zio-http-feature-adapter/SKILL.md) | `XxxZioHttp` + `XxxEndpoints`, `routesPublic`/`routesAuth` split |
| [zio-http-endpoint](zio-http-endpoint/SKILL.md) | individual `Endpoint[...]` definition, DTOs + Schema, domain→HTTP error mapping, middleware context |
| [zio-pg-jdbc-wrappers](zio-pg-jdbc-wrappers/SKILL.md) | `pgSelectMany`/`pgInsertOne`/… with `ZIO.scoped`, `using ctx`, `mapThrowable` |
| [zio-prelude-domain-patterns](zio-prelude-domain-patterns/SKILL.md) | `Validation` vs `Either`, `Subtype`/`Newtype` refinement, `Equal`/`Ord` for domain types |

---

## Install

```bash
# Install as plugin (skills namespaced hexagonal-scala-zio-best-practices:<skill-name>)
claude plugin install ~/s4y/skills-draft

# Install single skill manually (legacy, no namespace)
cp -r ~/s4y/skills-draft/skills/<skill-name> ~/.claude/skills/
```
