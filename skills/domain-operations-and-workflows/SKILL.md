---
name: domain-operations-and-workflows
description: Use when deciding whether a piece of logic is pure or effectful, when a piece of domain logic ends up needing a mock or stub to test, when a domain workflow's R pulls in an infrastructure type instead of a domain port, or when choosing between a static function object and a ZIO service class for a workflow
tags: [architecture, domain-modeling, language-agnostic]
---

# Domain Operations and Workflows

**Scope:** language-agnostic in principle; R/E discipline below is ZIO-concrete

## Overview

"Domain service" is retired as a term — it was doing double duty for both pure
rules and I/O-touching logic, which is what causes domain layers to either
fake purity (effects smuggled in as hidden dependencies) or collapse into the
application layer (business rules smashed across boundaries, per Domain
Modeling Made Functional's workflow style). Split it in two:

- **Domain Operation** — pure. No effect type in the signature, not even a
  "pure" one like `UIO`. Takes value objects/entities in, returns a value
  object/entity or a domain error out.
- **Domain Workflow** — effectful. `ZIO[R, E, A]`. Composes Operations with
  Ports. This is what an "effectful domain service" (e.g. a deposit rule that
  must read a rate before applying it) actually is.

See `domain-value-objects` for VO construction rules and `hexagonal-feature-layout`
for where each of these lives on disk and which imports are allowed.
For Operation-layer construction helpers (`Validation`, `Newtype`/`Subtype`,
`Equal`/`Ord`), see `zio-prelude-domain-patterns`.

## Naming

Suffix objects with `Operations` for pure logic, `Workflows` for effectful:

| Object | Bucket | Signal |
|--------|--------|--------|
| `AuthorizationOperations` | Operation | pure, no effect type |
| `TranslatorOperations` | Operation | pure, no effect type |
| `AuthorizeWorkflows` | Workflow | returns `ZIO[...]` |
| `TranslatorWorkflows` | Workflow | returns `ZIO[...]` |

The suffix makes the bucket visible from the name alone — no need to read signatures. `grep *Workflows` finds all effectful domain logic; `grep *Operations` finds all pure logic.

## Core Rules

**Domain Operation has no mutable or effectful state — dependencies are pure values.**
An Operation may live as a top-level function, a companion/module object method, or
a method on a class whose constructor holds only pure values (sealed enums, config
constants, pure function types). What it must never hold is mutable state or anything
that requires I/O to produce.

When an Operation needs a policy or lookup table, prefer passing it as an explicit
parameter and applying partially at the composition root — this keeps the function
composable in a pipeline without threading hidden context:

```scala
// policy as explicit parameter — partial application at the composition root
def applyDiscount(policy: DiscountPolicy)(price: Money, code: DiscountCode): Either[PricingError, Money] = ...

// composition root
val applyCompanyDiscount: (Money, DiscountCode) => Either[PricingError, Money] =
  applyDiscount(CompanyDiscountPolicy)
```

`R` on a `ZIO` is the functional-DI mechanism for the *effectful* case (Workflows);
explicit parameters + partial application is the functional-DI for the *pure* case (Operations).

**Domain Operation has zero effect-type imports** — no `zio.ZIO`, `zio.Task`,
`zio.UIO`, no `cats.effect.IO`. `zio.prelude.*` is allowed: it is algebra and
data structures, not an effect system, so it doesn't violate the boundary.

```scala
// Operation: pure top-level function, no effect type, no injected state
def applyDiscount(price: Money, code: DiscountCode): Either[PricingError, Money] = ...
```

**Domain Workflow's `R` is restricted to `Any` or another domain port**
— never an infra type directly (`DataSource`, `SttpBackend`, a JDBC type).
This is the port-placement invariant made mechanical: if a workflow calls a
port, the port is declared in the domain, and `R` names that domain-declared
type — never the infra type that implements it later.

```scala
// Workflow: R names a domain port, not an infra type
trait RateLookup:
  def currentRate(currency: Currency): IO[RateLookupError, ExchangeRate]

def convert(amount: Money, target: Currency): ZIO[RateLookup, ConversionError, Money] = ...
```

Composing two workflows unions their `R` automatically — a workflow that
calls another workflow ends up with `R` = the union of both workflows'
ports, never wider. Concrete infra implementations of the port traits are
provided only at the composition root, exactly as `zio-layer-composition`
already requires.

**Domain Workflow's `E` is the sealed domain error hierarchy plus `InfraFailure`.**
Raw `Throwable` is banned. `InfraFailure` (declared in `core.domain.errors`)
is allowed and expected — adapters convert raw exceptions into it before crossing the port
boundary, so above the port the error is typed and the workflow can reason about it normally.
`E` may be a single type or a union (`InfraFailure | DomainError`).

**The testing litmus test** — if testing a piece of domain logic requires a
mock, stub, or `ZLayer.succeed(...)`, it is a Workflow, not an Operation. An
Operation is tested by calling it directly with literal inputs. Reaching for
a double on something believed to be "just a domain service" is the signal
that an effect was smuggled in; re-type it as a Workflow with the relevant
port showing up in `R` rather than wiring a double around it.

## Checklist

- [ ] Operation constructor (if any) holds only pure values — no ports, no services, no effectful dependencies
- [ ] Operation dependencies (policies, lookup tables, config) are explicit parameters, composed via partial application
- [ ] No `zio.ZIO`/`zio.Task`/effect-type import in anything called an Operation
- [ ] Every Workflow's `R` is `Any` or a domain port type — never an infra type
- [ ] Every Workflow's `E` is a sealed domain error type or `InfraFailure` — never raw `Throwable`
- [ ] Nothing named "domain service" remains — it's either an Operation or a Workflow
- [ ] No mock/stub needed to test anything classified as an Operation

## Common Mistakes

**Calling a Workflow a "domain service"** — the term hides which bucket the
thing is in and invites exactly the confusion this skill exists to resolve.
Name it Operation or Workflow.

**`R` widened to an infra type "just for now"** — `ZIO[DataSource, ...]` in a
domain workflow is the port-placement invariant broken in the type signature
itself. Declare the port trait in the domain even if, today, there's only
one implementation.

**Reaching for `F[_]: MonadError[F, DomainError]` to "stay framework-agnostic"**
— if every other layer in the codebase is already ZIO-committed (composition
root, HTTP adapter, repository wrappers), this buys portability you will
never use at the cost of tagless-final ceremony on every signature and worse
error-handling ergonomics than ZIO's native `mapError`/`catchAll`. Stay
concrete unless multiple effect runtimes are a real, near-term requirement.

**Operation class holding a mutable or effectful dependency** — `class PricingService(repo: PricingRepository)` smuggles a port into an Operation. The fix: make it a Workflow with `repo` in `R`, not an Operation with `repo` in the constructor. A class holding a *pure value* (a `DiscountPolicy` enum, a `Map[Code, Rate]` loaded once at startup) is fine — the test: can the constructor parameter be constructed without any `ZIO`, `Future`, or I/O? If yes, it is a pure value and the class is a valid Operation carrier.

**Mocking a pure function instead of re-typing it** — if a "domain service"
needs a `ZLayer` to be testable, the fix is not a better mock, it's
recognizing the thing has a port dependency and belongs in the Workflow
bucket with that port in `R`.

**Extracting workflow logic into a trait to enable test stubbing** — if a
function calling a driven port is wrapped in a trait so callers can inject a
stub, the stub sits at the wrong level. The driven port (`UsageRepository`,
`TranslationGateway`, etc.) is already the test seam — stub that. A trait
with one implementation and no infra variation is indirection with no payoff;
collapse it to a static function in an object.

```scala
// WRONG — trait wraps one driven port, exists only for stubbing
trait AuthorizeService[TX <: TransactionContext]:
  def authorize(ctx: AuthorizeContext)(using TX): IO[InfraFailure, AuthorizeResult]

object AuthorizeService:
  def makeLive[TX <: TransactionContext: Tag](repo: UsageRepository[TX]) =
    new AuthorizeService[TX]:
      def authorize(ctx: AuthorizeContext)(using TX) =
        Authorization.isUserSuper(ctx.userId).toZIO.orElse(
          repo.used(ctx.userId, ctx.provider, QuotaPeriod.Hour(1)).map(Authorization.enoughQuota)
        )

// caller holds both the repo AND the service wrapping the same repo — duplication
class TranslatorService[TX](usageRepository: UsageRepository[TX], authorizeService: AuthorizeService[TX], ...)

// CORRECT — static function; fails on Denied so callers can use *> instead of flatMap
object AuthorizeWorkflows:
  def authorize[TX <: TransactionContext](
      ctx: AuthorizeContext,
      usageRepository: UsageRepository[TX]
  )(using TX): IO[InfraFailure | AuthorizeResult.Denied, Unit] =
    AuthorizationOperations.isUserSuper(ctx.userId).toZIO.orElse(
      usageRepository.used(ctx.userId, ctx.provider, QuotaPeriod.Hour(1))
        .map(AuthorizationOperations.enoughQuota)
    ).flatMap(_.toZIO).unit

// caller uses *> — no flatMap, no wrapping of Denied into a caller-owned error type
object TranslatorWorkflows:
  def translate[TX <: TransactionContext](...): IO[TranslationError | InfraFailure | AuthorizeResult.Denied, TranslationResponse] =
    transactionManager.transaction("authorize") {
      AuthorizeWorkflows.authorize(ctx, usageRepository)
    } *> gateway.translate(request)
```

Return type `IO[InfraFailure | AuthorizeResult.Denied, Unit]` keeps `Denied` as a
distinct error kind rather than wrapping it into a caller-owned type
(`TranslationError.Unauthorized`). The presentation layer sees three separate error
types and can map each to the correct HTTP status independently — no pattern-matching
inside a wrapper enum.

Test seam is `UsageRepository[TX]` — stub it with an in-memory implementation to
exercise both `Authorized` and `Denied` paths. Stubbing `AuthorizeService` instead
would test `TranslatorService`'s pattern-match in isolation, missing the actual
authorization logic.

## Static Function vs ZIO Service for Workflows

When implementing a domain workflow, choose one of two shapes before writing code:

**Shape A — static function object (explicit deps)**

```scala
object TranslatorWorkflows:
  def translate[TX <: TransactionContext](
      userId: ..., request: ...,
      gateways: TranslationGateways,
      usageRepository: UsageRepository[TX],
      transactionManager: TransactionManager[TX]
  ): IO[TranslationError | InfraFailure | AuthorizeResult.Denied, TranslationResponse]
```

Every caller supplies all deps. New dep = edit every caller.

**Shape B — ZIO service class (hidden deps)**

```scala
class TranslatorWorkflows(gateways: TranslationGateways):
  def translate[TX <: TransactionContext](
      userId: ..., request: ...,
      usageRepository: UsageRepository[TX],
      transactionManager: TransactionManager[TX]
  ): IO[TranslationError | InfraFailure | AuthorizeResult.Denied, TranslationResponse]

object TranslatorWorkflows:
  def layer: ZLayer[TranslationGateways, Nothing, TranslatorWorkflows] =
    ZLayer.fromFunction(new TranslatorWorkflows(_))
```

Non-TX deps hidden in constructor + ZLayer. New non-TX dep = change layer only,
zero callers touched. TX-parameterized deps (`UsageRepository[TX]`,
`TransactionManager[TX]`) cannot be hidden — they stay explicit because the TX type
is chosen at the use-case level, not at the workflow level.

**Decision rule:**

| Situation | Shape |
|-----------|-------|
| One caller today, stable deps | A — refactor cost = 1 edit, indirection buys nothing |
| Multiple callers OR deps likely to grow | B — one layer change protects all callers |
| Wrapper around a single port the caller already holds | A — see "Extracting workflow logic into a trait" mistake below; B adds no value here |

> ⚠️ **Stop and decide.** This choice is not a detail — changing shape later touches every caller (A→B) or requires unwrapping a ZLayer (B→A). Pick deliberately based on caller count and dep volatility, not habit. The developer is responsible for the final call.

## Domain Logic Inside Transaction Boundaries

`TransactionManager.transaction` is an **atomicity boundary**, not an infra-only
wrapper. Domain logic that must be consistent with a subsequent write belongs inside
the same transaction — moving the analysis outside creates a TOCTOU gap (another
transaction can mutate the data between the read and the decision).

```scala
// WRONG — read and update in separate transactions; race condition between them
val count = transactionManager.transaction("read") { repo.used(...) }
count.flatMap { n =>
  if enoughQuota(n) then
    transactionManager.transaction("update") { repo.add(...) }
  else ZIO.fail(Denied(...))
}

// CORRECT — read + conditional update atomic
transactionManager.transaction("authorize and record") {
  repo.used(...).flatMap { n =>
    if enoughQuota(n) then repo.add(...).as(Authorized)
    else ZIO.fail(Denied(...))  // domain error, rolls back
  }
}
```

Because the effect inside can fail with domain errors, `transaction` must be generic
over `E`:

```scala
def transaction[R, E, A](log: String)(
    effect: TX ?=> ZIO[R, InfraFailure | E, A]
): ZIO[R, InfraFailure | E, A]
```

This is the honest type — `InfraFailure` from begin/commit failures, `E` from the
workflow inside. The original restricted signature (`IO[InfraFailure, A]` only)
assumed transaction bodies are pure data fetches, which is too narrow.

**What must NOT go inside a transaction:** long-running I/O — network calls, LLM
requests, external API gateways. These hold a DB connection and lock for the full
duration. Keep transactions to fast, local port calls (DB reads/writes).

