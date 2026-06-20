---
name: module-i18n
description: Use when adding localized strings to a Scala 3 module, auditing i18n resource files for unused or cross-module keys, or when choosing between ResourcesStringsResolver and ResourcesBundleResolver
tags: [scala, scala3, i18n, architecture]
---

# Module I18n (Scala 3)

**Scope:** Scala 3 + Mill build. Uses `given`, `extension`, `private[pkg]` scoping.

## When invoked for ADDING — ask first

Before creating any files, ask:

> Use `ResourcesStringsResolver` (recommended) or `ResourcesBundleResolver`?
>
> - **ResourcesStringsResolver** — free-form keys in `.i18n` files. Keys are the English messages themselves (e.g. `Invalid provider: {}` = `Invalid provider: {0}.`). No dot-separated naming required.
> - **ResourcesBundleResolver** — Java `ResourceBundle`, `.properties` files, dot-separated keys (`error.invalid_provider`). Standard JVM locale fallback.
>
> Use `ResourcesStringsResolver` unless you need `.properties` file compatibility.

## Adding i18n to a Module

**Step 1 — verify build.mill has `core.i18n` in `moduleDeps`:**
```scala
object mymodule extends BaseModule {
  override def moduleDeps: Seq[JavaModule] =
    Seq(core.i18n, ...)
}
```

**Step 2 — create `I18n.scala` in the package:**
```scala
// features/myfeature/domain/src/s4y/myfeature/domain/I18n.scala
package s4y.myfeature.domain

import s4y.i18n.{ResourcesStringsResolver, TranslationResolver}

private[domain] given translationResolver: TranslationResolver =
  ResourcesStringsResolver("messages_myfeature_domain")
```

`private[domain]` — prevents cross-module access.

**Step 3 — create the resource file:**

Place at `features/myfeature/domain/resources/messages_myfeature_domain.i18n`

Format: `key = localized value`
- Key is the English message with `{}` placeholders
- Value uses `{0}`, `{1}`, … (Java MessageFormat)
- Lines starting with `#` or blank lines are ignored

```
Invalid provider: {} = Invalid provider: {0}.
Quota exceeded = Quota exceeded.
Request error: {} = Request error: {0}.
```

**Step 4 — use in package files:**
```scala
// any file in s4y.myfeature.domain — resolver in scope via given
import s4y.i18n.{Translatable, t}

val msg: Translatable = t"Invalid provider: $provider"
val msg2: Translatable = t"Quota exceeded"
```

The `t"..."` interpolator reads the string literal as the translation key. `$var` arguments are passed as `{0}`, `{1}`, etc. in the value.

## Auditing a Module's Resources

**Rules:**
1. Every key in the `.i18n` file must appear in at least one `t"..."` in the **same package**.
2. Every `t"..."` literal should match a key in the module's `.i18n` file.
3. Cross-module key usage is a **red flag** — if module A's code uses `t"..."` strings defined in module B's resolver, the boundary is broken.

**How to check:**

For each key in `messages_<module>.i18n`:
```bash
grep -r 'key text here' features/mymodule/src --include="*.scala"
```
If no matches → remove the key.

For each `t"..."` in the module:
```bash
grep -rh 't"[^"]*"' features/mymodule/src --include="*.scala"
```
Extract the literal text and verify it exists in the module's `.i18n` file.

**Cross-module check:** if a string appears in `t"..."` in package A but is only defined in the `.i18n` of package B, it will silently fall back to the raw key. Search both packages for the key text to confirm ownership.

## Layer Isolation Rules

| Layer | Bundle? | Note |
|-------|---------|------|
| domain | ✅ for typed errors carrying `Translatable` | Never resolve locale in domain — pass `Translatable` upward |
| domain.workflows | ✅ own bundle | Same rule |
| presentation | ✅ always | Locale resolution happens here |
| infra | ❌ | Map to domain errors before crossing boundary |

## Common Mistakes

**Unused keys in `.i18n`** — stale after refactors. Audit on every i18n change.

**`given` at top-level package** — visible everywhere; scope `private[featurePkg]`.

**Resolving locale in domain** — locale is request-scoped; pass `Translatable` (lazy) upward.

**Cross-module fallback** — if `t"..."` key is not in the module's bundle, it silently returns the raw key at runtime. No compile error.

