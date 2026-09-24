# SQL Server Statistics Governance Engine

Integrated v1.3.2 source and qualification record for statistics maintenance in SQL Server. A utility database houses the engine while target databases remain separate. This project uses `DBAdmin` as its default and qualification database, but an end user can choose another existing user database. The engine records observations, recommends per-statistic commands, and executes approved maintenance only in `ENFORCE` mode.

## Install

Run `src/installer/Install_v1.3.2.sql` in SQLCMD mode with Windows Authentication:

```powershell
sqlcmd -S localhost -E -C -I -d DBAdmin -b -i D:\Projects\StatsGovernance\src\installer\Install_v1.3.2.sql
```

`-C` trusts the local server certificate, `-I` enables quoted identifiers, and `-b` returns a failing exit code when SQL Server reports an error. The installer is rerunnable.

The selected utility database must already exist at compatibility level 110 or higher. An Ola-compatible `dbo.CommandLog` must also exist in that database. The installer validates that table and never changes it. It creates the governance objects described below and makes no instance-level changes or changes in target databases.

### Use a different utility database

The packaged v1.3.2 installer contains three `USE [DBAdmin];` directives. To deploy into another utility database, make a deployment copy of the installer, replace all three directives with the bracketed name of the chosen database, and run `sqlcmd` with that database in `-d`. Changing `-d` alone is insufficient because the `USE` directives take precedence.

For example, for a utility database named `DBAUtility`, change each directive to:

```sql
USE [DBAUtility];
```

Then run:

```powershell
sqlcmd -S localhost -E -C -I -d DBAUtility -b -i C:\Deployment\Install_v1.3.2_DBAUtility.sql
```

The installed procedures, functions, views, trigger, and governance tables use local two-part names, so they operate from the database where they are installed. Put the compatible `dbo.CommandLog` in that same database. Some v1.3.2 validation messages still use the name `DBAdmin`; for a custom installation, they refer to the chosen utility database. The repository's qualification scripts and the examples below use `DBAdmin`; substitute the chosen database in three-part names.

## What is installed in the utility database

The selected utility database centralizes policy, approvals, telemetry, and execution evidence. The installed permanent table schema remains version 1.3.0; the installed module code is version 1.3.2.

### Tables

| Object | Purpose |
| --- | --- |
| `dbo.StatsGovernanceSettings` | The singleton policy row. Installed defaults include a 10 percent change threshold, 500 minimum modifications, a 60 minute cooldown, and a 5 second lock timeout. |
| `dbo.StatsGovernanceScope` | Persistent database exclusions and enforcement approvals, including who made the decision, when, and why. |
| `dbo.StatsGovernanceScopeAudit` | The before-and-after history produced for every scope insert, update, or delete. |
| `dbo.StatsGovernanceOverrides` | Approved table-level or statistic-level exceptions for exclusion, full scan, sample percent, sample rows, or automatic refresh. Overrides can expire. |
| `dbo.StatsGovernanceRuns` | One row per run with its mode, caller, server, parameters, timing, status, and errors. |
| `dbo.StatsGovernanceRunDatabases` | One row per database considered by a run, including selection, captured environment, scope rechecks, candidate count, and errors. |
| `dbo.StatsGovernanceTelemetry` | One row per statistic with snapshots, policy decisions, proposed and executed commands, `CommandLog` correlation, post-checks, and errors. |

The installer also creates the keys, indexes, defaults, and check constraints that enforce this table contract.

### Modules

| Type | Installed objects |
| --- | --- |
| Public run procedures | `dbo.usp_DRE_StatsGovernance_v1` for database-wide work and `dbo.usp_DRE_StatsGovernanceTargeted_v1` for selected tables or statistics categories. |
| Scope and inspection procedures | `dbo.usp_DRE_SetStatsDatabaseScope_v1`, `dbo.usp_DRE_StatsDatabaseSelection_v1`, `dbo.usp_DRE_StatsCapabilities_v1`, and `dbo.usp_DRE_StatsScopeLookup_v1`. |
| Engine procedures | `dbo.usp_DRE_StatsGovernanceWorker_v1`, `dbo.usp_DRE_StatsCollect_v1`, `dbo.usp_DRE_StatsCheckDatabaseGate_v1`, and `dbo.usp_DRE_StatsOverride_v1`. |
| Functions | `dbo.ufn_DRE_StatsCapabilities_v1`, `dbo.ufn_DRE_StatsDecision_v1`, and `dbo.ufn_DRE_StatsCommand_v1` detect capabilities, apply policy, and build the exact quoted command. |
| Reporting views | `dbo.v_DRE_StatsGovernanceResults_v1`, `dbo.v_DRE_StatsDatabaseSelection_v1`, `dbo.v_DRE_StatsDatabaseContext_v1`, `dbo.v_DRE_StatsScopeConfiguration_v1`, and `dbo.v_DRE_StatsColumnstoreHealth_v1`. |
| Audit trigger | `dbo.tr_DRE_StatsScopeAudit_v1` records scope changes and prevents a scope key from being renamed in place. |

`dbo.CommandLog` is a prerequisite rather than a project-owned object. Only `ENFORCE` writes to it, using one row per attempted statistic. The engine retains the inserted `CommandLog.ID` so completion and error details update the exact row.

## Examples

Run these examples in the selected utility database as a `sysadmin`, outside an explicit transaction and with `IMPLICIT_TRANSACTIONS OFF`. The examples use `DBAdmin`; replace that qualifier when using another utility database.

### 1. Recommend index statistics for one table

```sql
EXEC DBAdmin.dbo.usp_DRE_StatsGovernanceTargeted_v1
    @Databases = N'AdventureWorks2019',
    @Tables = N'Sales.SalesOrderHeader',
    @StatisticsScope = 'INDEX_ONLY',
    @Mode = 'RECOMMEND';
```

This applies policy to statistics associated with indexes on `Sales.SalesOrderHeader`. Eligible rows receive an exact proposed command in telemetry, but no maintenance is executed. When `@Tables` is supplied, `@Databases` must resolve to exactly one database.

### 2. Check detected platform capabilities

```sql
EXEC DBAdmin.dbo.usp_DRE_StatsCapabilities_v1;
```

Use this after installation or after moving the utility database to another instance. It reports the server version, engine edition, and feature boundaries that affect statistics `MAXDOP`, persisted sample percentage, metadata availability, and Azure SQL Managed Instance behavior.

### 3. Preview the databases selected by `ALL`

```sql
EXEC DBAdmin.dbo.usp_DRE_StatsDatabaseSelection_v1
    @Databases = N'ALL';
```

This read-only preview shows database accessibility, persistent exclusions, enforcement approval, and whether collection can proceed. `ALL` includes online, accessible, non-snapshot user databases and omits system databases and the utility database where the procedure runs.

### 4. Observe a database without proposing maintenance

```sql
EXEC DBAdmin.dbo.usp_DRE_StatsGovernance_v1
    @Databases = N'AdventureWorks2019',
    @Mode = 'OBSERVE',
    @MAXDOP = 4,
    @MaxExecutionTimeMinutes = 30;
```

`OBSERVE` records statistics metadata, thresholds, and environment context without creating recommendations, executing `UPDATE STATISTICS`, or writing an execution row to `CommandLog`. To inspect several databases in one run, pass a comma-separated list of existing database names.

### 5. Recommend auto-created statistics for selected tables

```sql
EXEC DBAdmin.dbo.usp_DRE_StatsGovernanceTargeted_v1
    @Databases = N'AdventureWorks2019',
    @Tables = N'Sales.SalesOrderHeader,Production.Product',
    @StatisticsScope = 'AUTO_ONLY',
    @Mode = 'RECOMMEND',
    @MinRowCountFloor = 0;
```

This limits evaluation to standalone auto-created statistics on two tables. The zero row-count floor is useful in a small lab database; keep the production default of 1,000,000 rows unless broader scope is intentional. Valid scopes are `ALL`, `INDEX_ONLY`, `AUTO_ONLY`, `USER_ONLY`, and `NON_AUTO`.

### 6. Approve one database for enforcement

```sql
EXEC DBAdmin.dbo.usp_DRE_SetStatsDatabaseScope_v1
    @DatabaseName = N'AdventureWorks2019',
    @IsExcluded = 0,
    @EnabledForEnforcement = 1,
    @Notes = N'Approved for controlled statistics maintenance testing';
```

Approval is explicit and persistent. The procedure records the original login and UTC approval time, requires a nonempty reason, and causes the audit trigger to capture the old and new scope. Setting `@EnabledForEnforcement = 0` removes the approval.

### 7. Enforce a narrow, approved maintenance run

```sql
EXEC DBAdmin.dbo.usp_DRE_StatsGovernanceTargeted_v1
    @Databases = N'AdventureWorks2019',
    @Tables = N'Sales.SalesOrderHeader',
    @StatisticsScope = 'INDEX_ONLY',
    @Mode = 'ENFORCE',
    @MAXDOP = 4,
    @MaxExecutionTimeMinutes = 15;
```

Run `RECOMMEND` first and review its output. In `ENFORCE`, the engine rechecks database identity, scope, object existence, current metadata, active overrides, eligibility, and platform capability before each action. It correlates every attempted command with its own `CommandLog` row and then performs a metadata post-check.

### 8. Exclude a database from collection and enforcement

```sql
EXEC DBAdmin.dbo.usp_DRE_SetStatsDatabaseScope_v1
    @DatabaseName = N'AdventureWorks2019',
    @IsExcluded = 1,
    @Notes = N'Paused during application release window';
```

An exclusion prevents collection and clears enforcement approval. The scope and audit tables retain the reason, login, and UTC time. To return the database to selection, call the procedure with `@IsExcluded = 0` and a new reason; enforcement stays disabled until separately approved.

### 9. Review the latest run

```sql
DECLARE @RunID uniqueidentifier;

SELECT TOP (1) @RunID = RunID
FROM DBAdmin.dbo.StatsGovernanceRuns
ORDER BY StartedAtUTC DESC;

SELECT RunID, Mode, DatabaseName, SchemaName, TableName, StatName,
       InitiallyEligible, InitialReason, ProposedMethod,
       RecommendedCommand, ExecutedCommand, ExecutionStatus,
       CommandLogID, PostcheckStatus, ErrorNumber, ErrorMessage
FROM DBAdmin.dbo.v_DRE_StatsGovernanceResults_v1
WHERE RunID = @RunID
ORDER BY DatabaseName, SchemaName, TableName, StatName;
```

The results view flattens the useful fields from stored snapshots and decisions. Filtering by `RunID` prevents concurrent or historical runs from being mixed. Query `dbo.v_DRE_StatsDatabaseContext_v1` with the same `RunID` for captured version, compatibility, CE, and capability evidence.

Start with `OBSERVE` or `RECOMMEND`. `ENFORCE` requires an enabled database scope approval and writes one CommandLog row per attempted statistic. The public main and targeted interfaces retain their ten and eight parameters, respectively. Default `@MAXDOP` is 4. See `docs/DESIGN_DECISIONS.md` for policy, `docs/PLATFORM_COMPATIBILITY.md` for the Microsoft-documentation review, `docs/QUALIFICATION_20260923.md` for tested behavior, and `docs/MANUAL_PLATFORM_VALIDATION.md` for testing on other instances.

## Qualification boundary

The integrated installer, report modes, policy gates, compatibility levels 110–170, CE 70, and controlled `ENFORCE` were exercised on local SQL Server 2025 CU8. Runtime testing on SQL Server 2016–2022 and Azure SQL Managed Instance still requires those target instances. Capability simulations cover their documented feature boundaries but do not replace runtime qualification.
