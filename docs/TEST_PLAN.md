# Test Plan

Execution status for the 2026-09-23 local v1.3.2 qualification is recorded in `QUALIFICATION_20260923.md`. This file remains the broader cross-version plan. The available `localhost` instance is SQL Server 2025; run the contract, policy, and controlled execution layers on each actual earlier-version or Managed Instance target before claiming cross-version runtime qualification.

The test strategy is separated into three layers.

## Layer 1 - Contract tests

Purpose:

Verify that installed objects match the exact shape expected by the code before behavior is tested.

Contract checks must include:

- SQL Server product version/build/edition,
- database compatibility,
- database collations,
- engine/table schema versions,
- permanent table columns,
- data types,
- lengths/precision/scale,
- nullability,
- column collations,
- defaults,
- check constraints,
- keys,
- indexes,
- triggers,
- procedure/function/view existence,
- procedure parameter names/order/types/defaults,
- required result-view columns,
- CommandLog shape,
- object definitions/hashes where useful.

`tests/contract/00_CommandLog.sql` validates the 16 required columns, types, lengths, nullability, identity property, and clustered primary key. `tests/execution/07_CommandLog_Bootstrap.sql` creates a compatibility-level-110 disposable utility database without `dbo.CommandLog`, installs twice, verifies automatic creation and object preservation, runs the remaining contracts, and removes the database.

Contract tests are read-only.

A contract mismatch stops qualification before DDL/DML.

## Layer 2 - Policy tests

Purpose:

Validate deterministic decisions using controlled inputs without executing statistics maintenance.

Minimum policy scenarios:

### Eligibility

- below governance threshold,
- exactly at governance threshold,
- above governance threshold,
- zero stats baseline,
- cooldown active,
- cooldown expired,
- missing telemetry,
- excluded object,
- unsupported capability.

### Native threshold

- table <= 500 rows,
- legacy 500 + 20 percent rule,
- dynamic compatibility 130+ rule,
- global TF2371 dynamic rule where applicable,
- filtered statistic basis,
- NORECOMPUTE,
- AUTO_UPDATE_STATISTICS OFF,
- async context.

### Sampling

- AUTO,
- SAMPLE_PERCENT,
- SAMPLE_ROWS,
- FULLSCAN approved override,
- existing persisted percentage,
- persistence OFF,
- persistence KEEP,
- invalid SAMPLE_ROWS + persistence ON.

### Skew

- LOW,
- MODERATE,
- HIGH,
- EXTREME,
- UNKNOWN.

Verify skew does not independently force FULLSCAN.

### Statistics scope

- ALL,
- INDEX_ONLY,
- AUTO_ONLY,
- USER_ONLY,
- NON_AUTO.

### Database selection

- arbitrary caller-selected utility database,
- SYSTEM_DATABASES resolves master, model, and msdb,
- USER_DATABASES excludes system databases,
- ALL includes supported system and user databases,
- utility database excluded from group selectors,
- tempdb rejected,
- SSISDB rejected when present,
- replication distribution database rejected when present,
- local Always On secondary blocked,
- primary-replica state revalidated before collection and enforcement.

### Index family

- ROWSTORE,
- COLUMNSTORE,
- XML,
- SPATIAL,
- HASH,
- JSON,
- UNKNOWN.

Unsupported/non-rowstore execution paths should be explicitly deferred.

## Layer 3 - Execution tests

Purpose:

Prove SQL Server actually executes the intended maintenance and records it correctly.

Use dedicated lab objects only.

For each executed statistic verify:

- exact RunID,
- exact TelemetryID,
- initial eligibility,
- decision reason,
- proposed method,
- generated command,
- MAXDOP clause when supported,
- persistence clause,
- CommandLog inserted ID,
- CommandLog mapping,
- StartTime/EndTime,
- ErrorNumber/ErrorMessage,
- post-update stats metadata,
- modification counter reset behavior,
- rows sampled,
- persisted sample percentage,
- postcheck status.

## Controlled ENFORCE fixture

Before creating a new fixture, inspect whether the existing Phase 7 lab state still contains useful evidence.

Do not rerun until current-state inspection is complete.

The prior intended fixture used:

```text
AdventureWorks2019.DREStatsLab.StatsEnforceQualification
400,000 rows
50,000 modifications
```

Expected governance threshold at default 10 percent:

```text
40,000 modifications
```

Expected modern dynamic native threshold for 400,000 rows:

```text
20,000 modifications
```

Expected comparison:

```text
GOVERNANCE_LATER
```

Expected governance progress:

```text
125 percent
```

Expected native progress:

```text
250 percent
```

Execution paths:

1. index-associated statistic -> `SAMPLE 25000 ROWS`,
2. standalone user-created statistic -> approved `FULLSCAN`.

Persistence for the controlled one-time test should be OFF.

## CommandLog execution test

Index-associated statistic:

```text
ObjectType = U
IndexName populated
IndexType numeric
StatisticsName populated
CommandType = UPDATE_STATISTICS
```

Standalone statistic:

```text
ObjectType = U
IndexName NULL
IndexType NULL
StatisticsName populated
CommandType = UPDATE_STATISTICS
```

Exactly one CommandLog row should correspond to each executed statistic.

## Safety checks

Before every execution test:

- assert target is dedicated lab schema/table,
- assert no explicit user transaction,
- assert required application lock can be acquired,
- assert target database scope/approval,
- assert current engine version and schema contract,
- assert no conflicting lab overrides,
- assert cleanup plan.

After every test:

- restore temporary configuration,
- remove temporary overrides,
- retain telemetry/CommandLog until validation passes,
- clean up only dedicated lab objects after evidence is reviewed.

## Cross-version qualification

After SQL Server 2025 development qualification is stable, run capability-focused qualification on required versions/builds:

```text
SQL Server 2016
SQL Server 2017
SQL Server 2019
SQL Server 2022
SQL Server 2025
```

Do not assume a capability is present on all CUs/SPs of a major version.
