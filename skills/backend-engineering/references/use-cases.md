# Use Cases

Application behavior lives in one class per operation. Use a typed request, a typed response, constructor injection, and one public `async execute()` method.

## File placement and name

```text
src/modules/<context>/application/<entity>/use-cases/<action>/
└── <action>-<entity>-use-case.ts
```

Examples:

```text
use-cases/create/create-order-use-case.ts
use-cases/find/by-id/find-order-by-id-use-case.ts
use-cases/list/default/list-order-use-case.ts
use-cases/actions/cancel/cancel-order-use-case.ts
```

Use CRUD folders only for CRUD behavior. Put domain transitions such as cancel, execute, approve, retry, allocate, or reconcile under `actions/` with the business verb in the file name.

## Canonical create use case

```typescript
import type { DatabaseOptions } from "@/core/types/database-options";
import { CreateAuditLogUseCase } from "@/modules/core/application/audit-log/use-cases/create/create-audit-log-use-case";
import { Order } from "@/modules/sales/domain/order/entities/order";
import type { OrderRepository } from "@/modules/sales/domain/order/repositories/order-repository";
import type { PersistedOrder } from "@/modules/sales/domain/order/types/persisted-order";
import { inject, injectable } from "tsyringe";

import { FindOrderByExternalIdUseCase } from "../find/by-external-id/find-order-by-external-id-use-case";

interface CreateOrderUseCaseRequest {
    externalId: Order["externalId"];
    customerId: Order["customerId"];
    priority?: Order["priority"];
    createdBy: Order["createdBy"];
    databaseOptions?: DatabaseOptions;
}

type CreateOrderUseCaseResponse = PersistedOrder;

@injectable()
export class CreateOrderUseCase {
    constructor(
        @inject(FindOrderByExternalIdUseCase)
        private readonly findOrderByExternalIdUseCase: FindOrderByExternalIdUseCase,
        @inject("OrderRepository")
        private readonly orderRepository: OrderRepository,
        @inject(CreateAuditLogUseCase)
        private readonly createAuditLogUseCase: CreateAuditLogUseCase
    ) {}

    async execute({
        externalId,
        customerId,
        priority,
        createdBy,
        databaseOptions,
    }: CreateOrderUseCaseRequest): Promise<CreateOrderUseCaseResponse> {
        await this.findOrderByExternalIdUseCase.execute({
            externalId,
            options: { throwIfFound: true },
            databaseOptions,
        });

        const newOrder = Order.create({
            externalId,
            customerId,
            priority,
            createdBy,
            updatedBy: createdBy,
        });

        const order = await this.orderRepository.create(
            newOrder,
            databaseOptions
        );

        await this.createAuditLogUseCase.execute({
            action: "CREATE",
            entity: "Order",
            entityId: order.id,
            oldValues: null,
            newValues: {
                externalId: order.externalId,
                customerId: order.customerId,
                priority: order.priority,
                status: order.status,
            },
            userId: createdBy,
            databaseOptions,
        });

        return order;
    }
}
```

## Request pattern

- Name it `<UseCaseName>Request`.
- Use an `interface` for an object-shaped request.
- Derive field types from domain sources, such as `Order["externalId"]`, instead of repeating primitives.
- Include only data the operation needs.
- Include actor, operation, or tenant context when the invariant needs it.
- Include `databaseOptions?: DatabaseOptions` for persistent operations that can join a transaction.
- Keep the request local to the file unless another Module genuinely consumes the type.
- Model conditional input with a discriminated union instead of unrelated optional fields.

## Response pattern

- Name it `<UseCaseName>Response`.
- Use a `type` alias.
- Return the domain result callers need; avoid transport response shapes.
- Use a persisted type when a successful write guarantees a non-null identifier.
- Use `void` only when no result or state is useful to callers.
- Express multiple valid outcomes as a discriminated union.

Examples:

```typescript
type FindOrderByIdUseCaseResponse = PersistedOrder | null;

type CancelOrderUseCaseResponse = {
    order: PersistedOrder;
    alreadyCancelled: boolean;
};
```

## Find/list use cases

Expose reusable reads as named application operations. Other orchestration use cases call these operations instead of duplicating repository search logic.

```typescript
import { ConflictError, NotFoundError } from "@/core/errors";

interface FindOrderByIdUseCaseRequest {
    id: Order["id"];
    options?: {
        throwIfFound?: boolean;
        throwIfNotFound?: boolean;
    };
    databaseOptions?: DatabaseOptions;
}

type FindOrderByIdUseCaseResponse = PersistedOrder | null;

@injectable()
export class FindOrderByIdUseCase {
    constructor(
        @inject("OrderRepository")
        private readonly orderRepository: OrderRepository
    ) {}

    async execute({
        id,
        options,
        databaseOptions,
    }: FindOrderByIdUseCaseRequest): Promise<FindOrderByIdUseCaseResponse> {
        const order = await this.orderRepository.findById(id, databaseOptions);

        if (order && options?.throwIfFound) {
            throw new ConflictError("order.found.by-id");
        }

        if (!order && options?.throwIfNotFound) {
            throw new NotFoundError("order.not-found.by-id");
        }

        return order;
    }
}
```

Repository access belongs in the use case whose responsibility is that persistence operation. A higher-level orchestration use case should reuse a find/list/create/update/delete use case when one already expresses the needed behavior.

## Transaction-owning use cases

The coordinator that owns the atomic invariant owns the transaction:

```typescript
await runInTransaction({
    databaseClient: this.databaseClient,
    databaseOptions,
    execute: async (transaction) => {
        const transactionOptions = { transaction };

        const order = await this.findOrderByIdUseCase.execute({
            id,
            options: { throwIfNotFound: true },
            databaseOptions: transactionOptions,
        });

        order.cancel(updatedBy);

        await this.updateOrderUseCase.execute({
            order,
            databaseOptions: transactionOptions,
        });
    },
});
```

- Pass the same transaction to every nested persistence operation.
- Reuse an incoming transaction when the operation is composable.
- Do not open a transaction in controllers, routes, mappers, or presenters.
- Make independent post-rollback recording explicit when failure state must survive an operational rollback.

## Error pattern

Throw typed application/domain errors with stable keys. Let the global Fastify error handler map them to HTTP.

```typescript
throw new NotFoundError("order.not-found.by-id");
throw new ConflictError("order.found.by-external-id");
throw new ForbiddenError("order.cancel.forbidden");
```

Use cases do not import `FastifyRequest`, `FastifyReply`, status codes, OpenAPI schemas, or controllers.

## Completion checklist

- Request and response types match the application Interface.
- The class is `@injectable()` and dependencies are constructor-injected.
- The only public operation is `async execute()`.
- Domain rules stay in domain objects or policies; orchestration stays here.
- Reads reuse existing find/list use cases when appropriate.
- Persistent calls propagate `databaseOptions`.
- Errors are typed and transport-independent.
- Audit, idempotency, transaction, queue, and observability effects required by the behavior are present.
- Focused unit tests cover every meaningful branch.
