# Repositories, Mappers, and Providers

Persistence is an Adapter behind a domain-owned repository Interface. The domain speaks in entities and value types; infrastructure translates those values into parameterized SQL and registers the concrete implementation in one composition root.

## Repository Interface

Place the contract with the domain:

```text
src/modules/<context>/domain/<entity>/repositories/<entity>-repository.ts
```

```typescript
import type { DatabaseOptions } from "@/core/types/database-options";
import type { ListResult } from "@/core/types/list-result";

import type { Order } from "../entities/order";
import type { PersistedOrder } from "../types/persisted-order";

export interface ListOrderOptions {
    page: number;
    pageSize: number;
    allRecords?: boolean;
    status?: Order["status"];
    search?: string;
}

export abstract class OrderRepository {
    abstract create(
        order: Order,
        databaseOptions?: DatabaseOptions
    ): Promise<PersistedOrder>;

    abstract findById(
        id: Order["id"],
        databaseOptions?: DatabaseOptions
    ): Promise<PersistedOrder | null>;

    abstract findByExternalId(
        externalId: Order["externalId"],
        databaseOptions?: DatabaseOptions
    ): Promise<PersistedOrder | null>;

    abstract list(
        options: ListOrderOptions,
        databaseOptions?: DatabaseOptions
    ): Promise<ListResult<PersistedOrder>>;

    abstract update(
        order: PersistedOrder,
        databaseOptions?: DatabaseOptions
    ): Promise<PersistedOrder>;

    abstract delete(
        id: Order["id"],
        databaseOptions?: DatabaseOptions
    ): Promise<void>;
}
```

Use an abstract class when its constructor token is the class itself. If the project uses string or symbol tokens consistently, an `interface` is also valid. Do not expose SQL rows, query builders, connections, transactions, or dialect-specific types through this contract.

## Persisted entity type

Creation-time entities may not have a database identifier. Model the successful persisted state explicitly:

```typescript
import type { PersistedEntity } from "@/core/entities/persisted-entity";

import type { Order } from "../entities/order";

export type PersistedOrder = PersistedEntity<Order>;
```

Keep the one unavoidable persistence assertion in the mapper, not scattered across use cases.

## Mapper

```text
src/modules/<context>/infra/<entity>/database/mappers/<entity>-mapper.ts
```

```typescript
import type { DatabaseRecord } from "@/core/types/database-record";
import type { PersistedEntity } from "@/core/entities/persisted-entity";
import { Order } from "@/modules/sales/domain/order/entities/order";

export type OrderPersistence = DatabaseRecord & {
    id: number;
    external_id: string;
    customer_id: number;
    priority: number;
    status: number;
    created_by: number;
    updated_by: number;
    created_at: Date;
    updated_at: Date;
};

export class OrderMapper {
    static toDomain(raw: OrderPersistence): PersistedEntity<Order> {
        return Order.create(
            {
                externalId: raw.external_id,
                customerId: raw.customer_id,
                priority: raw.priority,
                status: raw.status,
                createdBy: raw.created_by,
                updatedBy: raw.updated_by,
                createdAt: raw.created_at,
                updatedAt: raw.updated_at,
            },
            raw.id
        ) as PersistedEntity<Order>;
    }

    static toPersistence(order: Order): Omit<OrderPersistence, "id"> {
        return {
            external_id: order.externalId,
            customer_id: order.customerId,
            priority: order.priority,
            status: order.status,
            created_by: order.createdBy,
            updated_by: order.updatedBy,
            created_at: order.createdAt,
            updated_at: order.updatedAt,
        };
    }
}
```

The mapper is the only place that knows both column names and domain construction. It performs shape translation, not queries, authorization, defaults that belong to the entity, or business transitions.

## SQL repository

Use one repository implementation with an injected dialect when the supported databases differ only in SQL mechanics. Split implementations only when their behavior or data model genuinely diverges.

```typescript
import { DatabaseError } from "@/core/errors";
import type { DatabaseOptions } from "@/core/types/database-options";
import type { DatabaseClient } from "@/infra/database/database-client";
import type { SqlDialect } from "@/infra/database/dialect/sql-dialect";
import type { Order } from "@/modules/sales/domain/order/entities/order";
import {
    type ListOrderOptions,
    OrderRepository,
} from "@/modules/sales/domain/order/repositories/order-repository";
import type { PersistedOrder } from "@/modules/sales/domain/order/types/persisted-order";
import { inject, injectable } from "tsyringe";

import { OrderMapper, type OrderPersistence } from "../mappers/order-mapper";

@injectable()
export class SqlOrderRepository implements OrderRepository {
    private readonly insertColumns = [
        "external_id",
        "customer_id",
        "priority",
        "status",
        "created_by",
        "updated_by",
        "created_at",
        "updated_at",
    ] as const;

    constructor(
        @inject("DatabaseClient")
        private readonly databaseClient: DatabaseClient,
        @inject("SqlDialect")
        private readonly dialect: SqlDialect
    ) {}

    async create(
        order: Order,
        databaseOptions?: DatabaseOptions
    ): Promise<PersistedOrder> {
        const values = OrderMapper.toPersistence(order);
        const parameters = Object.fromEntries(
            this.insertColumns.map((column) => [column, values[column]])
        );

        const result = await this.databaseClient.query<OrderPersistence>({
            sql: this.dialect.insertReturning({
                table: "orders",
                columns: [...this.insertColumns],
                returning: ["*"],
            }),
            parameters,
            options: databaseOptions,
        });

        const raw = result.records[0];

        if (!raw) {
            throw new DatabaseError("order.persistence.create.empty-result");
        }

        return OrderMapper.toDomain(raw);
    }

    async findById(
        id: Order["id"],
        databaseOptions?: DatabaseOptions
    ): Promise<PersistedOrder | null> {
        const result = await this.databaseClient.query<OrderPersistence>({
            sql: "SELECT * FROM orders WHERE id = @id",
            parameters: { id },
            options: databaseOptions,
        });

        return result.records[0]
            ? OrderMapper.toDomain(result.records[0])
            : null;
    }

    async list(
        options: ListOrderOptions,
        databaseOptions?: DatabaseOptions
    ) {
        const query = this.dialect.paginatedSelect({
            table: "orders",
            page: options.page,
            pageSize: options.pageSize,
            allRecords: options.allRecords,
            filters: {
                status: options.status,
                search: options.search,
            },
            orderBy: [{ column: "created_at", direction: "DESC" }],
        });

        const [records, count] = await Promise.all([
            this.databaseClient.query<OrderPersistence>({
                ...query.records,
                options: databaseOptions,
            }),
            this.databaseClient.query<{ count: number }>({
                ...query.count,
                options: databaseOptions,
            }),
        ]);

        return {
            data: records.records.map(OrderMapper.toDomain),
            count: count.records[0]?.count ?? 0,
        };
    }
}
```

Adapt method names to the actual database client; preserve the boundaries and guarantees shown here.

### Query rules

- Parameterize every untrusted value. Never interpolate values into SQL text.
- Keep identifier allowlists inside dialect/query-builder code; identifiers cannot be protected by value parameters.
- Use one ordered column list as the source for INSERT columns and parameters.
- Return mapped domain values, never driver records.
- Apply deterministic ordering before pagination.
- Execute count and page queries against the same filter semantics.
- Pass `databaseOptions` to every query participating in a transaction.
- Translate driver failures into typed infrastructure/application errors at a stable boundary without discarding the original cause used for internal logs.
- Use the injected dialect for placeholders, pagination, returning/output clauses, quoting, date expressions, and locking syntax.

## Transactions

Expose an infrastructure-neutral transaction carrier:

```typescript
export interface DatabaseOptions {
    transaction?: DatabaseTransaction;
}
```

The application coordinator owns atomicity. A transaction helper reuses an incoming transaction or starts, commits, and rolls back one new transaction:

```typescript
await runInTransaction({
    databaseClient,
    databaseOptions,
    execute: async (transaction) => {
        await firstUseCase.execute({
            databaseOptions: { transaction },
        });
        await secondUseCase.execute({
            databaseOptions: { transaction },
        });
    },
});
```

Do not expose the concrete driver transaction outside infrastructure types or open transactions inside controllers and routes.

## Provider registration

Register each Adapter once, close to the Module:

```typescript
import { OrderRepository } from "@/modules/sales/domain/order/repositories/order-repository";
import { container } from "tsyringe";

import { SqlOrderRepository } from "../database/repositories/order-repository";

container.registerSingleton<OrderRepository>(
    "OrderRepository",
    SqlOrderRepository
);
```

Aggregate providers with side-effect imports only at composition roots:

```typescript
// src/modules/sales/infra/providers/index.ts
import "../order/providers";

// src/infra/providers/index.ts
import "@/infra/database/providers";
import "@/modules/iam/infra/providers";
import "@/modules/sales/infra/providers";
```

Rules:

- One stable token per Interface; avoid string aliases for the same dependency.
- Register database client and dialect before repositories that consume them.
- Do not import provider side effects from domain or application files.
- Unit tests construct use cases explicitly and never depend on this registry.
- E2E and production startup load the same provider graph, with only external resources configured for the environment.

## Migrations

Use timestamp-prefixed, immutable SQL files:

```text
src/infra/database/<dialect>/migrations/
└── 20260824153000_create_orders_table.sql
```

```sql
CREATE TABLE orders (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    external_id VARCHAR(80) NOT NULL,
    customer_id BIGINT NOT NULL,
    priority SMALLINT NOT NULL,
    status SMALLINT NOT NULL,
    created_by BIGINT NOT NULL,
    updated_by BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT uq_orders_external_id UNIQUE (external_id)
);

CREATE INDEX ix_orders_status_created_at
    ON orders (status, created_at DESC);
```

Use syntax and types appropriate to the selected database. When the product supports more than one dialect, create one migration with equivalent semantics under each dialect directory and exercise both in CI.

- Make every schema change through a committed migration; never rely on application startup to mutate production schema.
- Write forward-safe changes for rolling deployments: add before use, backfill, switch readers/writers, then remove in a later release.
- Never edit an already released migration; add a new corrective migration.
- Name constraints and indexes deterministically.
- Add indexes from real query and uniqueness requirements.
- Preserve parity across supported dialects or document an explicit feature boundary.
- Test migrations from an empty database and from the previous released schema.

## Completion checklist

- Domain Interface contains no SQL, driver, or transport types.
- Mapper is the only database/domain shape translator.
- Repository queries are parameterized and dialect-aware.
- List count, filters, ordering, and pagination agree.
- Transaction options reach every persistent operation.
- Provider registration is unique and reachable from bootstrap.
- Migration and indexes support the repository behavior.
- Unit tests use the in-memory implementation; E2E proves the SQL implementation and wiring.
