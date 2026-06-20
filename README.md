# hexagonal-scala-zio-best-practices

Claude Code plugin. Architecture skills for **Scala 3 / ZIO 2 / Mill** hexagonal architecture: domain modeling, layer separation, use-case scaffolding, ZIO-HTTP endpoints, TX-parameterized repositories, and composition root wiring.

---

## Install

### Option A — Project scope (recommended)

Add the marketplace to your project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "hexagonal-scala-zio-best-practice": {
      "source": {
        "source": "github",
        "repo": "s4ysolutions/hexagonal-scala-zio-best-practice"
      }
    }
  }
}
```

Then install at project scope:

```bash
claude plugin install hexagonal-scala-zio-best-practices@hexagonal-scala-zio-best-practice --scope project
```

Skills are then available as `hexagonal-scala-zio-best-practices:<skill-name>`.

### Option B — Single skill (manual)

```bash
cp -r skills/<skill-name> ~/.claude/skills/
```

---

## Skills

### Language-Agnostic

| Skill | Purpose |
|-------|---------|
| [hexagonal-feature-layout](skills/hexagonal-feature-layout/SKILL.md) | domain/app/infra/presentation layering rules, what belongs where |
| [module-separation](skills/module-separation/SKILL.md) | physical build-module split for hexagonal architecture; compiler-enforced layer rules |
| [layers-to-modules](skills/layers-to-modules/SKILL.md) | deciding how many modules one layer maps to; Operations vs Workflows split analysis; naming conventions |
| [domain-operations-and-workflows](skills/domain-operations-and-workflows/SKILL.md) | pure Domain Operation vs. effectful Domain Workflow, `R`/`E` discipline, testing litmus test |
| [composition-root](skills/composition-root/SKILL.md) | single wiring point for all adapters; concrete types named nowhere else |
| [usecase-command](skills/usecase-command/SKILL.md) | Command object + abstract UseCase handler; presentation stays TX-agnostic |
| [domain-value-objects](skills/domain-value-objects/SKILL.md) | VO with internal validation, typed error boundary, layer-pure types |
| [per-feature-sql-migrations](skills/per-feature-sql-migrations/SKILL.md) | Sqitch per-bounded-context, numbered migrations, pgTAP tests |
| [endpoint-contract-separation](skills/endpoint-contract-separation/SKILL.md) | OpenAPI endpoint definition separate from route handler |
| [static-data-memory-adapter](skills/static-data-memory-adapter/SKILL.md) | In-memory adapter for static/read-only data, avoids DB overhead |

### Scala-Specific

| Skill | Purpose |
|-------|---------|
| [mill-module-layout](skills/mill-module-layout/SKILL.md) | Mill `build.mill` idioms for the module-separation layout; `moduleDeps`, test sub-modules, base traits |
| [scala3-tx-parameterized-repository](skills/scala3-tx-parameterized-repository/SKILL.md) | `Repository[TX <: TransactionContext]` with `using ctx: TX` context params |
| [module-i18n](skills/module-i18n/SKILL.md) | `private[pkg] given translationResolver`, `t"..."` interpolator per layer |

### ZIO-Specific

| Skill | Purpose |
|-------|---------|
| [zio-layer-composition](skills/zio-layer-composition/SKILL.md) | `>>>` / `++` layer grammar, `fromFunction` vs `fromZIO`, composition root graph |
| [zio-http-feature-adapter](skills/zio-http-feature-adapter/SKILL.md) | `XxxZioHttp` + `XxxEndpoints`, `routesPublic`/`routesAuth` split |
| [zio-http-endpoint](skills/zio-http-endpoint/SKILL.md) | individual `Endpoint[...]` definition, DTOs + Schema, domain→HTTP error mapping, middleware context |
| [zio-pg-jdbc-wrappers](skills/zio-pg-jdbc-wrappers/SKILL.md) | `pgSelectMany`/`pgInsertOne`/… with `ZIO.scoped`, `using ctx`, `mapThrowable` |
| [zio-prelude-domain-patterns](skills/zio-prelude-domain-patterns/SKILL.md) | `Validation` vs `Either`, `Subtype`/`Newtype` refinement, `Equal`/`Ord` for domain types |
