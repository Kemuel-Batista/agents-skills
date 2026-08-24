# Unit Tests

Unit tests prove domain and application behavior through explicit construction. The real subject is combined only with test-owned factories, fakes, and in-memory repository implementations.

## Hard boundary

A unit spec may import:

- the production entity, policy, service, or use case under test;
- another production domain/application operation needed to construct the subject;
- `in-memory-*-repository` files from `test`;
- `fake-*` or `stub-*` test Adapters from `test`;
- `make-*` factories and deterministic test utilities from `test`;
- Vitest primitives.

A unit spec must never:

- import a SQL/ORM repository, database client, dialect, migration, Fastify app, controller, route, provider registry, cache client, queue client, filesystem Adapter, or remote SDK;
- call `container.resolve()`, load `src/infra/providers`, boot Fastify, or use Supertest;
- connect to Postgres, SQL Server, Redis, a broker, the network, or real storage;
- use `vi.mock()` to replace an internal Module, repository, or use case that can be supplied through the constructor;
- assert SQL, HTTP status, route registration, framework wiring, or private methods.

If the subject cannot be constructed under this boundary, improve its constructor Seam. Do not weaken the test by importing production infrastructure.

## File placement and name

```text
test/modules/<context>/application/<entity>/use-cases/<action>/
└── <action>-<entity>-use-case.spec.ts
```

Mirror the production path. Keep reusable test artifacts here:

```text
test/modules/<context>/domain/<entity>/entities/make-<entity>.ts
test/modules/<context>/infra/<entity>/repositories/in-memory-<entity>-repository.ts
test/modules/<context>/infra/<port>/fake-<port>.ts
```

Production code never imports `@test/*`.

## Canonical use-case spec

```typescript
import { CreateOrderUseCase } from "@/modules/sales/application/order/use-cases/create/create-order-use-case";
import { FindOrderByExternalIdUseCase } from "@/modules/sales/application/order/use-cases/find/by-external-id/find-order-by-external-id-use-case";
import { CreateAuditLogUseCase } from "@/modules/core/application/audit-log/use-cases/create/create-audit-log-use-case";
import { beforeEach, describe, expect, it } from "vitest";

import { InMemoryAuditLogRepository } from "@test/modules/core/infra/audit-log/repositories/in-memory-audit-log-repository";
import { makeOrder } from "@test/modules/sales/domain/order/entities/make-order";
import { InMemoryOrderRepository } from "@test/modules/sales/infra/order/repositories/in-memory-order-repository";

describe("CreateOrderUseCase", () => {
    let orderRepository: InMemoryOrderRepository;
    let auditLogRepository: InMemoryAuditLogRepository;
    let createAuditLogUseCase: CreateAuditLogUseCase;
    let findOrderByExternalIdUseCase: FindOrderByExternalIdUseCase;
    let sut: CreateOrderUseCase;

    beforeEach(() => {
        orderRepository = new InMemoryOrderRepository();
        auditLogRepository = new InMemoryAuditLogRepository();

        findOrderByExternalIdUseCase = new FindOrderByExternalIdUseCase(
            orderRepository
        );
        createAuditLogUseCase = new CreateAuditLogUseCase(auditLogRepository);

        sut = new CreateOrderUseCase(
            findOrderByExternalIdUseCase,
            orderRepository,
            createAuditLogUseCase
        );
    });

    it("creates and audits an order", async () => {
        const order = await sut.execute({
            externalId: "ORDER-001",
            customerId: 42,
            createdBy: 7,
        });

        expect(order).toEqual(
            expect.objectContaining({
                id: expect.any(Number),
                externalId: "ORDER-001",
                customerId: 42,
                createdBy: 7,
            })
        );
        expect(orderRepository.items).toHaveLength(1);
        expect(auditLogRepository.items).toEqual([
            expect.objectContaining({
                action: "CREATE",
                entity: "Order",
                entityId: order.id,
                userId: 7,
            }),
        ]);
    });

    it("rejects a duplicate external ID without side effects", async () => {
        orderRepository.items.push(
            makeOrder({ externalId: "ORDER-001" }, 100)
        );

        await expect(
            sut.execute({
                externalId: "ORDER-001",
                customerId: 42,
                createdBy: 7,
            })
        ).rejects.toMatchObject({
            key: "order.found.by-external-id",
        });

        expect(orderRepository.items).toHaveLength(1);
        expect(auditLogRepository.items).toHaveLength(0);
    });
});
```

Use `sut` for the subject under test. Recreate mutable collaborators in `beforeEach`; tests must not depend on execution order.

## In-memory repository pattern

An in-memory repository implements the same domain contract with deterministic in-process state. It models repository semantics required by application tests; it does not imitate SQL syntax or database driver behavior.

```typescript
import type { DatabaseOptions } from "@/core/types/database-options";
import type { Order } from "@/modules/sales/domain/order/entities/order";
import {
    type ListOrderOptions,
    OrderRepository,
} from "@/modules/sales/domain/order/repositories/order-repository";
import type { PersistedOrder } from "@/modules/sales/domain/order/types/persisted-order";

import { makeOrder } from "@test/modules/sales/domain/order/entities/make-order";

export class InMemoryOrderRepository implements OrderRepository {
    public items: PersistedOrder[] = [];
    private nextId = 1;

    async create(
        order: Order,
        _databaseOptions?: DatabaseOptions
    ): Promise<PersistedOrder> {
        const persisted = makeOrder(
            {
                externalId: order.externalId,
                customerId: order.customerId,
                priority: order.priority,
                status: order.status,
                createdBy: order.createdBy,
                updatedBy: order.updatedBy,
                createdAt: order.createdAt,
                updatedAt: order.updatedAt,
            },
            this.nextId++
        );

        this.items.push(persisted);
        return persisted;
    }

    async findById(
        id: Order["id"],
        _databaseOptions?: DatabaseOptions
    ): Promise<PersistedOrder | null> {
        return this.items.find((item) => item.id === id) ?? null;
    }

    async findByExternalId(
        externalId: Order["externalId"],
        _databaseOptions?: DatabaseOptions
    ): Promise<PersistedOrder | null> {
        return (
            this.items.find((item) => item.externalId === externalId) ?? null
        );
    }

    async list(
        options: ListOrderOptions,
        _databaseOptions?: DatabaseOptions
    ) {
        const normalizedSearch = options.search?.toLocaleLowerCase();
        const filtered = this.items.filter((item) => {
            const matchesStatus =
                options.status === undefined || item.status === options.status;
            const matchesSearch =
                !normalizedSearch ||
                item.externalId.toLocaleLowerCase().includes(normalizedSearch);

            return matchesStatus && matchesSearch;
        });

        const start = (options.page - 1) * options.pageSize;
        const data = options.allRecords
            ? filtered
            : filtered.slice(start, start + options.pageSize);

        return { data, count: filtered.length };
    }

    async update(
        order: PersistedOrder,
        _databaseOptions?: DatabaseOptions
    ): Promise<PersistedOrder> {
        const index = this.items.findIndex((item) => item.id === order.id);

        if (index === -1) {
            throw new Error("In-memory order not found");
        }

        this.items[index] = order;
        return order;
    }

    async delete(
        id: Order["id"],
        _databaseOptions?: DatabaseOptions
    ): Promise<void> {
        this.items = this.items.filter((item) => item.id !== id);
    }
}
```

Requirements:

- Implement the real repository Interface; a contract change should break both SQL and in-memory implementations at compile time.
- Keep `items` public when state assertions make tests clearer.
- Generate deterministic IDs and reset state by constructing a new repository per test.
- Match null/not-found, uniqueness, filtering, ordering, pagination, and update semantics that use cases depend on.
- Ignore `DatabaseOptions` unless transaction behavior itself is the subject. Test transaction orchestration with a dedicated fake transaction runner, not a database.
- Do not implement SQL features, latency, driver errors, locking, or database constraints here; those belong in integration/E2E coverage.

## Factory pattern

```typescript
import { Order } from "@/modules/sales/domain/order/entities/order";
import { OrderPriority } from "@/modules/sales/domain/order/enums/order-priority";
import { OrderStatus } from "@/modules/sales/domain/order/enums/order-status";
import type { PersistedOrder } from "@/modules/sales/domain/order/types/persisted-order";

type OrderOverrides = Partial<{
    externalId: string;
    customerId: number;
    priority: OrderPriority;
    status: OrderStatus;
    createdBy: number;
    updatedBy: number;
    createdAt: Date;
    updatedAt: Date;
}>;

let sequence = 1;

export function makeOrder(
    overrides: OrderOverrides = {},
    id = sequence++
): PersistedOrder {
    return Order.create(
        {
            externalId: `ORDER-${id}`,
            customerId: 1,
            priority: OrderPriority.NORMAL,
            status: OrderStatus.PENDING,
            createdBy: 1,
            updatedBy: 1,
            createdAt: new Date("2025-01-01T00:00:00.000Z"),
            updatedAt: new Date("2025-01-01T00:00:00.000Z"),
            ...overrides,
        },
        id
    ) as PersistedOrder;
}
```

Defaults are valid, explicit, and deterministic. Override only fields relevant to the scenario. Random data may be used for uniqueness, but never make expected behavior depend on randomness or the current clock.

## Fake Adapter pattern

Use a stateful fake for an injected non-repository port:

```typescript
export class FakeAuditLog implements AuditLogPort {
    public entries: CreateAuditLogInput[] = [];

    async create(input: CreateAuditLogInput): Promise<void> {
        this.entries.push(structuredClone(input));
    }
}
```

Expose captured inputs and configurable results/errors. Prefer fakes over call-count mocks because state and observable messages explain behavior more clearly.

## Complex setup

When explicit wiring becomes repetitive, create a test context function that still constructs every dependency visibly:

```typescript
function makeSut() {
    const orderRepository = new InMemoryOrderRepository();
    const auditLogRepository = new InMemoryAuditLogRepository();
    const createAuditLog = new CreateAuditLogUseCase(auditLogRepository);
    const findOrder = new FindOrderByExternalIdUseCase(orderRepository);
    const sut = new CreateOrderUseCase(
        findOrder,
        orderRepository,
        createAuditLog
    );

    return { sut, orderRepository, auditLogRepository };
}
```

Do not turn `makeSut()` into a hidden production container. Return every collaborator a test may seed or inspect.

## Scenario matrix

Cover branches with observable consequences:

- successful result and persisted state;
- default values and boundary values;
- not-found, conflict, invalid transition, and authorization errors;
- idempotent retry or duplicate handling;
- rollback/compensation orchestration through fake transaction or port state;
- emitted audit/event/queue payloads when part of the application contract;
- no partial side effects after a rejected operation;
- list filter, pagination, ordering, and count semantics.

Avoid one assertion per implementation line. A focused scenario may assert its returned value and all relevant state changes.

## Execution order

Keep unit selection explicit in the base Vitest configuration:

```typescript
test: {
    include: ["test/**/*.spec.ts"],
    exclude: ["test/**/*.e2e-spec.ts"],
    setupFiles: ["./test/test-setup.ts"],
    coverage: {
        provider: "v8",
        include: ["src/**/*-use-case.ts"],
    },
}
```

The unit setup file may register deterministic global test Adapters only when a cross-cutting application dependency makes that necessary. A focused spec still constructs and owns the collaborators that affect its behavior.

Run the exact spec first, then the unit suite:

```bash
bun vitest run test/modules/sales/application/order/use-cases/create/create-order-use-case.spec.ts
bun test
```

Use only commands present in the target repository. Unit selection must exclude `*.e2e-spec.ts`.

## Completion checklist

- Spec mirrors the production file path and uses `*.spec.ts`.
- Subject and mutable collaborators are recreated per test.
- Imports contain no production infrastructure.
- Every repository is an `InMemory*Repository` from `test`.
- Every remote/cache/queue/clock/ID dependency is a deterministic test Adapter.
- No app, container, Supertest, database, Redis, broker, filesystem, network, or internal Module mock is used.
- Assertions target public results, typed errors, repository state, and emitted port state.
- Failure scenarios prove absence of invalid partial effects.
- Focused and full unit commands pass with observed output.
