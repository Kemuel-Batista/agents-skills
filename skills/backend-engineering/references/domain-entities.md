# Domain Entities

Entities own valid domain state, defaults, and intrinsic transitions. They do not know Fastify, Zod, SQL, repositories, containers, HTTP status codes, or external SDKs.

## File placement

```text
src/modules/<context>/domain/<entity>/
├── entities/<entity>.ts
├── enums/<entity>-status.ts
├── errors/
├── types/persisted-<entity>.ts
└── value-objects/
```

Use a value object when validation and behavior belong to one conceptual value. Use an entity when identity and lifecycle matter. Keep cross-aggregate orchestration in application use cases or a named domain service/policy.

## Enum pattern

Prefer an `as const` object when numeric values must match a persisted or external contract:

```typescript
export const OrderStatus = {
    PENDING: 1,
    PROCESSING: 2,
    COMPLETED: 3,
    CANCELLED: 4,
} as const;

export type OrderStatus = (typeof OrderStatus)[keyof typeof OrderStatus];
```

Values are compatibility contracts. Changing them requires a migration and impact review across database rows, APIs, events, permissions, tests, and integrations.

## Canonical entity

```typescript
import type { Optional } from "@/core/types/optional";

import { InvalidDomainStateError } from "../errors/invalid-domain-state-error";
import { OrderPriority } from "../enums/order-priority";
import { OrderStatus, type OrderStatus as OrderStatusValue } from "../enums/order-status";

export interface OrderProps {
    id?: number;
    externalId: string;
    customerId: number;
    priority: OrderPriority;
    status: OrderStatusValue;
    createdBy: number;
    updatedBy: number;
    createdAt: Date;
    updatedAt: Date;
}

type CreateOrderProps = Optional<
    OrderProps,
    "id" | "priority" | "status" | "updatedBy" | "createdAt" | "updatedAt"
>;

export class Order {
    id?: number;
    externalId: string;
    customerId: number;
    priority: OrderPriority;
    status: OrderStatusValue;
    createdBy: number;
    updatedBy: number;
    createdAt: Date;
    updatedAt: Date;

    private constructor(props: OrderProps) {
        this.id = props.id;
        this.externalId = props.externalId;
        this.customerId = props.customerId;
        this.priority = props.priority;
        this.status = props.status;
        this.createdBy = props.createdBy;
        this.updatedBy = props.updatedBy;
        this.createdAt = props.createdAt;
        this.updatedAt = props.updatedAt;
    }

    static create(props: CreateOrderProps): Order {
        const now = new Date();

        return new Order({
            ...props,
            priority: props.priority ?? OrderPriority.NORMAL,
            status: props.status ?? OrderStatus.PENDING,
            updatedBy: props.updatedBy ?? props.createdBy,
            createdAt: props.createdAt ?? now,
            updatedAt: props.updatedAt ?? now,
        });
    }

    cancel(updatedBy: number, now = new Date()): void {
        if (
            this.status === OrderStatus.COMPLETED ||
            this.status === OrderStatus.CANCELLED
        ) {
            throw new InvalidDomainStateError("order.cancel.invalid-status", {
                status: this.status,
            });
        }

        this.status = OrderStatus.CANCELLED;
        this.updatedBy = updatedBy;
        this.updatedAt = now;
    }
}
```

The private constructor forces callers through a named factory. The factory applies defaults in one place and supports database rehydration by accepting explicit identity and timestamps.

## State rules

- Put a transition on the entity when it depends only on that entity's current state and inputs.
- Reject invalid transitions with a typed domain error and stable key.
- Update audit fields in the same transition that changes state.
- Pass a clock value into time-sensitive behavior or inject a clock at the application Seam; tests must not race the wall clock.
- Keep setters unavailable when an unrestricted assignment could violate an invariant.
- Do not perform database reads, publish messages, or resolve dependencies from an entity.
- Do not create a method that only mirrors a property assignment without protecting an invariant.

For invariants requiring other aggregates or persistence facts, let the use case load the required state and invoke a domain policy or entity transition inside its transaction.

## Nullable and optional values

- Optional means the field may be omitted from the operation.
- Nullable means `null` is an intentional domain value.
- Do not use both unless the two states have distinct meaning.
- Normalize transport-specific empty strings or coercions before entity construction.
- Preserve omitted-versus-null semantics in update requests and mappers.

## Persisted type

```typescript
import type { PersistedEntity } from "@/core/entities/persisted-entity";

import type { Order } from "../entities/order";

export type PersistedOrder = PersistedEntity<Order>;
```

Use the plain entity before persistence and the persisted type after a successful repository write or database read. Do not mark `id` as always present on a newly created entity just to satisfy infrastructure typing.

## Value-object pattern

```typescript
export class ExternalOrderId {
    private constructor(public readonly value: string) {}

    static create(input: string): ExternalOrderId {
        const value = input.trim().toUpperCase();

        if (!/^[A-Z0-9-]{1,80}$/.test(value)) {
            throw new InvalidDomainStateError("order.external-id.invalid");
        }

        return new ExternalOrderId(value);
    }

    equals(other: ExternalOrderId): boolean {
        return this.value === other.value;
    }
}
```

Create a value object only when its normalization, validation, equality, or behavior repays the extra type. Keep trivial primitives trivial.

## Completion checklist

- Entity name and fields use canonical domain language.
- Constructor is private and creation/rehydration passes through a named factory.
- Defaults and intrinsic invariants have one owner.
- State transitions are named business verbs and reject invalid states.
- Time, actor, identity, and nullability semantics are explicit.
- Entity imports no application or infrastructure code.
- Persisted identity is modeled separately when creation starts without an ID.
- Unit tests cover defaults, valid transitions, invalid transitions, boundaries, and deterministic time behavior.
