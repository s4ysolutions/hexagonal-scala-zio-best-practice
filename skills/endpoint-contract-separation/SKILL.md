---
name: endpoint-contract-separation
description: Use when building HTTP APIs with OpenAPI generation, when a route handler is growing schema definitions, or when endpoint metadata and handler logic are mixed in the same function
tags: [http, openapi, architecture, language-agnostic]
---

# Endpoint Contract Separation

**Scope:** language-agnostic, HTTP API pattern

## Overview

An **endpoint** is the OpenAPI contract: path, method, input type, output type, error type. A **route** is the handler implementation. They are defined in separate functions / objects and joined only at the composition point.

## Structure

```
Languages.endpoint(prefix)         ← contract: types + path + docs
Languages.route(endpoint, useCase) ← implementation: calls use case, maps DTO

// joined at the HTTP orchestrator or composition root
endpoint = Languages.endpoint(prefix)
routes ++ Languages.route(endpoint, ucGetLanguages)
openAPI = OpenAPIGen.fromEndpoints(..., endpoint, ...)
```

## Endpoint Object

```scala
// All schema/type information lives here
def endpoint(prefix: PathCodec[Unit]): GetLanguagesEndpoint =
  Endpoint(GET / prefix / "languages")
    .tag("Vocabla")
    .out[GetLanguagesResponseDto]
    .outError[InternalServerError500](Status.InternalServerError)
```

## Route Function

```scala
// Implementation only — no type declarations
def route(endpoint: GetLanguagesEndpoint,
          useCase: UseCase[GetLanguagesCommand]): Route[Any, Response] =
  endpoint.implement { _ =>
    useCase(new GetLanguagesCommand())
      .map { r => GetLanguagesResponseDto(...) }
      .mapError { case InfraFailure(_,_) => InternalServerError500("...") }
  }
```

## Why Separate

| Concern | Endpoint | Route |
|---------|----------|-------|
| OpenAPI generation | ✅ passes endpoint to OpenAPIGen | ❌ |
| Type safety | ✅ typed in/out/error slots | ✅ implementation checked against contract |
| Middleware | ✅ auth type declared on endpoint | ✅ implementation called in orchestrator (composition root) |
| Testability | independent contract test | independent handler test |

Endpoints are **named, typed values** that the HTTP orchestrator can thread through both OpenAPI generation and route binding — impossible if the contract is embedded inside the handler.

## Common Mistakes

**Defining the schema inside `.implement { ... }`** — the handler lambda becomes unreadable and the endpoint cannot be passed to OpenAPI gen separately.

**Endpoints as anonymous values** — giving endpoints named types (`type GetLanguagesEndpoint = Endpoint[...]`) lets the orchestrator store and pass them by name.

**Route calls repository directly** — the route maps HTTP ↔ command; business calls go through the use case.

> ⚠️ TESTING PENDING — not pressure-tested yet. Install only after review.
