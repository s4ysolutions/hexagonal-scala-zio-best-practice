---
name: client-gateway-port
description: Use when a Scala.js frontend needs to call a backend HTTP endpoint and turn the response into domain objects, when designing the frontend half of a hexagon, or when deciding whether a client-side data-fetch abstraction needs a transaction parameter
tags: [scala, scalajs, architecture, http, frontend]
---

# Client Gateway Port (Frontend Hexagon)

**Scope:** Scala 3 + Scala.js frontend consuming a ZIO-HTTP backend via a shared contract module

## Overview

The frontend is a hexagon too. It has driven ports (fetch data from the backend) and driven adapters (implement the fetch over HTTP). The shape mirrors a server-side repository port, with one structural difference: **no transaction context**. The client never manages a DB transaction, so the TX type parameter from [[scala3-tx-parameterized-repository]] is absent — the port is a plain effectful interface.

## When to Use

- Frontend (`*Js` module) needs data currently only reachable via a backend REST endpoint
- An existing shared contract module (see [[endpoint-contract-separation]]) already defines the DTOs both sides use
- Deciding where frontend fetch/decode code belongs relative to domain and contract modules

Do NOT use for server-to-server calls (that's a regular repository/gateway port, TX-parameterized if it touches persistence) or for UI state management (Laminar signals, component wiring — out of scope).

## Module Layout

```
features.X.client            — port only, depends on domain.domainJs (+ core.domain.errors)
features.X.client.http       — HTTP adapter, depends on client + contracts.http.httpJs + core.http.gateway
```

Both are `BaseJsModule`. The port module stays adapter-agnostic — swapping HTTP for a mock or a different transport means adding a new adapter module, not touching `client`.

## Core Pattern

```scala
// features.X.client — the port
package s4y.vocabla.client

import s4y.repositories.errors.InfraFailure
import s4y.vocabla.domain.vo.Lang
import zio.IO

final case class GetLanguages(
    defaultLang: Lang,
    unknownLang: Lang,
    languages: List[Lang]
)

trait LanguagesGateway:
  def getLanguages: IO[InfraFailure, GetLanguages]
```

```scala
// features.X.client.http — the adapter
package s4y.vocabla.client.http

import s4y.http.gateway.HttpGateway
import s4y.vocabla.contracts.http.LanguagesContract
import s4y.vocabla.contracts.http.LanguagesContract.GetLanguagesResponse as GetLanguagesResponseDto
import zio.schema.codec.JsonCodec
import zio.{IO, ZIO}

final class LanguagesGatewayHttp(gateway: HttpGateway) extends LanguagesGateway:
  private val path = "/" + LanguagesContract.pathSegments.mkString("/")

  def getLanguages: IO[InfraFailure, GetLanguages] =
    gateway.getJson(path)                 // IO[InfraFailure | HttpError, String]
      .mapError(toInfraFailure)           // collapse union -> single client-facing error
      .flatMap(decode)                    // JSON -> DTO via shared Schema
      .map(toModel)                       // DTO -> domain, via contract's fromDomain/toDomain
```

## Rules

- **No TX parameter.** The client never threads a transaction; if a "port" ends up needing one, it has drifted into being a repository, not a client gateway.
- **Path segments live on the contract, not the adapter.** `LanguagesContract.pathSegments` is the single source of truth for the route; server (`Endpoint`) and client (`LanguagesGatewayHttp`) both derive from it so they cannot drift independently.
- **Error collapse happens at the adapter boundary.** `HttpGateway.getJson` returns a union (`InfraFailure | HttpError`); the port's return type is the single domain-facing `InfraFailure`. Map the union down inside the adapter — don't leak transport error types past `client.http`.
- **Decode via the contract's `Schema`, not a hand-rolled parser.** `JsonCodec.jsonCodec(schema).decodeJson(body)` using the `given Schema[Dto]` already derived on the contract DTO (see [[endpoint-contract-separation]]).
- **Map DTO to domain at the edge.** `Contract.Lang.toDomain(dto)` — the client module never returns raw DTOs to callers, same rule as the server route never leaking raw domain types outward.

## Common Mistakes

**TX parameter added "for consistency" with server repositories** — client has no transaction to parameterize over; adding one just adds unused generic noise. Leave it off.

**Adapter returns the transport union error directly** — callers (UI code) end up pattern-matching on `HttpError` cases that only make sense at the HTTP layer. Collapse to `InfraFailure` inside the adapter.

**Port module depends on `contracts.http` directly** — the port should only know about domain types (`Lang`, `GetLanguages`); only the adapter module should depend on the wire contract. Keeps the port swappable to a non-HTTP adapter later.

**Decoding without the shared `Schema`** — writing manual JSON decoding in the adapter duplicates what the contract module already derives, and silently drifts from the server's encoding when the DTO changes.
