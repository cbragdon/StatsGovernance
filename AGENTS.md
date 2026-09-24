# Statistics Governance Project - Codex Instructions

## Scope

This repository contains the SQL Server Statistics Governance Engine project.

Primary development/test instance:

- SQL Server instance: `DESKTOP-6BVBI90`
- Default administrative database: `DBAdmin`; installation must also work in any caller-selected utility database.
- Test database: `AdventureWorks2019`
- Authentication: Windows Authentication
- Do not store credentials in this repository.

## Current operating rule

Treat the live SQL Server instance as authoritative.

Do not assume that a table, view, procedure, trigger, function, or column exists merely because it appears in an older source file. Read the installed metadata before modifying code.

The integrated v1.3.2 installation and dedicated-lab `ENFORCE` qualification completed on 2026-09-23. Read `docs/CURRENT_STATE.md` and `docs/QUALIFICATION_20260923.md` before further work. Any new `ENFORCE` qualification should use dedicated lab objects and inspect the live state first. The user has authorized database testing and modification for this project.

## Project objective

Develop, qualify, and document an enterprise SQL Server Statistics Governance Engine for supported SQL Server versions and Azure SQL Server platforms where the implemented features are valid.

The engine separates:

1. eligibility - whether a statistic needs maintenance,
2. collection method - how the statistic should be updated,
3. persistence - whether a sampling percentage should be persisted.

The integrated v1.3.2 build is installed on the local SQL Server 2025 instance. Runtime qualification on earlier engines and Azure SQL Managed Instance remains pending access to those instances.

## Hard requirements

1. Create the standard Ola-compatible `dbo.CommandLog` when absent; validate and never alter an existing table.
2. Only `ENFORCE` may write the utility database's `dbo.CommandLog`.
3. `OBSERVE` and `RECOMMEND` must not perform statistics maintenance.
4. Do not run `ENFORCE` against business tables without explicit user approval.
5. Controlled `ENFORCE` testing must use dedicated lab objects.
6. Default `@MAXDOP` is 4.
7. Low sample percentage alone does not justify `FULLSCAN`.
8. Identity/datetime leading columns alone do not justify `FULLSCAN`.
9. Legacy CE alone does not justify `FULLSCAN`.
10. Histogram skew alone does not justify `FULLSCAN`.
11. Columnstore delta-store state alone does not justify `FULLSCAN`.
12. `FULLSCAN` requires an explicitly approved path such as `FORCE_FULLSCAN`.
13. A one-time `FULLSCAN` must not automatically persist a 100 percent sample rate.
14. `SAMPLE n ROWS` is approximate because SQL Server samples data pages.
15. Missing telemetry is unknown, not zero and not false.
16. Maintenance-window expiration is a soft stop; an in-flight command may complete.
17. Do not alter SQL Server instance-level settings as part of this project.
18. Do not use `xp_cmdshell`.
19. Do not silently remove required `MAXDOP`, persistence, or version-specific behavior because a feature is unsupported. Return an explicit blocked-capability status instead.
20. Do not automatically delete statistics based on usage telemetry.
21. Preserve the existing public procedure contracts.
22. Treat collation as part of the object contract.
23. Declare nullability explicitly in permanent tables, temp tables, and table variables.
24. Serialize `rowversion`/`binary` values to textual/XML form with `sys.fn_varbintohexstr()` unless a different binary-safe representation is explicitly required.
25. Never claim a runtime test passed unless Codex actually executed it against the target SQL Server and checked the result.
26. Installer and utility SQL scripts must use the caller-selected connection database; do not hardcode `USE [DBAdmin]`.
27. Supported system database targets are `master`, `model`, and `msdb`.
28. Never select or approve `tempdb`, `SSISDB`, or a replication distribution database.
29. Never process a database on a local Always On secondary replica; check at selection and revalidate before work.

## Public procedure contracts

`dbo.usp_DRE_StatsGovernance_v1` in the selected utility database must retain exactly these ten public parameters:

```sql
@Databases
@Mode = 'RECOMMEND'
@MAXDOP = 4
@MinRowCountFloor = 1000000
@LowSampleThresholdBase = 2.0
@LargeTableThresholdBase = 20000000
@DefaultSamplePercentBase = NULL
@MaxExecutionTimeMinutes = 300
@IOThroughputTier = 'STANDARD'
@LegacyCEMultiplier = 2.0
```

`dbo.usp_DRE_StatsGovernanceTargeted_v1` in the selected utility database must retain exactly these eight public parameters:

```sql
@Databases nvarchar(max)
@Tables nvarchar(max) = NULL
@StatisticsScope varchar(20) = 'ALL'
@Mode varchar(10) = 'RECOMMEND'
@MAXDOP int = 4
@MinRowCountFloor bigint = 1000000
@MaxExecutionTimeMinutes int = 300
@IOThroughputTier varchar(8) = 'STANDARD'
```

## Statistics scopes

Supported targeted scopes:

- `ALL`
- `INDEX_ONLY`
- `AUTO_ONLY`
- `USER_ONLY`
- `NON_AUTO`

`@Tables` uses comma-separated, schema-qualified `schema.table` names.

When `@Tables` is supplied:

- exactly one resolved database is allowed,
- `ALL` databases with a table list is rejected,
- every supplied table must resolve,
- statistics are updated one-by-one by name; do not replace this with table-wide `UPDATE STATISTICS schema.table` behavior.

## CommandLog contract

Use the Ola Hallengren-compatible `dbo.CommandLog` table in the selected utility database. The installer creates it when absent and preserves it when present.

Columns used by this project:

```text
ID
DatabaseName
SchemaName
ObjectName
ObjectType
IndexName
IndexType
StatisticsName
PartitionNumber
ExtendedInfo
Command
CommandType
StartTime
EndTime
ErrorNumber
ErrorMessage
```

Required mapping:

Index-associated statistic:
- `ObjectType = 'U'`
- `IndexName` populated
- numeric `IndexType` populated
- `StatisticsName` populated

Standalone statistic:
- `ObjectType = 'U'`
- `IndexName = NULL`
- `IndexType = NULL`
- `StatisticsName` populated

`Command` must never be NULL for execution rows.

Only `ENFORCE` writes CommandLog.

## Sampling and skew policy

Methods:

- `AUTO`
- `SAMPLE_PERCENT`
- `SAMPLE_ROWS`
- `FULLSCAN`

Skew classifications:

- `LOW`
- `MODERATE`
- `HIGH`
- `EXTREME`
- `UNKNOWN`

Default skew thresholds:

- LOW: less than 5 percent
- MODERATE: at least 5 and less than 10 percent
- HIGH: at least 10 and less than 25 percent
- EXTREME: at least 25 percent

`HIGH` or `EXTREME` skew does not automatically imply `FULLSCAN`.

`FORCE_SAMPLE_ROWS` rules:
- `SampleRows` and `SamplePercent` are mutually exclusive.
- Automatic `SAMPLE_ROWS` does not add persistence.
- If an existing persisted sample rate is present and persistence mode is KEEP, do not silently replace it.
- Persistence mode ON is not valid for row-count sampling because `PERSIST_SAMPLE_PERCENT` persists a percentage, not a row count.

## Native auto-update threshold telemetry

Native auto-update threshold selection depends on SQL Server version, database compatibility level, and TF 2371 behavior. CE mode is contextual information and must not be used as the formula selector.

Report at least:

```text
CurrentTableRows
StatsRowsAtLastUpdate
UnfilteredRowsAtLastUpdate
RowCountDeltaSinceStatsUpdate
ModificationCounter
EstimatedAutoUpdateThresholdModifications
EstimatedModificationsRemainingToAutoUpdate
AutoUpdateThresholdProgressPercent
AutoUpdateThresholdReached
AutoUpdateThresholdPolicy
ThresholdProductMajorVersion
ThresholdCompatibilityLevel
ThresholdCEContext
GovernanceThresholdBasisRows
GovernanceEffectiveModificationThreshold
GovernanceModificationsRemaining
GovernanceThresholdProgressPercent
GovernanceThresholdReached
GovernanceVsNativeThresholdDeltaModifications
GovernanceVsNativeThresholdComparison
```

For filtered statistics, use `unfiltered_rows` as the native threshold basis when available; report current table rows separately.

Do not cap progress percentages at 100 percent.

Current comparison values in the implemented v1.3.1 decision code are:

- `GOVERNANCE_EARLIER`
- `GOVERNANCE_LATER`
- `SAME_THRESHOLD`

## Index-family policy

Recognized families:

- ROWSTORE
- COLUMNSTORE
- XML
- SPATIAL
- HASH
- JSON
- STANDALONE
- UNKNOWN

Non-rowstore index-associated statistics are visible but deferred unless a later release explicitly adds supported execution logic.

## Version capability policy

Do not infer capability from major version alone when a CU/SP build gate applies.

Known capability gates already used by this project include:

- SQL Server 2016 `CREATE OR ALTER`: SP1+
- SQL Server 2016 statistics `MAXDOP`: SP2+
- SQL Server 2016 `PERSIST_SAMPLE_PERCENT`: SP1 CU4+
- SQL Server 2016 persisted-sample rebuild retention: SP2 CU17 build 13.0.5888.11+ or SP3+
- SQL Server 2016 `sys.dm_db_stats_histogram`: SP1 CU2 build 13.0.4422.0+
- SQL Server 2017 statistics `MAXDOP`: CU3 build 14.0.3015.40+
- SQL Server 2017 `PERSIST_SAMPLE_PERCENT`: CU1 build 14.0.3006.16+
- SQL Server 2017 persisted-sample rebuild retention: CU26 build 14.0.3411.3+
- SQL Server 2019 persisted-sample rebuild retention: CU10 build 15.0.4123.1+

Validate these against Microsoft documentation before changing capability logic.

## Current release-state rule

Do not create another incremental r5-style patch.

The next integrated release should be v1.3.2 and must fold all validated fixes into one canonical source tree.

Read `docs/CURRENT_STATE.md`, `docs/KNOWN_DEFECTS.md`, `docs/DESIGN_DECISIONS.md`, and `docs/TEST_PLAN.md` before taking action.

## First task

Follow `docs/CODEX_FIRST_TASK.md`.

Before any SQL Server DDL/DML:

1. identify available local SQL clients,
2. connect with Windows Authentication,
3. inventory the live installed contract,
4. inspect the incomplete Phase 7 state,
5. produce/update `docs/LIVE_SCHEMA_CONTRACT.md`,
6. produce `docs/DISCREPANCY_REPORT.md`,
7. stop for user review.

Do not rerun `ENFORCE` during the inventory phase.
