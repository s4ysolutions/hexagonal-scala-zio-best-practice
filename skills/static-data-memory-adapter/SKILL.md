---
name: static-data-memory-adapter
description: Use when a repository port holds data that never changes at runtime (configuration lists, enumerations, static reference tables), or when a test needs a fast in-memory substitute for a persistence adapter
tags: [architecture, testing, language-agnostic]
---

# Static Data Memory Adapter

**Scope:** language-agnostic, framework-agnostic

## Overview

When a port's data is truly static at runtime (never changes after startup), implement it with an in-memory adapter instead of a database adapter. The port contract is identical — only the concrete type chosen at the composition root differs.

## Pattern

```
LanguagesRepository[TX]        ← port (abstract)
  ↑ implemented by
LanguagesRepositoryMemory      ← in-memory: returns a hardcoded list
LanguagesRepositoryPg          ← db: queries a table
```

At the composition root:
```
// data never changes at runtime → use memory
val languagesRepoLayer: ULayer[LanguagesRepository[TXM]] = LanguagesRepositoryMemory.layer
```

## When to Use In-Memory

| Data | Adapter |
|------|---------|
| Language list, country codes, enum values | Memory |
| User records, orders, events | DB |
| Configuration loaded once at startup | Memory |
| Config that changes without restart | DB or config service |

## Transaction Context for Memory

Static memory adapters still implement the same `Repository[TX]` port. Use a dedicated lightweight transaction context (e.g., `TransactionContextMemory`) that carries no connection — it satisfies the type signature without overhead:

```
TransactionContextMemory   ← zero-cost context, no DB involved
TransactionManagerMemory   ← trivially runs the effect synchronously
```

This keeps the port signature uniform while avoiding database infrastructure for pure data.

## Testing Benefit

The same in-memory adapter can be injected in unit tests without a database, providing fast, deterministic test doubles:

```
// test wiring
val repoLayer: ULayer[LanguagesRepository[TXM]] = LanguagesRepositoryMemory.layer
```

## Common Mistakes

**In-memory adapter for mutable data** — if the data can be written by the app, the memory adapter is a regression risk (data lost on restart, no durability).

**Separate port for "static" data** — always use the same port as the DB adapter; switching between implementations at the composition root is the point.

**Loading static data from DB on every request** — if data is truly static, load it once at startup into the memory adapter; a DB round-trip per request for unchanging data is unnecessary.

**Treating "static" as "never changes across deploys"** — if a DB of record exists (e.g. a languages table), the memory adapter's hardcoded list must be regenerated on deploy whenever that table changes. Static means "does not change while the process is running," not "never changes in production."

