# Schemas

Each endpoint action owns runtime validation and OpenAPI metadata in a colocated `*.schema.ts` file. Shared entity response schemas live under the entity's `schemas/` folder.

## File placement

```text
src/modules/<context>/infra/<entity>/
├── controllers/<action>/<action>-<entity>.schema.ts
└── schemas/<entity>.shared.schema.ts
```

## Request schemas

```typescript
import { OrderPriority } from "@/modules/sales/domain/order/enums/order-priority";
import { OrderStatus } from "@/modules/sales/domain/order/enums/order-status";
import { z } from "zod";

export const createOrderBodySchema = z.object({
    externalId: z.string().trim().min(1).max(80),
    customerId: z.coerce.number().int().positive(),
    priority: z.enum(OrderPriority).default(OrderPriority.NORMAL),
});

export const findOrderParamsSchema = z.object({
    id: z.coerce.number().int().positive(),
});

export const listOrderQuerySchema = z.object({
    page: z.coerce.number().int().positive().default(1),
    pageSize: z.coerce.number().int().min(1).max(100).default(20),
    allRecords: z.coerce.boolean().default(false),
    status: z.enum(OrderStatus).optional(),
    search: z.string().trim().min(1).max(120).optional(),
});

export type CreateOrderBody = z.infer<typeof createOrderBodySchema>;
```

Use coercion for params/query values Fastify receives as strings. For JSON body fields, use coercion only when the public contract intentionally accepts string representations.

Validate:

- required versus optional versus nullable semantics;
- trimming and empty strings;
- string length and format;
- integer, sign, range, and decimal precision;
- enums and discriminated variants;
- array length and per-item constraints;
- cross-field rules with `refine` or `superRefine` when the rule belongs to the transport contract.

Domain invariants still belong in domain/application code. Zod protects the delivery Seam; it does not replace domain validation.

## Shared response schema

```typescript
import { OrderPriority } from "@/modules/sales/domain/order/enums/order-priority";
import { OrderStatus } from "@/modules/sales/domain/order/enums/order-status";

export const orderTag = "Orders";
export const orderSecurity = [{ sessionAuth: [] }];

export const orderSchema = {
    type: "object",
    required: [
        "id",
        "externalId",
        "customerId",
        "priority",
        "status",
        "createdAt",
        "updatedAt",
    ],
    properties: {
        id: { type: "integer", minimum: 1 },
        externalId: { type: "string" },
        customerId: { type: "integer", minimum: 1 },
        priority: {
            type: "number",
            enum: Object.values(OrderPriority),
        },
        status: {
            type: "number",
            enum: Object.values(OrderStatus),
        },
        createdAt: { type: "string", format: "date-time" },
        updatedAt: { type: "string", format: "date-time" },
    },
} as const;

export const orderResponseSchema = {
    type: "object",
    required: ["order"],
    properties: {
        order: orderSchema,
    },
} as const;
```

The response schema must match the presenter exactly, including nullability, date serialization, field names, nesting, and required fields.

## Endpoint OpenAPI schema

```typescript
import HttpStatusCode from "@/core/enums/http-status-code";
import { commonResponses } from "@/infra/schemas/openapi/common-responses.schema";
import { OrderPriority } from "@/modules/sales/domain/order/enums/order-priority";

import {
    orderResponseSchema,
    orderSecurity,
    orderTag,
} from "../../schemas/order.shared.schema";

export const createOrderOpenAPISchema = {
    tags: [orderTag],
    summary: "Create order",
    description: "Creates an order in the sales Module",
    security: orderSecurity,
    body: {
        type: "object",
        required: ["externalId", "customerId"],
        properties: {
            externalId: {
                type: "string",
                minLength: 1,
                maxLength: 80,
            },
            customerId: {
                type: "integer",
                minimum: 1,
            },
            priority: {
                type: "number",
                enum: Object.values(OrderPriority),
                default: OrderPriority.NORMAL,
            },
        },
    },
    response: {
        ...commonResponses,
        [HttpStatusCode.CREATED]: {
            description: "Order created",
            content: {
                "application/json": {
                    schema: orderResponseSchema,
                },
            },
        },
        [HttpStatusCode.CONFLICT]: {
            description: "External ID already exists",
        },
    },
} as const;
```

If the project derives OpenAPI from Zod through a configured type provider, preserve that single-source pattern instead of duplicating schemas. Otherwise update Zod and OpenAPI together in the same change.

## Validation helper

Use one shared helper to convert Zod failures into the project's typed validation error:

```typescript
export function zodValidationSchema<TSchema extends z.ZodType>(
    schema: TSchema,
    data: unknown
): z.output<TSchema> {
    const result = schema.safeParse(data);

    if (!result.success) {
        throw ValidationError.fromZod(result.error);
    }

    return result.data;
}
```

Do not call `.parse()` independently in every controller if the project has standardized error formatting.

## Completion checklist

- Body, params, query, and owned headers each have the correct schema.
- Defaults and coercion match the public contract.
- Zod and OpenAPI agree on required, optional, nullable, enum, and range behavior.
- Shared response schemas match presenters.
- Success and typed error responses are documented.
- Security requirements and tags are present.
- E2E tests cover defaults, invalid values, missing required values, and safe error shape.
