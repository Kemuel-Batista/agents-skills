# Permissions and Guards

Authentication establishes a trusted request context. Authorization checks that context against one operation-specific permission. Keep both at the HTTP Seam and keep business ownership checks in application/domain behavior.

## Permission keys

Keep permission names centralized, stable, and typed:

```typescript
export const permissions = {
    sales: {
        order: {
            create: "permissions.sales.order.create",
            find: "permissions.sales.order.find",
            list: "permissions.sales.order.list",
            update: "permissions.sales.order.update",
            cancel: "permissions.sales.order.cancel",
            delete: "permissions.sales.order.delete",
        },
    },
} as const;

type NestedValue<T> = T extends string
    ? T
    : { [K in keyof T]: NestedValue<T[K]> }[keyof T];

export type PermissionKey = NestedValue<typeof permissions>;
```

Persisted permission names, seeds, route keys, session capabilities, and E2E fixtures must use the same canonical values. Change them only with an explicit compatibility and migration plan.

## Permission seed

Build seeds from the canonical constants instead of repeating string literals:

```typescript
import type { PermissionSeedEntry } from "./permission-seed-entry";
import { permissions } from "./permissions";

export const permissionSeed = [
    {
        key: permissions.sales.order.create,
        name: "Create orders",
        module: "sales",
    },
    {
        key: permissions.sales.order.find,
        name: "Find orders",
        module: "sales",
    },
    {
        key: permissions.sales.order.list,
        name: "List orders",
        module: "sales",
    },
] satisfies ReadonlyArray<PermissionSeedEntry>;
```

Seed idempotently by stable key, preserve existing role assignments, and remove or rename permissions only through an explicit migration. Test helpers grant these same typed keys; they never manufacture a guard bypass.

## Authenticated request context

Define the context once in Fastify type augmentation:

```typescript
export interface AuthContext {
    audience: "WEB" | "API";
    sessionId: string;
    userId: number;
    permissions: ReadonlySet<PermissionKey>;
    roles: ReadonlySet<string>;
}

declare module "fastify" {
    interface FastifyRequest {
        auth?: AuthContext;
    }
}
```

Do not attach password, password hash, raw token, cookie secret, or full session payload to the request.

Controllers on protected routes retrieve the context through one safe helper:

```typescript
import { UnauthorizedError } from "@/core/errors";
import type { FastifyRequest } from "fastify";

import type { AuthContext } from "./auth-context";

export function getAuthContext(request: FastifyRequest): AuthContext {
    if (!request.auth) {
        throw new UnauthorizedError("user.auth.not-authenticated");
    }

    return request.auth;
}
```

## Session authentication guard

```typescript
import { UnauthorizedError } from "@/core/errors";
import { FindUserSessionByIdUseCase } from "@/modules/iam/application/user/use-cases/find/session/by-id/find-user-session-by-id-use-case";
import type { FastifyReply, FastifyRequest } from "fastify";
import { container } from "tsyringe";

export async function ensureAuthenticated(
    request: FastifyRequest,
    _reply: FastifyReply
): Promise<void> {
    const sessionId = request.session?.sessionId;

    if (!request.cookies.sessionId || !sessionId) {
        throw new UnauthorizedError("user.auth.invalid-session.missing");
    }

    const findSession = container.resolve(FindUserSessionByIdUseCase);
    const session = await findSession.execute({
        id: sessionId,
        audience: "WEB",
    });

    if (!session) {
        throw new UnauthorizedError("user.auth.invalid-session.not-found");
    }

    request.auth = {
        audience: "WEB",
        sessionId: session.id,
        userId: session.userId,
        permissions: new Set(session.permissions),
        roles: new Set(session.roles),
    };
}
```

The guard resolves application behavior, not repositories. It validates audience so an API token cannot silently act as a browser session or vice versa.

## Permission guard

```typescript
import { ForbiddenError, UnauthorizedError } from "@/core/errors";
import type { FastifyReply, FastifyRequest } from "fastify";

import type { PermissionKey } from "../permissions";

export function ensurePermission(permission: PermissionKey) {
    return async function permissionGuard(
        request: FastifyRequest,
        _reply: FastifyReply
    ): Promise<void> {
        if (!request.auth) {
            throw new UnauthorizedError("user.auth.not-authenticated");
        }

        const isDeveloper = request.auth.roles.has("developer");
        const canAccess = request.auth.permissions.has(permission);

        if (!isDeveloper && !canAccess) {
            throw new ForbiddenError("user.permission.denied", {
                permission,
            });
        }
    };
}
```

Reuse capabilities already loaded by authentication. Avoid querying session, user, roles, and permissions again in every route guard.

## API bearer guard

External integration routes use a distinct audience and transport:

```typescript
import { UnauthorizedError } from "@/core/errors";
import { AuthenticateApiSessionUseCase } from "@/modules/iam/application/api-session/use-cases/authenticate/authenticate-api-session-use-case";
import type { FastifyReply, FastifyRequest } from "fastify";
import { container } from "tsyringe";

export async function ensureApiAuthenticated(
    request: FastifyRequest,
    _reply: FastifyReply
): Promise<void> {
    const authorization = request.headers.authorization;
    const token = authorization?.startsWith("Bearer ")
        ? authorization.slice("Bearer ".length)
        : null;

    if (!token) {
        throw new UnauthorizedError("api.auth.token.missing");
    }

    const authenticateApiSession = container.resolve(
        AuthenticateApiSessionUseCase
    );
    const session = await authenticateApiSession.execute({ token });

    request.auth = {
        audience: "API",
        sessionId: session.id,
        userId: session.userId,
        permissions: new Set(session.permissions),
        roles: new Set(session.roles),
    };
}
```

The use case owns token hashing/comparison and session lookup. Never log or persist the raw bearer token.

## Hook order and scope

Recommended order:

```text
cookie/session or bearer plugin
-> ensureAuthenticated or ensureApiAuthenticated
-> ensurePermission
-> request schema validation
-> controller
-> use case
```

Use a protected Fastify plugin scope for authentication and a per-route hook for permissions. External adapter routes get their own API-authenticated scope.

Authentication answers **who and which audience**. Permission guards answer **whether that identity has a capability**. A use case still enforces resource ownership, valid state transitions, tenant/operation isolation, and domain-specific authorization that depends on loaded data.

## Guard rules

- Return no domain data and perform no business mutation.
- Throw typed `UnauthorizedError` or `ForbiddenError`; let the global handler serialize safely.
- Fail closed when context, audience, session, or permission is absent.
- Keep public routes outside protected scopes rather than adding bypass flags.
- Redact cookies, tokens, authorization headers, and session payloads from logs.
- Rate-limit and audit sensitive login, token, permission, and administrative operations.
- Do not weaken hashing, cookie flags, audience validation, or permission checks for tests; test helpers must provision valid auth state.

## Required E2E coverage

For every protected endpoint, cover:

- valid identity with the required permission;
- missing or expired authentication;
- valid identity without the permission;
- wrong audience when WEB and API sessions coexist;
- safe error body with no token, cookie, stack, or internal context;
- domain ownership/isolation denial when applicable.
