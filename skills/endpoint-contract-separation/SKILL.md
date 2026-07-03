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
    .out[GetLanguagesResponse]
    .outError[InternalServerError500](Status.InternalServerError)
```

## Route Function

```scala
// Implementation only — no type declarations
def route(endpoint: GetLanguagesEndpoint,
          useCase: UseCase[GetLanguagesCommand]): Route[Any, Response] =
  endpoint.implement { _ =>
    useCase(new GetLanguagesCommand())
      .map { r => GetLanguagesResponse(...) }
      .mapError { case InfraFailure(_,_) => InternalServerError500("...") }
  }
```

## Naming the DTO Type (zio-schema / OpenAPI)

zio-http derives the OpenAPI component name from the Scala class name (`TypeId`) — there is no annotation that renames the type for OpenAPI while keeping a different class name (`@AvroAnnotations.name` exists but is Avro-codec-only and ignored by OpenAPI gen). A DTO called `GetLanguagesResponseDto` therefore shows up in the generated spec as `GetLanguagesResponseDto`, leaking implementation naming into the public contract.

**Fix:** name the DTO the same as the domain concept (`GetLanguagesResponse`, not `GetLanguagesResponseDto`) and let the package qualify it — `s4y.vocabla.contracts.http.LanguagesContract.GetLanguagesResponse` vs. the domain type in `s4y.vocabla.domain`. Where a call site needs both in scope, alias the import for local clarity: `import ...LanguagesContract.GetLanguagesResponse as GetLanguagesResponseDto`.

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

