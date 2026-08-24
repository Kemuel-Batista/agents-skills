---
name: backend-engineering
description: Design, scaffold, implement, refactor, review, or test TypeScript/Fastify backends with a consistent modular architecture, use-case pattern, HTTP layer, dependency injection, persistence infrastructure, permissions, and Vitest unit/E2E strategy. Use when starting a Fastify API or changing backend entities, use cases, controllers, schemas, routes, repositories, guards, providers, migrations, or tests. Do not use for frontend-only work or non-Fastify backends unless the user explicitly asks to adapt this standard.
---

# Backend Engineering

Apply one coherent TypeScript/Fastify backend standard across projects. The standard is generic: examples use neutral domain names and must be renamed to the target project's canonical language.

For an existing repository, read its root and scoped instructions first. Preserve explicit local contracts unless the user requests a migration to this standard. For a new project, use these references as the canonical starting point.

## Route the work

Choose the smallest set of references that covers the task:

- New API or infrastructure foundation: read [project structure](references/project-structure.md), [Fastify bootstrap](references/fastify-bootstrap.md), and [repositories, mappers, and providers](references/repositories-mappers-and-providers.md).
- Architecture, Module ownership, Interface, or Seam design: read [architecture](references/architecture.md).
- Domain model or entity state: read [domain entities](references/domain-entities.md).
- Application behavior: read [use cases](references/use-cases.md).
- HTTP endpoint: read [controllers](references/controllers.md), [schemas](references/schemas.md), [routes](references/routes.md), and [permissions and guards](references/permissions-and-guards.md) when protected.
- Unit coverage: read [unit tests](references/unit-test.md).
- HTTP or assembled-runtime coverage: read [E2E tests](references/e2e-tests.md).

Read every reference for a new end-to-end resource because the resource crosses all of those artifacts. For focused work, do not load unrelated references.

## Discover before editing

1. Read applicable `AGENTS.md`, `CLAUDE.md`, and referenced project documentation.
2. Inspect `package.json`, TypeScript, formatting, test, environment, and path-alias configuration.
3. Trace the nearest complete resource through domain, application, infra, providers, routes, unit tests, and E2E tests.
4. Confirm real commands and current composition roots.
5. Record conflicts between docs and executable code. Follow higher-priority instructions, then the closest current working pattern.

Discovery is complete when every touched artifact has a precedent or is confirmed absent.

## Canonical dependency direction

Organize business Modules by domain context and keep dependencies pointing inward:

```text
infra -> application -> domain
```

- `domain` contains entities, value objects, enums, domain errors, and repository Interfaces.
- `application` contains use cases, orchestration, transaction ownership, and calls to Interfaces.
- `infra` contains Fastify, schemas, controllers, routes, guards, providers, mappers, SQL repositories, queues, cache, logging, and observability.

Treat each Module as a deep Module: expose a small Interface and hide orchestration and infrastructure behind it. Put a Seam only where behavior varies, and implement it with Adapters. Keep business decisions out of delivery and persistence Adapters.

## Implement the vertical slice

For each requested behavior:

1. Define input, caller-visible result, invariants, errors, authorization, persistence effects, and transaction needs.
2. Add or update the domain entity/value type and repository Interface when the behavior requires them.
3. Implement one application use case with typed request/response and `async execute()`.
4. Add infrastructure Adapters: mapper, repository, provider registration, and migration when persistence changes.
5. Add the HTTP slice: schema, controller, permission guard, and route registration.
6. Add focused unit tests using in-memory repositories and E2E tests when the HTTP contract or assembled wiring changes.
7. Run the narrowest test first, then repository-defined type, lint, build, and broader checks proportional to risk.

Do not create partial slices. A resource is incomplete when its required registration, validation, persistence mapping, permission, migration, or test is missing.

## Non-negotiable file standards

- Use files and directories in `kebab-case`, classes in `PascalCase`, and variables/functions in `camelCase` unless scoped instructions override them.
- Use strict TypeScript and explicit types at Module Interfaces.
- Validate every untrusted value with Zod at the delivery Seam.
- Use constructor injection in use cases and provider registration in composition roots.
- Keep controllers thin: validate, resolve one use case, execute, present, respond.
- Keep route files declarative: path, schema, permission, handler.
- Use parameterized persistence and explicit mappers between database and domain shapes.
- Propagate `databaseOptions?: DatabaseOptions` through persistent use cases and repositories so transactions compose.
- Unit tests instantiate the subject explicitly with in-memory repositories or fake Adapters. They never boot Fastify, resolve the production container, connect to real infrastructure, or mock internal Modules.
- E2E tests exercise the real Fastify route, validation, authentication/authorization, DI, and persistence effect in isolated test infrastructure.
- Use typed operational errors and a global Fastify error handler. Controllers do not catch domain/application errors.
- Use only commands verified in repository manifests or checked-in tool configuration.

## Verification and handoff

Self-review the final diff for layer violations, missing registrations, stale schemas, unsafe queries, authorization gaps, transaction mistakes, test-only seams leaked into production Interfaces, and unrelated changes.

Lead the handoff with the delivered behavior. Report files changed, public Interface or schema changes, migrations, tests and commands run, exact results, unverified infrastructure, assumptions, and residual risk. Never claim a check passed without observed output.
