# Controllers

Controllers adapt Fastify to one application use case. They validate transport input, obtain authenticated context, resolve the use case, execute it once, present the result, and send an explicit status.

## File placement

```text
src/modules/<context>/infra/<entity>/controllers/<action>/
├── <action>-<entity>.controller.ts
└── <action>-<entity>.schema.ts
```

## Canonical create controller

```typescript
import HttpStatusCode from "@/core/enums/http-status-code";
import { getAuthContext } from "@/infra/http/auth/get-auth-context";
import { zodValidationSchema } from "@/infra/http/utils/zod/zod-validation-schema";
import { CreateOrderUseCase } from "@/modules/sales/application/order/use-cases/create/create-order-use-case";
import type { FastifyReply, FastifyRequest } from "fastify";
import { container } from "tsyringe";

import { OrderPresenter } from "../../presenters/order-presenter";
import { createOrderBodySchema } from "./create-order.schema";

export class CreateOrderController {
    async handle(
        request: FastifyRequest,
        reply: FastifyReply
    ): Promise<FastifyReply> {
        const { userId } = getAuthContext(request);

        const { externalId, customerId, priority } = zodValidationSchema(
            createOrderBodySchema,
            request.body
        );

        const createOrderUseCase = container.resolve(CreateOrderUseCase);

        const order = await createOrderUseCase.execute({
            externalId,
            customerId,
            priority,
            createdBy: userId,
        });

        return reply.status(HttpStatusCode.CREATED).send({
            order: OrderPresenter.toHTTP(order),
        });
    }
}
```

## Params and query

Validate each input source separately with its own schema:

```typescript
const { id } = zodValidationSchema(findOrderParamsSchema, request.params);

const { page, pageSize, status } = zodValidationSchema(
    listOrderQuerySchema,
    request.query
);
```

Do the same for headers when an endpoint owns a header contract. Authentication middleware owns session or bearer validation; the controller consumes the trusted context it establishes.

## Canonical list controller

```typescript
export class ListOrderController {
    async handle(
        request: FastifyRequest,
        reply: FastifyReply
    ): Promise<FastifyReply> {
        const { page, pageSize, allRecords, search } = zodValidationSchema(
            listOrderQuerySchema,
            request.query
        );

        const listOrderUseCase = container.resolve(ListOrderUseCase);

        const { orders, count } = await listOrderUseCase.execute({
            options: { page, pageSize, allRecords },
            search,
        });

        return reply.status(HttpStatusCode.OK).send({
            data: orders.map(OrderPresenter.toHTTP),
            meta: { count, page, pageSize },
        });
    }
}
```

## Presenter pattern

Use a presenter when the public response is not exactly the domain shape or when dates, private fields, nested values, or persisted names need controlled serialization.

```typescript
import type { PersistedOrder } from "@/modules/sales/domain/order/types/persisted-order";

export class OrderPresenter {
    static toHTTP(order: PersistedOrder) {
        return {
            id: order.id,
            externalId: order.externalId,
            customerId: order.customerId,
            priority: order.priority,
            status: order.status,
            createdAt: order.createdAt.toISOString(),
            updatedAt: order.updatedAt.toISOString(),
        };
    }
}
```

Never return secrets, password hashes, tokens, internal error causes, database column names, or fields the public contract does not own.

## Controller rules

- One controller class per endpoint action.
- One public `async handle(request, reply)` method.
- Resolve use cases through `container.resolve()`; do not instantiate repositories or concrete infrastructure.
- Invoke one primary use case. If several business operations must coordinate, create an orchestration use case.
- Pass authenticated actor/context explicitly to the use case.
- Use `HttpStatusCode`, not magic numbers.
- Let endpoint schemas define OpenAPI metadata and runtime contracts.
- Return a presenter shape, not persistence rows.
- Do not open transactions, write SQL, publish directly to a broker, or decide domain transitions.
- Do not add `try/catch` merely to map expected errors; the global error handler owns translation.

## Error flow

```text
controller -> use case throws typed error -> global error handler
           -> safe HTTP status and response body
```

Catch an error in a controller only when the endpoint itself owns a transport-specific recovery or translation that the global handler cannot represent. Keep the original typed error available for logging and correlation.

## Completion checklist

- Every request source is validated.
- Authentication context comes from a guard or session plugin.
- The controller resolves and calls the correct use case.
- Actor and operation scope are forwarded.
- Response status and presenter match the endpoint schema.
- No business rule or infrastructure implementation leaked into the controller.
- E2E coverage proves success, validation, auth/permission, and relevant error behavior.
