# Fastify Bootstrap

Use this sequence to start a production-shaped TypeScript/Fastify API. Keep bootstrap as a composition root: it loads configuration, registers infrastructure, assembles plugins and routes, starts the listener, and shuts resources down. It does not contain business behavior.

## 1. Initialize the project

Use the repository's package manager. This example uses Bun:

```bash
bun init
bun add fastify @fastify/cookie @fastify/cors @fastify/helmet @fastify/swagger @fastify/swagger-ui reflect-metadata tsyringe zod
bun add -d typescript vite vite-tsconfig-paths vitest supertest @types/supertest prettier eslint
```

Add database, cache, queue, tracing, and session packages only when the project actually uses those capabilities. Wrap each external system behind one Adapter and validate all related configuration.

Canonical scripts:

```json
{
    "scripts": {
        "dev": "bun --watch src/infra/server.ts",
        "build": "vite build",
        "start": "bun dist/server.js",
        "typecheck": "tsc --noEmit",
        "lint": "eslint .",
        "format:check": "prettier --check .",
        "test": "vitest run",
        "test:watch": "vitest",
        "test:e2e:http": "vitest run --config vitest.e2e.http.config.ts"
    }
}
```

Verify runtime/build compatibility before copying the exact `start` command. The checked-in manifest is the command source of truth.

## 2. Configure strict TypeScript

```json
{
    "compilerOptions": {
        "target": "ES2022",
        "module": "ESNext",
        "moduleResolution": "Bundler",
        "strict": true,
        "noUncheckedIndexedAccess": true,
        "noImplicitOverride": true,
        "experimentalDecorators": true,
        "emitDecoratorMetadata": true,
        "esModuleInterop": true,
        "resolveJsonModule": true,
        "baseUrl": ".",
        "paths": {
            "@/*": ["src/*"],
            "@test/*": ["test/*"]
        },
        "types": ["node"]
    },
    "include": ["src", "test", "*.config.ts"]
}
```

Configure the same aliases in Vite/Vitest with `vite-tsconfig-paths`. Never rely on an alias that only TypeScript understands.

## 3. Validate environment at import time

```typescript
// src/config/env.ts
import { z } from "zod";

const envSchema = z.object({
    NODE_ENV: z.enum(["development", "test", "production"]),
    HOST: z.string().default("0.0.0.0"),
    PORT: z.coerce.number().int().min(1).max(65_535).default(3333),
    LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace"])
        .default("info"),
    APP_PROFILE: z.enum(["PRODUCTION", "HTTP_INTEGRATION", "FULL_INTEGRATION"])
        .default("PRODUCTION"),
    DATABASE_URL: z.string().min(1),
    COOKIE_SECRET: z.string().min(32),
    CORS_ORIGINS: z.string().transform((value) =>
        value.split(",").map((origin) => origin.trim())
    ),
});

const parsedEnv = envSchema.safeParse(process.env);

if (!parsedEnv.success) {
    throw new Error(`Invalid environment: ${parsedEnv.error.message}`);
}

export const env = parsedEnv.data;
```

Do not export raw `process.env` reads throughout the codebase. Never log secret values in validation failures.

## 4. Define composition profiles

Production and E2E need different amounts of infrastructure without changing business wiring:

```typescript
export type AppProfile = "PRODUCTION" | "HTTP_INTEGRATION" | "FULL_INTEGRATION";

export interface CreateAppOptions {
    profile?: AppProfile;
}
```

- `PRODUCTION`: all configured production plugins, providers, routes, telemetry, and workers.
- `HTTP_INTEGRATION`: HTTP, auth, DI, and database; replace queues or remote systems with deterministic test Adapters when they are not under test.
- `FULL_INTEGRATION`: full assembled runtime for cross-infrastructure behavior.

Profiles may change external Adapters and background-process startup. They must not skip authentication, permission guards, schemas, controllers, use cases, repositories, or routes being tested.

## 5. Register providers

Load `reflect-metadata` before decorated classes and provider side effects exactly once:

```typescript
// src/infra/providers/index.ts
import "@/infra/database/providers";
import "@/modules/iam/infra/providers";
import "@/modules/sales/infra/providers";
```

Database client, SQL dialect, repositories, clock, identifiers, audit, cache, and integration ports are registered here or through imported Module registries. See [repositories, mappers, and providers](repositories-mappers-and-providers.md).

## 6. Create the Fastify instance

```typescript
// src/infra/http/create-app.ts
import { env } from "@/config/env";
import Fastify, { type FastifyInstance } from "fastify";

import { globalErrorHandler } from "./middlewares/global-error-handler";
import { setup } from "../setup";
import type { CreateAppOptions } from "./types/create-app-options";

export async function createApp(
    options: CreateAppOptions = {}
): Promise<FastifyInstance> {
    const app = Fastify({
        logger: {
            level: env.LOG_LEVEL,
            redact: [
                "req.headers.authorization",
                "req.headers.cookie",
                "res.headers.set-cookie",
            ],
        },
        disableRequestLogging: false,
        trustProxy: true,
    });

    app.setErrorHandler(globalErrorHandler);
    app.setNotFoundHandler(async (_request, reply) => {
        return reply.status(404).send({
            error: "route.not-found",
            message: "Route not found",
        });
    });

    await setup(app, options.profile ?? "PRODUCTION");

    return app;
}
```

`createApp()` assembles and returns a ready-able instance; it never calls `listen()`. This makes the same composition callable by production and E2E tests.

## 7. Assemble plugins in deterministic order

```typescript
// src/infra/setup/index.ts
import "reflect-metadata";
import "@/infra/providers";

import type { FastifyInstance } from "fastify";

import type { AppProfile } from "../http/types/create-app-options";
import { routes } from "../http/routes";
import { setupInfrastructure } from "./infrastructure";
import { setupOpenApi } from "./openapi";
import { setupSecurity } from "./security";

export async function setup(app: FastifyInstance, profile: AppProfile) {
    await setupSecurity(app);
    await setupInfrastructure(app, profile);
    await setupOpenApi(app);
    await app.register(routes);
}
```

Recommended order:

```text
configuration and metadata
-> provider registrations
-> security headers/CORS/cookies/session
-> database/cache/queue/telemetry plugins
-> OpenAPI and common schemas
-> public/protected routes
-> optional background workers
```

A plugin must be registered before routes that consume its decorators or request augmentation.

## 8. Configure baseline HTTP security

```typescript
// src/infra/setup/security.ts
import cookie from "@fastify/cookie";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import type { FastifyInstance } from "fastify";

import { env } from "@/config/env";

export async function setupSecurity(app: FastifyInstance) {
    await app.register(helmet);
    await app.register(cors, {
        origin: env.CORS_ORIGINS,
        credentials: true,
    });
    await app.register(cookie, {
        secret: env.COOKIE_SECRET,
        hook: "onRequest",
    });
}
```

Add the chosen session plugin immediately after cookie registration. Production cookies should be `httpOnly`, `secure`, use an explicit `sameSite` policy, and have bounded lifetime. Use an explicit origin allowlist; do not combine wildcard origins with credentials.

Add request/body limits, rate limits, multipart limits, CSRF protection, and proxy settings according to exposure and threat model.

## 9. Standardize errors

```typescript
// src/infra/http/middlewares/global-error-handler.ts
import { AppError } from "@/core/errors/app-error";
import type { FastifyError, FastifyReply, FastifyRequest } from "fastify";

export async function globalErrorHandler(
    error: FastifyError | AppError,
    request: FastifyRequest,
    reply: FastifyReply
) {
    if (error instanceof AppError) {
        request.log.info(
            { errorKey: error.key, statusCode: error.statusCode },
            "request rejected"
        );

        return reply.status(error.statusCode).send({
            error: error.key,
            message: error.safeMessage,
            details: error.safeDetails,
        });
    }

    request.log.error({ err: error }, "unhandled request error");

    return reply.status(500).send({
        error: "internal-server-error",
        message: "Internal server error",
    });
}
```

The response never includes stack, SQL, driver data, secret configuration, tokens, or internal causes. Preserve the original cause only in protected structured logs and traces.

## 10. Expose health and OpenAPI

- Liveness answers whether the process/event loop is alive; it should not fail because a dependency is temporarily unavailable.
- Readiness checks only dependencies required to serve traffic and uses bounded timeouts.
- Expose build/version information that is safe for operators.
- Register OpenAPI schemas before routes and publish docs only according to environment/security policy.
- Add request IDs and propagate correlation across database, queue, and remote Adapter calls.

## 11. Separate app creation from process lifecycle

```typescript
// src/infra/http/app.ts
import { env } from "@/config/env";

import { createApp } from "./create-app";

export const app = await createApp({ profile: env.APP_PROFILE });
```

```typescript
// src/infra/server.ts
import "reflect-metadata";
import "@/infra/telemetry/register";

import { env } from "@/config/env";

import { app } from "./http/app";

async function shutdown(signal: NodeJS.Signals) {
    app.log.info({ signal }, "shutting down");

    try {
        await app.close();
        process.exitCode = 0;
    } catch (error) {
        app.log.error({ err: error }, "shutdown failed");
        process.exitCode = 1;
    }
}

for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.once(signal, () => void shutdown(signal));
}

try {
    await app.listen({ host: env.HOST, port: env.PORT });
} catch (error) {
    app.log.fatal({ err: error }, "server startup failed");
    process.exitCode = 1;
}
```

Telemetry registration stays before imports that instrumented libraries need to patch. `app.close()` must close Fastify plugins, database pools, cache clients, queue consumers, workers, and telemetry exporters through registered lifecycle hooks.

## New-project delivery order

1. Package manifest, strict TypeScript, aliases, formatting, lint, and environment validation.
2. Typed core errors, identifier/date abstractions, database types, and global error mapping.
3. Database client, dialect, migrations, transaction helper, and provider composition.
4. `createApp`, deterministic setup plugins, security, OpenAPI, health, and process lifecycle.
5. Authentication, request context, permission keys, and guards.
6. First complete vertical resource: domain, use cases, repository, mapper, provider, controller, schema, route, unit, and E2E.
7. CI checks, migration verification, isolated E2E infrastructure, telemetry, graceful shutdown, and operational docs.

Do not scaffold empty layers for future guesses. Add each optional subsystem with one real consumer and one verification path.

## Bootstrap checklist

- Environment is validated once and secrets are redacted.
- Metadata and telemetry load before decorated/instrumented imports.
- `createApp()` does not listen and is reused by E2E.
- Plugin order satisfies decorators and request augmentation.
- Provider registrations load exactly once.
- Public, session-protected, and API-protected route groups are explicit.
- Global errors are safe and typed errors keep stable keys.
- Readiness, liveness, OpenAPI, correlation, and shutdown behavior exist.
- Unit tests need no bootstrap; E2E uses a deliberate profile.
- Typecheck, lint, unit, E2E, build, and migration commands are checked in and observed in CI.
