# Architecture and Design

Read this reference when a task changes Module ownership, Interface shape, Seam placement, persistence strategy, integration contracts, runtime topology, or operational guarantees.

## Start with a decision, not a diagram

Write down:

- the product or operational decision to support;
- users or callers and their critical flows;
- functional behavior and data invariants;
- workload, latency, availability, consistency, and recovery expectations;
- security, privacy, compliance, cost, and team constraints;
- assumptions, especially unverified scale claims.

The frame is complete when success and failure are observable and every hard constraint has a source or is marked as an assumption.

## Map the existing system

Trace the requested behavior through the current code:

```text
caller -> delivery Adapter -> Module Interface -> behavior
       -> persistence/integration Adapter -> observable outcome
```

Identify the Module that owns each invariant, write path, read path, and source of truth. Locate composition roots and runtime wiring. Note cross-Module calls, shared data, public contracts, asynchronous messages, and operational tooling.

Use the repository's domain language. If a DDD project distinguishes a bounded context, aggregate, command, or policy, preserve those terms. Do not rename a domain to fit a generic architecture vocabulary.

## Design deep Modules

A deep Module gives callers high Leverage through a small Interface and concentrates knowledge with high Locality.

For each candidate Interface, specify more than types:

- operations and parameters;
- invariants and ordering constraints;
- result and error modes;
- idempotency and concurrency semantics;
- required configuration and authorization;
- performance or consistency characteristics callers must know.

Apply these tests:

- **Deletion test**: if deleting the Module merely removes complexity, it was shallow; if complexity spreads to callers, it was earning its place.
- **Interface test surface**: callers and tests should exercise the same Seam.
- **Adapter test**: one Adapter is usually hypothetical; two justified Adapters make the Seam real.

Prefer hiding complexity over adding pass-through layers. Internal Seams used by the Implementation or its tests need not become part of the external Interface.

## Classify dependencies before placing Seams

### In-process

Pure computation or in-memory state. Keep it inside the Implementation and test through the Module Interface. An Adapter rarely helps.

### Local-substitutable

A dependency with a faithful local stand-in, such as an embedded database, test container, in-memory filesystem, or deterministic clock. Keep the Seam internal and exercise the Module with the stand-in.

### Remote but owned

An internal system across a network or queue. Put an injected port at the real transport Seam. Keep business behavior in the deep Module; use production transport and local test Adapters.

### True external

A third-party system the team does not control. Inject only the narrow Interface the Module consumes. Define timeouts, retry safety, rate limits, idempotency, error translation, observability, and a production plus test Adapter.

## Choose topology only from constraints

- Prefer the simplest topology satisfying current constraints.
- Keep evolving domains together when independent deployment, scaling, ownership, or fault isolation do not repay distribution cost.
- Split deployment only with evidence for independent lifecycle or failure isolation.
- Use asynchronous communication when it protects a critical path or models a real temporal decoupling.
- Add caches, queues, replicas, search systems, schedulers, or distributed locks for a measured need and an explicit invalidation or recovery model.

Treat shared databases, dual writes, cross-system transactions, and distributed ownership of one invariant as risks requiring an explicit consistency story.

## Design data and contracts

For each write path, define validation, authorization, transaction ownership, concurrency control, idempotency, auditability, and migration compatibility. For each read path, define consistency needs, query shape, pagination, ordering, indexing, and staleness tolerance.

Across a Seam, define:

- canonical contract and versioning strategy;
- omitted versus null semantics;
- error taxonomy and safe translation;
- timeout, retry, replay, duplicate, and out-of-order behavior;
- authentication, authorization, rate limits, and sensitive-data handling;
- backward and forward compatibility during rollout.

Adapters translate protocols and external vocabulary. They should not redefine domain rules.

## Design runtime operations

Match operational depth to risk:

- structured logs with correlation and redaction;
- metrics for traffic, errors, saturation, latency, retries, and backlog;
- traces across meaningful remote Seams;
- health checks that distinguish readiness from liveness;
- SLOs and alerts tied to user-visible failure;
- bounded retries with backoff and jitter where repetition is safe;
- circuit breaking, backpressure, DLQ or replay where failure can accumulate;
- runbooks and rollback paths for changes operators must own.

## Compare and recommend

Compare only viable alternatives by simplicity, consistency, latency, reliability, security, operability, cost, migration risk, and team ownership. Recommend one design. Prefer incremental rollout with observable checkpoints and a reversible next step.

Architecture work is complete when the recommendation identifies:

- Module ownership and Interface;
- Seam and Adapter placement;
- data and consistency model;
- failure, security, and observability behavior;
- migration, rollout, rollback, and proof plan;
- assumptions and decisions still requiring human authority.
