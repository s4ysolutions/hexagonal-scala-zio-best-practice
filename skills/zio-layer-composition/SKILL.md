---
name: zio-layer-composition
description: Use when wiring ZIO ZLayer graphs, when a layer fails to compile due to missing dependencies, when deciding between ZLayer.fromFunction and ZLayer.fromZIO, or when a layer is being assembled in the wrong module
tags: [zio, scala, dependency-injection]
---

# ZIO Layer Composition

**Scope:** ZIO 2.x specific

## Overview

`ZLayer` is ZIO's dependency injection mechanism. Layers are assembled bottom-up at the composition root using `>>>` (sequential) and `++` (parallel/additive). Construction logic goes in the layer; business logic goes in the service.

## Core Grammar

```scala
// Sequential: A provides B's dependency
val bLayer: ZLayer[Any, E, B] = aLayer >>> ZLayer { ... }

// Additive: A and B have no dependency on each other
val abLayer: ZLayer[Any, E, A & B] = aLayer ++ bLayer

// Feeding: aLayer + bLayer together provide C's dependencies
val cLayer: ZLayer[Any, E, C] =
  (aLayer ++ bLayer) >>> ZLayer.fromZIO { ... }
```

## `fromFunction` vs `fromZIO`

| Use | When |
|-----|------|
| `ZLayer.fromFunction(MyService(_))` | Constructor takes only services from env — pure, no effects |
| `ZLayer.fromZIO { ZIO.serviceWith[...] { ... } }` | Construction requires an effectful step (e.g., reading config, opening a pool) |

Prefer `fromFunction` — it signals pure construction and is more readable. Use `fromZIO` only when the constructor itself has effects.

## Layer Graph at Composition Root

```scala
// infra layers (bottom)
val pgDataSourceLayer: Layer[InfraFailure, DataSource] = ...
val txManagerLayer: Layer[InfraFailure, TransactionManager[TXDB]] =
  pgDataSourceLayer >>> TransactionManagerPg.layer

// repo (infra) + use case (app) layers (middle)
val usersRepoLayer: ULayer[UsersRepository[TXDB]] = UsersRepositoryPg.layer
val registerUserLayer: Layer[InfraFailure, UseCase[RegisterCommand]] =
  (txManagerLayer ++ usersRepoLayer) >>> RegisterUserUseCase.makeLayer[TXDB]

// presentation layers (top)
val httpLayer: Layer[InfraFailure, MyZioHttp] =
  registerUserLayer >>> MyZioHttp.layer
```

## `makeLayer` Companion Convention

Each service exposes a `makeLayer` (or `layer`) in its companion object. The layer's input type documents the service's dependencies:

```scala
object RegisterUserUseCase:
  def makeLayer[TX <: TransactionContext: zio.Tag]
      : URLayer[TransactionManager[TX] & UsersRepository[TX],
                UseCase[RegisterCommand]] =
    ZLayer.fromFunction(new RegisterUserUseCase[TX](_, _))
```

## Memoization

ZIO memoizes layers by default — if two downstream layers depend on the same layer, it is built once and shared. This is almost always correct.

Use `.fresh` to opt out:

```scala
myApp.provideLayer(sharedLayer.fresh ++ otherLayer)  // sharedLayer built fresh for each consumer
```

Common trap: two connection pools collapsing to one because the pool layer is shared. If you need distinct instances, `.fresh`.

## `ZLayer.derive`

For simple constructors (case class or trait with constructor params), `ZLayer.derive` replaces hand-written `fromFunction`:

```scala
case class MyService(repo: UsersRepository[TXDB], tm: TransactionManager[TXDB])

object MyService:
  val layer: URLayer[UsersRepository[TXDB] & TransactionManager[TXDB], MyService] =
    ZLayer.derive[MyService]
```

Use when the constructor is a straightforward field injection. Use `fromFunction` / `fromZIO` when there's custom construction logic.

## Rules (additions)

**Never use `provide` for layer wiring.** `provide` auto-resolves the dependency graph by type — if two layers satisfy the same type, the selection is implicit and the error appears far from the source. Always wire explicitly with `>>>` (sequential) and `++` (additive); the graph is then visible in code and any missing dependency is a compile error at the exact wiring site.

```scala
// WRONG — auto-wiring, silent ambiguity risk
myApp.provide(useCaseLayer, repoLayer, txManagerLayer, dataSourceLayer)

// CORRECT — explicit graph
val appLayer =
  (dataSourceLayer >>> txManagerLayer ++ repoLayer) >>> useCaseLayer
myApp.provideLayer(appLayer)
```

## Wiring Shapes

Two valid shapes. Choose by how many products share the same use case.

**Shape 1 — thin use case, wiring at composition root.**
Use case `makeLayer` declares its deps; product wires the full graph.

```scala
// use case companion — declares deps only
object RegisterUserUseCase:
  def makeLayer[TX: zio.Tag]
      : URLayer[TransactionManager[TX] & UsersRepository[TX], UseCase[RegisterCommand]] =
    ZLayer.fromFunction(new RegisterUserUseCase[TX](_, _))

// product (composition root) — wires the full graph
val appLayer: Layer[InfraFailure, UseCase[RegisterCommand]] =
  (txManagerLayer ++ UsersRepositoryPg.layer) >>> RegisterUserUseCase.makeLayer[TXDB]
```

Default choice. Simple, all wiring visible in one place.

**Shape 2 — use case companion owns the wiring structure.**
Companion bundles the internal graph pattern; infra layers are still passed from outside.
Reduces duplication when multiple products share the same use case.

```scala
// use case companion — owns wiring structure, infra layers are params
object RegisterUserUseCase:
  def makeLayer[TX: zio.Tag]
      : URLayer[TransactionManager[TX] & UsersRepository[TX], UseCase[RegisterCommand]] =
    ZLayer.fromFunction(new RegisterUserUseCase[TX](_, _))

  def bundledLayer[TX: zio.Tag](
      repoLayer: URLayer[Any, UsersRepository[TX]]   // caller supplies concrete infra
  ): URLayer[TransactionManager[TX], UseCase[RegisterCommand]] =
    (ZLayer.service[TransactionManager[TX]] ++ repoLayer) >>> makeLayer[TX]

// product A — concrete infra named here only
val appLayerA: Layer[InfraFailure, UseCase[RegisterCommand]] =
  txManagerLayer >>> RegisterUserUseCase.bundledLayer(UsersRepositoryPg.layer)

// product B (e.g. test harness) — different infra, same structure
val appLayerB =
  memTxManagerLayer >>> RegisterUserUseCase.bundledLayer(UsersRepositoryMemory.layer)
```

Invariant preserved: concrete infra classes (`UsersRepositoryPg`, `UsersRepositoryMemory`) named only at the product call site, not inside the companion.

## Common Mistakes

**Layer contains business logic** — `ZLayer.fromZIO { ... businessDecision ... }` — extraction belongs in a service method, not a layer factory.

**Services constructed with `new` outside any layer factory** — bypasses the DI graph; a dependency is now invisible to the compiler. Using `new` *inside* `ZLayer.fromFunction(new MyService(_))` is correct and expected.

**`>>>` with incompatible types** — compiler error means the right-hand layer has a requirement the left-hand layer does not provide; check the `R` type of the downstream layer.

**`provide` / `provideSomeLayer` anywhere** — `provide` is banned. `provideSomeLayer` inside a use case is doubly wrong: use cases must not self-wire, and auto-resolution hides dependency bugs. Use explicit `>>>` / `++` at the composition root only.

> ⚠️ TESTING PENDING — not pressure-tested yet. Install only after review.
