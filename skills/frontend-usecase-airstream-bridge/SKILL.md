---
name: frontend-usecase-airstream-bridge
description: Use when a Scala.js frontend use case must turn a ZIO effect into an Airstream Signal/EventStream for Laminar UI, when choosing between an imperative Var + fire-and-forget launch, a one-shot fromFuture signal, or an EventBus + flatMapSwitch reactive pipeline, or when deciding whether launching a ZIO fiber per UI event is too expensive
tags: [scala, scalajs, zio, airstream, frontend]
---

# Frontend Use Case: ZIO → Airstream Bridge

**Scope:** Scala.js frontend, ZIO 2.x effects, Airstream `Signal`/`EventStream`/`Var`, Laminar UI. Frontend use cases are NOT the backend `UseCase[C]`/Command pattern ([[usecase-command]]) — no Command objects, no TX, no ZLayer registration; they are classes owning UI state that bridge effects into signals.

## Overview

The frontend has no single ZIO runtime entry point the way `ZIOAppDefault.run` gives the backend one — see [[composition-root]]. DOM events (clicks, mount, input) each start a *new* root effect. A single shared `Runtime[Any]` (built once in the composition root, passed as `given`) launches every one of them. Launching a fiber onto an existing runtime is cheap (fiber alloc + microtask enqueue) — the expensive thing would be rebuilding the `Runtime` per call, which nothing here does. So the boundary between imperative DOM-event world and ZIO is unavoidable; only its shape is a choice.

The use case's `E` channel must already be folded to `Nothing` before crossing the bridge — every ZIO effect exposed to Laminar is `UIO[A]`, its failures already turned into a state value.

## Three Bridge Shapes

### A — Imperative `Var` + fire-and-forget launch

```scala
package s4y.vocabla.frontend

import zio.{Runtime, UIO, Unsafe}

object ZioBridge:
  def run(effect: UIO[Unit])(using runtime: Runtime[Any]): Unit =
    Unsafe.unsafe { implicit unsafe =>
      val _ = runtime.unsafe.runToFuture(effect)
    }
```

```scala
final class LoadLanguagesUseCase(gateway: LanguagesGateway)(using Runtime[Any]):
  private val _state: Var[State] = Var(State.Loading)
  val state: Signal[State] = _state.signal

  def reload(): Unit =
    _state.set(State.Loading)
    ZioBridge.run(
      gateway.getLanguages.fold(
        failure => _state.set(State.Failed(failure.toString)),
        result => _state.set(State.Loaded(result))
      )
    )

  reload()
```

Use case owns a `Var`, writes to it from inside the effect, exposes the read-only `.signal`. Simplest shape; each call site is one `ZioBridge.run(...)`.

### B — One-shot `Signal` via `EventStream.fromFuture`

```scala
package s4y.vocabla.frontend

import com.raquo.airstream.core.EventStream
import zio.{Runtime, UIO, Unsafe}

import scala.concurrent.ExecutionContext

extension [A](effect: UIO[A])
  def toEventStream(using runtime: Runtime[Any], ec: ExecutionContext): EventStream[A] =
    EventStream.fromFuture(
      Unsafe.unsafe { implicit unsafe => runtime.unsafe.runToFuture(effect) }
    )
```

`EventStream.fromFuture` needs an `ExecutionContext` to register `Future#onComplete` — put one `given` in the composition root, not an `import ... global` at every call site:

```scala
// composition root (Main.scala)
import scala.scalajs.concurrent.JSExecutionContext

given Runtime[Any] = Runtime.default
given ExecutionContext = JSExecutionContext.queue   // microtask-based, not global's macrotask
```

```scala
val state: Signal[State] =
  gateway.getLanguages
    .fold(f => State.Failed(f.toString), State.Loaded(_))
    .toEventStream
    .startWith(State.Loading)
```

No `Var`. Fetch-once-on-construction collapses to a one-liner. **`fromFuture` is eager** — the future starts the moment `.toEventStream` runs, i.e. at construction time here. Fine for "load on mount"; wrong if you expected the stream to be lazy per-subscriber.

### C — `EventBus` + `flatMapSwitch` for repeatable triggers

```scala
val reload = new EventBus[Unit]

val state: Signal[State] =
  reload.events
    .startWith(())                          // fire once on mount
    .flatMapSwitch { _ =>
      gateway.getLanguages
        .fold(f => State.Failed(f.toString), State.Loaded(_))
        .toEventStream
        .startWith(State.Loading)
    }
    .toSignal(State.Loading)

// wiring: onClick.mapToUnit --> reload.writer
```

Each `reload.events` emission rebuilds the inner effect from scratch (so `toEventStream` is called fresh, launching a new future). `flatMapSwitch` drops the previous inner stream when a new one arrives — last-trigger-wins for what the UI *sees*.

## Decision Table

| Shape | Use when | Cost |
|-------|----------|------|
| A — `Var` + `ZioBridge.run` | Imperative command dispatch (button calls a method); state changes come from multiple independent code paths, not just one fetch | Explicit `set` calls, easy to reason about and unit-test directly against the `Var` |
| B — `fromFuture` + `startWith` | Fetch-once-on-mount, no re-trigger needed; want to kill boilerplate `Var` | Eager: constructing the stream launches the fiber immediately |
| C — `EventBus` + `flatMapSwitch` | Repeatable trigger (reload button, search-as-you-type) where only the latest result matters | One `EventBus` + composition per use case; more moving parts than A |

## Common Mistakes

**Forgetting the `ExecutionContext` for shape B/C.** `EventStream.fromFuture` fails to compile without one in scope (`Cannot find an implicit ExecutionContext`). Don't reach for `scala.concurrent.ExecutionContext.Implicits.global` per call site — define one `given ExecutionContext = JSExecutionContext.queue` in the composition root alongside `given Runtime[Any]`, same lifetime, same place.

**Bridging a non-`UIO` effect.** `ZioBridge.run` and `toEventStream` both require `E = Nothing`. If a call site still has a real error channel, fold it (`.fold` / `.catchAll`) *before* the bridge, not after — the whole point is that nothing can be lost by launching fire-and-forget.

**Assuming `flatMapSwitch` interrupts the ZIO fiber.** It only detaches the *stream* — the previous ZIO effect (e.g. an in-flight HTTP GET) keeps running to completion in the background; its result is just discarded. Harmless for idempotent GETs. If a stale request must actually stop (e.g. a mutating call), keep the `Fiber` from `runtime.unsafe.fork` and `interrupt` it explicitly instead of relying on Airstream to cancel anything.

**Rebuilding a `Runtime` per call site.** The cost concern people reach for ("is bridging expensive?") is almost always this, not the `runToFuture` call itself. One `Runtime[Any]` built in the composition root ([[composition-root]]), threaded as a `using` parameter everywhere, is enough — see `Main.scala`'s `given Runtime[Any] = Runtime.default`.

**Reaching for `Var` out of habit when B or C would drop it.** A `Var` that only ever gets written from one `.fold` call and read from one `.signal` is a sign shape B fits — no mutable state needed at all.

## Related

- [[composition-root]] — where the single shared `Runtime[Any]` is constructed
- [[client-gateway-port]] — the `IO[InfraFailure, A]` gateway effects that get folded and bridged here
- [[usecase-command]] — backend equivalent boundary (`UseCase[C]`); frontend use cases follow the same "presentation depends on an abstraction, not the concrete effect" spirit, adapted for Airstream instead of a ZIO route
