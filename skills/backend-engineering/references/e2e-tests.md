# E2E Tests

E2E tests prove the assembled HTTP contract: real Fastify registration, schemas, authentication, permissions, controllers, dependency injection, use cases, mappers, SQL repositories, migrations, and observable persistence effects.

They use isolated test infrastructure. They never call production services or share mutable state with development or production.

## Boundary

An endpoint E2E spec uses:

- the real `createApp()`/assembled Fastify app;
- Supertest or Fastify `inject()` through the public HTTP route;
- real auth/session/permission setup helpers;
- the production DI graph and repository implementation;
- a real disposable test database with migrations applied;
- deterministic fake Adapters only for external systems outside the profile under test.

An endpoint E2E spec does not:

- instantiate the controller or use case directly;
- replace the repository with an in-memory implementation;
- bypass authentication or permission guards;
- mock internal application Modules;
- depend on test execution order;
- call `app.close()` in every spec file;
- point to a non-test database, Redis namespace, bucket, queue, or API account.

## File placement and name

```text
test/modules/<context>/infra/<entity>/controllers/<action>/
└── <action>-<entity>.controller.e2e-spec.ts
```

Mirror the controller path and use `*.e2e-spec.ts`. The unit configuration excludes this suffix; each E2E profile selects it explicitly.

## Canonical endpoint spec

```typescript
import type { OrderRepository } from "@/modules/sales/domain/order/repositories/order-repository";
import { app } from "@/infra/http/app";
import { permissions } from "@/modules/iam/domain/permission/permissions";
import request from "supertest";
import { container } from "tsyringe";
import { beforeAll, describe, expect, it } from "vitest";

import { iamLoginE2E } from "@test/modules/iam/utils/iam-login-e2e";

describe("POST /sales/orders", () => {
    let orderRepository: OrderRepository;

    beforeAll(async () => {
        await app.ready();
        orderRepository = container.resolve<OrderRepository>("OrderRepository");
    });

    it("creates an order with the authenticated actor", async () => {
        const { cookie, user } = await iamLoginE2E({
            app,
            permissions: [permissions.sales.order.create],
        });

        const response = await request(app.server)
            .post("/sales/orders")
            .set("Cookie", cookie)
            .send({
                externalId: "ORDER-E2E-001",
                customerId: 42,
                priority: 2,
            });

        expect(response.status).toBe(201);
        expect(response.body).toEqual({
            order: expect.objectContaining({
                id: expect.any(Number),
                externalId: "ORDER-E2E-001",
                customerId: 42,
                priority: 2,
                status: expect.any(Number),
                createdAt: expect.any(String),
                updatedAt: expect.any(String),
            }),
        });

        const persisted = await orderRepository.findByExternalId(
            "ORDER-E2E-001"
        );

        expect(persisted).toEqual(
            expect.objectContaining({
                id: response.body.order.id,
                createdBy: user.id,
            })
        );
    });

    it("applies request defaults", async () => {
        const { cookie } = await iamLoginE2E({
            app,
            permissions: [permissions.sales.order.create],
        });

        const response = await request(app.server)
            .post("/sales/orders")
            .set("Cookie", cookie)
            .send({
                externalId: "ORDER-E2E-DEFAULT",
                customerId: 42,
            });

        expect(response.status).toBe(201);
        expect(response.body.order.priority).toBe(1);
    });

    it("returns 422 for an invalid body and persists nothing", async () => {
        const { cookie } = await iamLoginE2E({
            app,
            permissions: [permissions.sales.order.create],
        });

        const response = await request(app.server)
            .post("/sales/orders")
            .set("Cookie", cookie)
            .send({ externalId: "", customerId: -1 });

        expect(response.status).toBe(422);
        expect(response.body).toEqual(
            expect.objectContaining({
                error: "request.validation.failed",
            })
        );
        expect(JSON.stringify(response.body)).not.toContain("stack");
        expect(await orderRepository.findByExternalId("")).toBeNull();
    });

    it("returns 409 for a duplicate external ID", async () => {
        const { cookie } = await iamLoginE2E({
            app,
            permissions: [permissions.sales.order.create],
        });

        await request(app.server)
            .post("/sales/orders")
            .set("Cookie", cookie)
            .send({ externalId: "ORDER-E2E-DUP", customerId: 42 })
            .expect(201);

        const response = await request(app.server)
            .post("/sales/orders")
            .set("Cookie", cookie)
            .send({ externalId: "ORDER-E2E-DUP", customerId: 42 });

        expect(response.status).toBe(409);
        expect(response.body.error).toBe("order.found.by-external-id");
    });

    it("returns 401 without authentication", async () => {
        await request(app.server)
            .post("/sales/orders")
            .send({ externalId: "ORDER-E2E-401", customerId: 42 })
            .expect(401);
    });

    it("returns 403 without the required permission", async () => {
        const { cookie } = await iamLoginE2E({ app, permissions: [] });

        await request(app.server)
            .post("/sales/orders")
            .set("Cookie", cookie)
            .send({ externalId: "ORDER-E2E-403", customerId: 42 })
            .expect(403);
    });
});
```

The repository read is a secondary assertion of the public request's persistent effect. Do not use it to arrange the success path when the public API can arrange the prerequisite clearly. For complex prerequisites, direct factory/repository setup is acceptable when that prerequisite endpoint is irrelevant to the behavior under test.

## Authentication helper

An auth helper provisions real identity, session, role, and permission records, then logs in through the actual authentication contract or issues a session through the same application behavior:

```typescript
const { cookie, user, session } = await iamLoginE2E({
    app,
    permissions: [permissions.sales.order.create],
    roles: ["operator"],
});
```

It must not add a magic test bypass to a guard. Keep WEB session and API bearer helpers separate so audience checks remain testable.

## Scenario matrix per endpoint

Cover only behavior owned by the endpoint, but cover it completely:

- full valid payload;
- minimum valid payload and defaults;
- invalid type, range, enum, format, cross-field, and missing required values;
- authenticated success with the exact permission;
- unauthenticated `401` and unauthorized `403`;
- wrong auth audience where relevant;
- `404`, `409`, invalid transition, or other typed application error;
- response status and exact public shape;
- resulting persistence, audit, event, or queue effect;
- redaction of secrets, stack, SQL, tokens, and internal causes;
- tenant/operation/resource isolation when applicable;
- idempotency and retry behavior for externally repeatable commands.

One canonical test may cover several properties. Avoid duplicating Zod unit tests for every equivalent invalid primitive; prioritize contract boundaries and regressions.

## Shared Vitest configuration

```typescript
// vitest.e2e.shared.ts
import tsconfigPaths from "vite-tsconfig-paths";
import { defineConfig, mergeConfig } from "vitest/config";

import baseConfig from "./vite.config";

export const e2eSharedConfig = mergeConfig(
    baseConfig,
    defineConfig({
        plugins: [tsconfigPaths()],
        test: {
            globals: true,
            globalSetup: ["./test/utils/e2e/global-setup.ts"],
            setupFiles: ["./test/utils/e2e/test-setup.ts"],
            runner: "./test/utils/e2e/e2e-runner.ts",
            bail: 1,
            maxConcurrency: 1,
            maxWorkers: 1,
            fileParallelism: false,
            isolate: false,
            testTimeout: 30_000,
            hookTimeout: 60_000,
        },
    })
);
```

Serialization is the safe default for suites sharing a database schema or Fastify singleton. Increase concurrency only after provisioning one isolated schema/database/namespace per worker.

## Profile configuration

```typescript
// vitest.e2e.http.config.ts
import { defineConfig, mergeConfig } from "vitest/config";

import { e2eSharedConfig } from "./vitest.e2e.shared";

export default mergeConfig(
    e2eSharedConfig,
    defineConfig({
        test: {
            include: [
                "test/modules/**/controllers/**/*.controller.e2e-spec.ts",
            ],
            env: {
                NODE_ENV: "test",
                APP_PROFILE: "HTTP_INTEGRATION",
            },
        },
    })
);
```

Maintain deliberate profiles rather than one accidental mega-suite:

- `HTTP_INTEGRATION`: ordinary controllers/routes with deterministic test Adapters for queues or remote systems not under test.
- `IAM_INTEGRATION`: login, session, roles, permissions, cookies, and bearer audience behavior.
- `FULL_INTEGRATION`: database plus cache/queue/worker behavior that requires the complete runtime.

Each spec pattern belongs to exactly one profile. Profile include globs must not overlap.

## Global setup: migrate once

```typescript
// test/utils/e2e/global-setup.ts
import { assertSafeTestEnvironment } from "./safety";
import { migrateTestDatabase } from "./test-database";

export default async function globalSetup() {
    assertSafeTestEnvironment();
    await migrateTestDatabase();
}
```

Run committed migrations once per E2E process, not once per spec. A fresh CI database proves empty-database migration. A separate migration job should also test upgrading from the previous release when compatibility matters.

## Per-test reset

```typescript
// test/utils/e2e/test-setup.ts
import { beforeEach } from "vitest";

import { clearFakeExternalAdapters } from "./fake-external-adapters";
import { assertSafeTestEnvironment } from "./safety";
import { resetTestDatabase } from "./test-database";

beforeEach(async () => {
    assertSafeTestEnvironment();
    await resetTestDatabase();
    clearFakeExternalAdapters();
});
```

Reset all mutable state used by the profile: relational tables, sequences when assertions require it, Redis namespace, queue/topic state, object keys, fake messages, deterministic clock, and provider caches. Respect foreign-key order or use a tested reset transaction/procedure.

## Close the app once

```typescript
// test/utils/e2e/e2e-runner.ts
import { TestRunner } from "vitest";

import { closeTestInfrastructure } from "./test-infrastructure";

let cleanupRegistered = false;
type E2ERunnerConfig = ConstructorParameters<typeof TestRunner>[0];

export default class E2ERunner extends TestRunner {
    constructor(config: E2ERunnerConfig) {
        super(config);

        if (!cleanupRegistered) {
            cleanupRegistered = true;
            this.onCleanupWorkerContext(async () => {
                const { app } = await import("@/infra/http/app");

                await app.close();
                await closeTestInfrastructure();
            });
        }
    }
}
```

Aggregate cleanup errors when the app, database pool, cache, queue, workers, or telemetry each need explicit shutdown. Use the Vitest runner API supported by the repository's installed version. The invariant is one assembled app per profile process and one close after all files, so no spec closes resources needed by another spec.

## Infrastructure isolation and safety

- Use disposable containers, an ephemeral CI service, or a dedicated test database/schema.
- Require an unmistakable test marker in database name, host/account, Redis prefix, bucket, and queue namespace.
- Abort before destructive reset when `NODE_ENV !== "test"` or any target fails its allowlist.
- Do not default test credentials to production-like hosts.
- Never run truncation/reset logic from production startup.
- Use unique names for parallel jobs and delete only that exact namespace.
- Keep external network disabled unless a profile explicitly tests a controlled sandbox service.

## Execution order

Run one spec, then its profile, then all relevant profiles:

```bash
bun vitest run --config vitest.e2e.http.config.ts test/modules/sales/infra/order/controllers/create/create-order.controller.e2e-spec.ts
bun run test:e2e:http
bun run test:e2e
```

Use only checked-in commands. Record which database/dialect and profile were actually exercised.

## Completion checklist

- Spec uses `*.e2e-spec.ts` and belongs to exactly one profile.
- Request enters through the final registered route and prefix.
- Real schema, guards, controller, DI, use cases, mapper, SQL repository, and migrations execute.
- Success, defaults, validation, `401`, `403`, typed errors, response shape, and persistence effect are covered as applicable.
- Mutable infrastructure is reset before every test.
- Migrations run once and app/resources close once per profile process.
- No internal Module is mocked and no in-memory repository replaces SQL.
- Safety checks make destructive reset impossible outside exact test targets.
- Focused and profile commands pass with observed output.
