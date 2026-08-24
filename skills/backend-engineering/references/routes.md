# Routes

Route files are declarative wiring. They connect URL, method, schema, permission guard, and controller without business logic.

## Entity route file

```text
src/modules/<context>/infra/<entity>/http/routes/<entity>.routes.ts
```

```typescript
import { ensurePermission } from "@/infra/http/middlewares/ensure-permission";
import { permissions } from "@/modules/iam/domain/permission/permissions";
import type { FastifyInstance } from "fastify";

import { CreateOrderController } from "../../controllers/create/create-order.controller";
import { createOrderOpenAPISchema } from "../../controllers/create/create-order.schema";
import { FindOrderByIdController } from "../../controllers/find/by-id/find-order-by-id.controller";
import { findOrderByIdOpenAPISchema } from "../../controllers/find/by-id/find-order-by-id.schema";
import { ListOrderController } from "../../controllers/list/list-order.controller";
import { listOrderOpenAPISchema } from "../../controllers/list/list-order.schema";

const createOrderController = new CreateOrderController();
const findOrderByIdController = new FindOrderByIdController();
const listOrderController = new ListOrderController();

export async function orderRoutes(app: FastifyInstance): Promise<void> {
    app.post("/", {
        preHandler: ensurePermission(permissions.sales.order.create),
        schema: createOrderOpenAPISchema,
        handler: createOrderController.handle,
    });

    app.get("/", {
        preHandler: ensurePermission(permissions.sales.order.list),
        schema: listOrderOpenAPISchema,
        handler: listOrderController.handle,
    });

    app.get("/:id", {
        preHandler: ensurePermission(permissions.sales.order.find),
        schema: findOrderByIdOpenAPISchema,
        handler: findOrderByIdController.handle,
    });
}
```

Instantiate controllers once at module scope. Controller methods passed directly as handlers must not depend on `this`; otherwise bind them or define the handler as an arrow property.

## Context route file

```text
src/modules/<context>/infra/http/routes/<context>.routes.ts
```

```typescript
import type { FastifyInstance } from "fastify";

import { orderRoutes } from "../../order/http/routes/order.routes";

export async function salesRoutes(app: FastifyInstance): Promise<void> {
    await app.register(orderRoutes, { prefix: "/orders" });
}
```

The root router supplies the context prefix, so the final route is `/sales/orders`.

## Root route registry

```text
src/infra/http/routes/index.ts
```

```typescript
import { authRoutes } from "@/modules/iam/infra/user/http/routes/auth.routes";
import { salesRoutes } from "@/modules/sales/infra/http/routes/sales.routes";
import type { FastifyInstance } from "fastify";

import { ensureAuthenticated } from "../middlewares/ensure-authenticated";
import { healthRoutes } from "./health.routes";

export async function routes(app: FastifyInstance): Promise<void> {
    await app.register(healthRoutes, { prefix: "/health" });
    await app.register(authRoutes, { prefix: "/auth" });

    await app.register(async function protectedRoutes(securedRoutes) {
        securedRoutes.addHook("preHandler", ensureAuthenticated);
        securedRoutes.addHook("onRoute", (routeOptions) => {
            routeOptions.schema = {
                ...routeOptions.schema,
                security: [{ sessionAuth: [] }],
            };
        });

        await securedRoutes.register(salesRoutes, { prefix: "/sales" });
    });
}
```

Use Fastify encapsulation to apply authentication once to a protected route group. Keep health, login, callback, or other intentionally public routes outside that group.

External integration adapters may need a separate authenticated group and bearer guard. Register each adapter through one typed registry selected from validated configuration; inactive adapters should not publish routes.

## Route ordering

Register specific static paths before ambiguous parameter paths when the router could interpret them similarly:

```typescript
app.get("/external-id/:externalId", options);
app.get("/:id", options);
```

Keep action semantics explicit:

- `POST /orders` creates.
- `GET /orders/:id` reads.
- `PUT /orders/:id` replaces the updateable representation when the project uses PUT.
- `PATCH /orders/:id/status` changes one field.
- `POST /orders/:id/cancel` represents a domain command when cancel is not a simple field patch.
- `DELETE /orders/:id` deletes only when deletion is the actual domain behavior.

Follow the project's established HTTP semantics and compatibility promises before changing an existing route.

## Route rules

- Paths in entity route files are relative to their registered prefix.
- Each route declares method, path, permission, schema, and handler.
- Authentication is inherited from the protected group; authorization is declared per operation.
- Routes do not parse payloads, resolve use cases, access repositories, or catch business errors.
- Register each Module exactly once.
- Keep public and protected namespaces visibly separate.
- Keep adapter-specific routes inside their adapter plugin.
- Update OpenAPI security metadata when route grouping changes.

## Completion checklist

- The entity route is registered by its context route.
- The context route is registered by the root registry.
- Final prefixes and parameter names match schemas and E2E tests.
- Every protected operation has the exact permission key.
- Public routes are intentionally public.
- Controller handler and endpoint schema match the action.
- No duplicate or inactive adapter route is mounted.
