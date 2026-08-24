# Project Structure

Use this structure for a new TypeScript/Fastify backend. In an existing project, preserve its explicit layout unless the task is a migration to this standard.

## Root

```text
.
├── src/
│   ├── config/
│   ├── core/
│   ├── infra/
│   └── modules/
├── test/
│   ├── core/
│   ├── infra/
│   ├── modules/
│   ├── utils/
│   ├── test-setup.ts
│   └── test-env.d.ts
├── scripts/
├── docs/
├── package.json
├── tsconfig.json
├── vite.config.ts
├── vitest.e2e.shared.ts
├── vitest.e2e.http.config.ts
└── prettier.config.js
```

Root responsibilities:

- `src` contains production code.
- `test` mirrors production Modules and holds only test code, factories, fakes, and harnesses.
- `scripts` contains deterministic operational or CI entry points.
- `docs` explains architecture and decisions that executable configuration cannot express.
- root configs are the source of truth for commands, aliases, formatting, TypeScript, and test selection.

## Production code

```text
src/
├── config/
│   └── env.ts
├── core/
│   ├── entities/
│   ├── enums/
│   ├── errors/
│   ├── types/
│   └── utils/
├── infra/
│   ├── @types/
│   ├── database/
│   │   ├── dialect/
│   │   ├── <dialect>/
│   │   │   └── migrations/
│   │   ├── providers/
│   │   ├── database-client.ts
│   │   └── transaction.ts
│   ├── http/
│   │   ├── middlewares/
│   │   ├── openapi/
│   │   ├── routes/
│   │   ├── create-app.ts
│   │   └── app.ts
│   ├── providers/
│   ├── setup/
│   ├── telemetry/
│   └── server.ts
└── modules/
    └── <context>/
        ├── application/
        ├── domain/
        └── infra/
```

Do not confuse `src/core` with a business Module named `core`. `src/core` is technical code shared across Modules; business concepts belong under `src/modules`.

## One domain Module

Use `orders` only as a neutral example. Replace it with the target domain language.

```text
src/modules/sales/
├── domain/
│   └── order/
│       ├── entities/
│       │   └── order.ts
│       ├── enums/
│       │   └── order-status.ts
│       ├── repositories/
│       │   └── order-repository.ts
│       ├── types/
│       │   └── persisted-order.ts
│       └── value-objects/
├── application/
│   └── order/
│       ├── services/
│       └── use-cases/
│           ├── actions/
│           ├── create/
│           │   └── create-order-use-case.ts
│           ├── delete/
│           ├── find/
│           │   ├── by-external-id/
│           │   └── by-id/
│           ├── list/
│           ├── patch/
│           └── update/
└── infra/
    ├── http/
    │   └── routes/
    │       └── sales.routes.ts
    ├── order/
    │   ├── controllers/
    │   │   └── create/
    │   │       ├── create-order.controller.ts
    │   │       └── create-order.schema.ts
    │   ├── database/
    │   │   ├── mappers/
    │   │   │   └── order-mapper.ts
    │   │   └── repositories/
    │   │       └── order-repository.ts
    │   ├── http/
    │   │   └── routes/
    │   │       └── order.routes.ts
    │   ├── presenters/
    │   │   └── order-presenter.ts
    │   ├── providers/
    │   │   └── index.ts
    │   └── schemas/
    │       └── order.shared.schema.ts
    └── providers/
        └── index.ts
```

## Test mirror

```text
test/modules/sales/
├── application/
│   └── order/
│       └── use-cases/
│           └── create/
│               └── create-order-use-case.spec.ts
├── domain/
│   └── order/
│       └── entities/
│           └── make-order.ts
└── infra/
    └── order/
        ├── controllers/
        │   └── create/
        │       └── create-order.controller.e2e-spec.ts
        └── repositories/
            └── in-memory-order-repository.ts
```

Keep unit tests, in-memory repositories, and factories under `test`, never in `src`. Production code must not import `@test/*`.

## File ownership

| File | Owns |
|---|---|
| entity | valid domain state, defaults, intrinsic transitions |
| repository Interface | domain-shaped persistence contract |
| use case | one application behavior and orchestration |
| controller | Fastify-to-use-case adaptation |
| endpoint schema | runtime input validation and OpenAPI contract |
| route | URL, hook, schema, and handler wiring |
| guard | authentication or authorization decision at the HTTP Seam |
| mapper | database shape to/from domain shape |
| SQL repository | parameterized persistence implementation |
| provider | token-to-Adapter registration |
| presenter | domain-to-public-response serialization |
| unit spec | behavior through the use-case Interface with test Adapters |
| E2E spec | real HTTP contract and assembled infrastructure behavior |

## Naming

- Directories and files: `kebab-case`.
- Entities, use cases, controllers, repositories, mappers, presenters: `PascalCase`.
- Functions, variables, methods: `camelCase`.
- Global constants and enum members: `UPPER_SNAKE_CASE`.
- Unit tests: `*.spec.ts`.
- E2E tests: `*.e2e-spec.ts`.
- Zod/OpenAPI files: `*.schema.ts`.
- Providers: `*.provider.ts` or `providers/index.ts`.

Create a new folder only when it represents a real responsibility or keeps a repeated artifact family navigable. Avoid empty architectural placeholders.
