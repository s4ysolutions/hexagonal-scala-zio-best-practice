---
name: layers-to-modules
description: Use when deciding how many build modules a single hexagonal layer should map to, when asked to create a new domain sub-module (e.g. domain.operations or domain.workflows), when a domain module pulls in ZIO and you want to know if that is correct, or when naming sub-modules within a layer
tags: [architecture, language-agnostic, build-system-agnostic]
---

# Mapping Hexagonal Layers to Build Modules

**Scope:** language-agnostic, build-system-agnostic

## Overview

The hexagonal layer map (`hexagonal-feature-layout`) is a *logical* structure.
Build modules are a *physical* enforcement mechanism (`module-separation`).
They do not have to be 1-to-1. A layer can be one module, or split into
several — the right choice depends on whether sub-parts of that layer have
genuinely different dependency surfaces. This skill gives the decision rules.

For the dependency rules (which module may import which) see `module-separation`.
For the wiring rule (concrete types named only at the composition root) see `composition-root`.

## The Core Principle

**Split a layer into multiple modules only when the parts have different
dependency surfaces that matter.** "Different" means: one part pulls in a
library or another module that the other part must not see, and that
restriction has a concrete benefit (cross-platform compatibility, smaller
classpaths, enforced purity, faster incremental compilation).

Splitting for organizational reasons alone (files feel cleaner in separate
directories) is not sufficient — use packages/directories within one module
instead.

## Layer-by-Layer Analysis

### `domain` layer

The domain layer splits into **two modules** with genuinely different dependency surfaces:

| Concern | Module | Deps |
|---------|--------|------|
| VOs, domain errors, operations | `feature.domain` | plain Scala, zio-prelude; **no ZIO effect runtime** |
| Port interfaces (repositories, gateways), domain workflows | `feature.domain.workflows` | ZIO + `feature.domain` |

**This split is the default, not a special case.**

`feature.domain` must never acquire the ZIO effect runtime — the compiler enforces this at the module level. Port interfaces return `ZIO[...]`, so they cannot live in `feature.domain`. They belong in `feature.domain.workflows`, alongside the domain workflows that call them.

```
feature.domain           ← VOs, errors, operations; zio-prelude only
feature.domain.workflows ← port interfaces, domain workflows; ZIO + depends on domain
```

`feature.domain.workflows` depends on `feature.domain` (for VOs and error types used
in port signatures). Every other layer that needs port interfaces depends on
`feature.domain.workflows`, not on `feature.domain` alone.

### `app` layer

Typically one module: `feature.app`. It depends on `feature.domain.workflows`
(for port interfaces to call) and `core.app`. Must not depend on any infra or
presentation module.

Split `app` into multiple modules only if different use-case groups need
genuinely different external libraries (rare). In practice, `feature.app`
stays as one module.

### `infra` layer

Always split by *technology*, not by feature concern:

```
feature.infra.pg       ← PostgreSQL adapter; deps: feature.domain.workflows, core.infra.pg
feature.infra.memory   ← in-memory adapter; deps: feature.domain.workflows, core.infra.memory
feature.infra.llm      ← LLM gateway; deps: feature.domain.workflows, HTTP client libs
feature.infra.s3       ← file storage adapter; deps: feature.domain.workflows, S3 client
```

Each infra sub-module depends on `feature.domain.workflows` (not `feature.domain` alone)
because it must see the port interfaces it implements. Infra sub-modules must **not**
depend on each other.

### `presentation` layer

Split by *framework*, not by route group:

```
feature.presentation.zioHttp   ← all HTTP routes for this feature
feature.presentation.cli       ← CLI entry point (if it exists)
```

Do not split `presentation.zioHttp` further into per-route sub-modules — that
produces fine-grained modules with almost no dependency-surface difference.
Keep routes as packages/directories within `feature.presentation.zioHttp`.

## Summary Decision Table

| Layer | Default | Split when |
|-------|---------|-----------|
| `domain` | `feature.domain` + `feature.domain.workflows` | always — different dep surfaces (ZIO vs no-ZIO) |
| `app` | one module | genuinely different external lib requirements per use-case group (rare) |
| `infra` | one sub-module per technology | always split by technology; never merge two technologies |
| `presentation` | one sub-module per framework | always split by framework; never split by route group |

## Naming Conventions

| What | Convention | Rationale |
|------|-----------|-----------|
| Domain pure module | `feature.domain` | pure root — VOs, errors, operations |
| Domain effectful sub-module | `feature.domain.workflows` | ports + workflows that use ZIO |
| Infra sub-modules | `feature.infra.<technology>` (`pg`, `memory`, `llm`, `s3`) | technology, not concern |
| Presentation sub-modules | `feature.presentation.<framework>` (`zioHttp`, `cli`) | framework, not route |

Avoid:
- `feature.domain.core` or `feature.domain.pure` — "domain" is already the pure module; adding "core/pure" implies the parent is impure
- `feature.domain.operations` as a module name — operations live inside `feature.domain`, not a sub-module
- `feature.infra.db` — too generic; name the technology (`pg`, `mysql`, `mongo`)
- `feature.presentation.rest` — too generic; name the framework (`zioHttp`, `http4s`, `akkaHttp`)

## Common Mistakes

**`feature.domain` depending on ZIO** — port interfaces return `ZIO[...]` and must live in
`feature.domain.workflows`. Any ZIO import in `feature.domain` violates the purity boundary;
the compiler catches this as a missing module dep if the split is in place.

**Infra or app depending on `feature.domain` instead of `feature.domain.workflows`** — port
interfaces are in `feature.domain.workflows`; a module that implements or calls ports must
declare `feature.domain.workflows` in its `moduleDeps`, not just `feature.domain`.

**One `feature.infra` module containing both PG and memory adapters** — they
have different external dependencies; keeping them together forces every
consumer (including tests) to pull in both.

**Splitting `presentation.zioHttp` by route group** — routes share the same
framework dep and are rarely compiled in isolation; the split produces noise
without benefit. Use packages.

**Naming the effectful sub-module `feature.domain.core`** — "core" implies a more
fundamental module, but it would be the effectful one (ZIO). Use `feature.domain.workflows`.

> ⚠️ TESTING PENDING — not pressure-tested yet. Install only after review.
