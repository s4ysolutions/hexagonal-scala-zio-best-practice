---
name: mill-module-layout
description: Use when setting up or extending a Mill build for a hexagonal/clean-architecture Scala project, when asked to create or scaffold a new Mill module (e.g. features.myFeature.infra.pg or features.myFeature.domain), when deciding how to declare moduleDeps for a new module, when adding a test sub-module in Mill, or when wiring a new bounded context into an existing Mill build
tags: [mill, scala, build-tool, architecture]
---

# Mill Module Layout for Hexagonal Architecture

**Scope:** Mill build tool (tested with Mill 1.x), Scala 3

## Overview

Mill's nested `object` model maps directly onto the `core / features / products`
module grouping from `module-separation`. Each Mill object is one build module;
`moduleDeps` is the only place where inter-module dependencies are declared,
making it the compile-time enforcer of layer rules.

See `module-separation` for the build-system-agnostic layout and dependency
rules. This skill covers the Mill-specific idioms for expressing them.

## Base Traits

Define shared settings once; every module mixes in the right trait:

```scala
trait BaseModule extends ScalaModule {
  def scalaVersion = "3.x.y"
  // shared compiler flags, common dep helpers
  override def scalacOptions = super.scalacOptions() ++ Seq(
    "-unchecked", "-deprecation", "-Xsemanticdb"
  )
}

trait BaseJvmModule extends BaseModule {
  // JVM-only deps (JDBC driver, HikariCP, …) declared here
}

trait BaseJsModule extends BaseModule with ScalaJSModule {
  // Scala.js settings
}
```

All production modules extend `BaseJvmModule` (or `BaseModule` for
cross-platform). Test sub-modules extend the appropriate `TestModule.*` mixin
instead — they do not extend the base traits directly.

## Top-Level Structure in `build.mill`

```scala
package build

object core    extends Module { ... }
object features extends Module { ... }
object products extends Module { ... }
```

`Module` (not `ScalaModule`) is used for grouping objects that are not
themselves compilable — only their children are. This prevents accidentally
running `mill core.compile` when you mean `mill core.app.compile`.

## Core Module Declaration

```scala
object core extends Module {

  object i18n extends BaseJvmModule { ... }

  object identity extends BaseModule {        // cross-platform: no JVM-only deps
    override def mvnDeps = Seq(zioDep, preludeDep)
  }

  object app extends BaseJvmModule {
    override def moduleDeps = Seq(core.i18n)
    override def mvnDeps = Seq(zioDep)
  }

  object tx extends BaseJvmModule {
    override def moduleDeps = Seq(core.identity)
    override def mvnDeps = Seq(zioDep)         // ZIO needed: TransactionManager is a ZIO service
  }

  object domain extends Module {
    object errors extends BaseModule { ... }   // InfraFailure; NO zioDep — pure domain imports this
  }

  object infra extends Module {
    object pg extends BaseJvmModule {
      override def moduleDeps = Seq(
        core.identity,
        core.tx,
        core.domain.errors
      )
      // test sub-module nested inside infra.pg
      object tests extends ScalaTests with TestModule.ZioTest {
        override def moduleDeps =
          Seq(core.infra.pg, core.loggers, core.tests)
        override def mvnDeps = Seq(zioTestDep, zioTestSbtDep)
      }
    }
    object memory extends BaseJvmModule {
      override def moduleDeps = Seq(
        core.identity,
        core.tx,
        core.domain.errors
      )
    }
  }

  object presentation extends Module {
    object zioHttp extends BaseJvmModule {
      override def moduleDeps = Seq(core.app)
      override def mvnDeps = Seq(zioDep, zioHttpDep)
    }
  }

  object loggers extends BaseJvmModule { ... }

  object tests extends BaseModule {           // shared test helpers only
    override def moduleDeps = Seq(core.tx)
    override def mvnDeps = Seq(zioTestDep, zioTestSbtDep, dotenvDep)
  }
}
```

## Feature Module Declaration

Each bounded context follows the same pattern. The names `domain`, `app`,
`infra`, `presentation` are fixed; sub-names under `infra` and `presentation`
reflect the technology (`pg`, `memory`, `zioHttp`, `llm`, …).

The `domain` object is a ScalaModule (has its own sources) AND a parent for
the `workflows` sub-module. Both can coexist in Mill: the parent compiles its
own sources; the nested object compiles its own separately.

```scala
object features extends Module {
  object myFeature extends Module {

    // feature.domain — pure: VOs, errors, operations; zio-prelude only, NO ZIO
    object domain extends BaseModule {
      override def moduleDeps = Seq(
        core.i18n,
        core.identity,
        core.domain.errors
        // + other feature pure domains if needed, e.g. features.auth.domain
      )
      override def mvnDeps = Seq(preludeDep)  // NO zioDep here

      object munits extends ScalaTests with TestModule.Munit {
        override def moduleDeps = Seq(domain)
        override def mvnDeps = Seq(munitDep)
      }

      // feature.domain.workflows — effectful: port interfaces, domain workflows; ZIO
      object workflows extends BaseJvmModule {
        override def moduleDeps = Seq(
          domain,                              // VOs and errors used in port signatures
          core.domain.errors,
          core.tx
        )
        override def mvnDeps = Seq(zioDep)

        object tests extends ScalaTests with TestModule.ZioTest {
          override def moduleDeps = Seq(workflows)
          override def mvnDeps = Seq(zioTestDep, zioTestSbtDep)
        }
      }
    }

    object app extends BaseJvmModule {
      override def moduleDeps = Seq(
        core.i18n,
        core.app,
        myFeature.domain,           // for VOs, errors
        myFeature.domain.workflows  // for port interfaces to call
      )
      override def mvnDeps = Seq(zioDep)
      // No dep on myFeature.infra.* or myFeature.presentation.*
    }

    object infra extends Module {
      object pg extends BaseJvmModule {
        override def moduleDeps = Seq(
          myFeature.domain.workflows,  // port interfaces to implement
          core.infra.pg
        )
        override def mvnDeps = Seq(zioDep)

        object tests extends ScalaTests with TestModule.ZioTest {
          override def moduleDeps =
            Seq(pg, core.infra.pg.tests, core.loggers)
          override def mvnDeps = Seq(zioTestDep, zioTestSbtDep, dotenvDep)
        }
      }
      object memory extends BaseJvmModule {
        override def moduleDeps = Seq(
          myFeature.domain.workflows,  // port interfaces to implement
          core.infra.memory
        )
        override def mvnDeps = Seq(zioDep)
      }
    }

    object presentation extends Module {
      object zioHttp extends BaseJvmModule {
        override def moduleDeps = Seq(
          myFeature.domain,           // for VOs, DTO mapping
          myFeature.app,
          core.presentation.zioHttp
        )
        override def mvnDeps = Seq(zioDep, zioHttpDep)

        object munits extends ScalaTests with TestModule.Munit {
          override def moduleDeps = Seq(zioHttp)
          override def mvnDeps = Seq(munitDep)
        }
        object tests extends ScalaTests with TestModule.ZioTest {
          override def moduleDeps = Seq(zioHttp)
          override def mvnDeps = Seq(zioTestDep, zioTestSbtDep)
        }
      }
    }
  }
}
```

## Product (Composition Root) Module

```scala
object products extends Module {
  object myService extends BaseJvmModule {
    override def mainClass = Some("com.example.myservice.cli.Main")

    override def moduleDeps = Seq(
      core.app,
      core.loggers,
      core.i18n,
      core.infra.memory,
      core.infra.pg,
      core.presentation.zioHttp,
      features.myFeature.infra.pg,
      features.myFeature.infra.memory,
      features.myFeature.app,
      features.myFeature.presentation.zioHttp,
      // ... all other features
    )

    override def mvnDeps = Seq(zioDep, zioConfigDep, zioHttpDep)
  }
}
```

This is the **only** module that references every concrete infra and
presentation module. Its source code is the composition root (TX type aliases,
ZLayer assembly, `main` entry point).

## Test Sub-Module Conventions

| Test type | Mill mixin | When to use |
|-----------|-----------|-------------|
| Pure / fast | `ScalaTests with TestModule.Munit` | Domain VOs, pure functions, endpoint contract shape |
| Effect-runtime | `ScalaTests with TestModule.ZioTest` | Workflows, use cases, integration |
| Integration (DB) | `ScalaTests with TestModule.ZioTest` + `dotenvDep` | Infra adapters needing a live DB |

Test modules are always **nested inside** their parent production module object,
not placed alongside it. This keeps `mill myFeature.domain.tests.test` scoped
to that module's own tests.

## Running Tests

```bash
# all tests in a module
mill features.myFeature.domain.tests.test
mill features.myFeature.infra.pg.tests.test

# all tests in a feature
mill __.test                    # every test sub-module in the project
mill features.myFeature.__.test # every test sub-module under myFeature

# compile-check without running
mill features.myFeature.domain.compile
```

## Common Mistakes

**Extending `ScalaModule` instead of `Module` for grouping objects** — a
grouping object (one that contains sub-modules but has no source files of its
own) should extend `Module`, not `ScalaModule`; extending `ScalaModule` adds
a spurious compile target with an empty source set.

**Declaring `mvnDeps` on a grouping `Module`** — dependencies belong on the
leaf `ScalaModule`, not on the parent `Module` wrapper.

**Test module depending on production modules of sibling features** — a
feature's test module may depend on `core.tests` and `core.loggers` but not
on another feature's production modules; share fixtures via `core.tests`.

**Putting the test sub-module alongside rather than inside the production
module** — Mill resolves `moduleDeps` references by the Scala object path;
nesting test inside production (`object tests extends ScalaTests` inside
`object domain`) keeps paths like `domain.tests` instead of a flat
`domainTests`.

**Duplicating dep lists instead of using `private val`** — when a module and
its test sub-module share the same `mvnDeps`, extract to a `private val` in
the parent `extends Module` block and reference it in both.

**Adding `zioDep` to `feature.domain`** — `feature.domain` must be ZIO-free; port
interfaces (which return `ZIO[...]`) belong in `feature.domain.workflows`. If ZIO
appears in `feature.domain.mvnDeps`, move the offending file to the `workflows` sub-module.

**Infra or app depending on `myFeature.domain` only** — if a module implements or calls
port interfaces, it must declare `myFeature.domain.workflows` in `moduleDeps`. A dep on
`myFeature.domain` alone is missing the port interface definitions.

> ⚠️ TESTING PENDING — not pressure-tested yet. Install only after review.
