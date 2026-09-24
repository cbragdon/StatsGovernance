# SQL Server Statistics Governance Engine

Integrated v1.3.2 source and qualification record for statistics maintenance in SQL Server. A utility database houses the engine while target databases remain separate. This project uses `DBAdmin` as its default and qualification database, but an end user can choose another existing user database. The engine records observations, recommends per-statistic commands, and executes approved maintenance only in `ENFORCE` mode.

## Install

The automated installer requires the utility database name. For the local instance:

```powershell
powershell.exe -ExecutionPolicy Bypass -File D:\Projects\StatsGovernance\scripts\00_Install.ps1 `
    -Server localhost `
    -Database DBAdmin `
    -TrustServerCertificate
```

The wrapper uses Windows Authentication, passes the selected database to `sqlcmd -d`, enables quoted identifiers, and returns a failure when SQL Server reports an error. `-TrustServerCertificate` adds `-C` for a server certificate that the workstation does not trust. Omit that switch when normal certificate validation should apply.

The selected utility database must already exist at compatibility level 110 or higher. If `dbo.CommandLog` is absent, the installer creates the standard Ola-compatible table in that database. If it already exists, the installer validates its required schema and preserves the table and its rows. It creates the remaining governance objects described below and makes no instance-level changes or changes in target databases.

### Direct SQLCMD installation

The SQL installer contains no `USE` statement. It installs into the connection's current database, so `-d` is the database selection mechanism:

```powershell
sqlcmd -S localhost -E -C -I -d DBAUtility -b -i D:\Projects\StatsGovernance\src\installer\Install_v1.3.2.sql
```

The installed procedures, functions, views, trigger, and governance tables use local two-part names. `dbo.CommandLog` is created in that same utility database when absent. The repository's examples use `DBAdmin`; substitute the chosen database in three-part names. The installer is rerunnable.

## What is installed in the utility database

The selected utility database centralizes policy, approvals, telemetry, and execution evidence. The installed permanent table schema remains version 1.3.0; the installed module code is version 1.3.2.

### Tables

| Object | Purpose |
| --- | --- |
| `dbo.CommandLog` | Standard Ola-compatible execution log. Created only when absent; an existing compatible table and its rows are preserved. |
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

`dbo.CommandLog` follows the standard Ola Hallengren schema. The installer creates it only when absent; an existing compatible table and its history are retained. Only `ENFORCE` writes execution rows, using one row per attempted statistic. The engine retains the inserted `CommandLog.ID` so completion and error details update the exact row.

## Database selection and exclusions

`@Databases` accepts a single database, a comma-separated list, or one of these group selectors:

| Selector | Databases considered |
| --- | --- |
| `SYSTEM_DATABASES` | `master`, `model`, and `msdb`. Microsoft-shipped tables in these databases are included in statistics collection. |
| `USER_DATABASES` | Supported user databases other than the utility database. |
| `ALL` | Both groups above. |

All group selectors omit the utility database, `tempdb`, `SSISDB`, replication distribution databases, snapshots, inaccessible or offline databases, and databases hosted on a local Always On secondary replica. Explicitly naming `tempdb`, `SSISDB`, or a distribution database is rejected. Explicitly naming an Always On secondary reports it as blocked. The engine calls `sys.fn_hadr_is_primary_replica` during selection and again before work so a role change cannot bypass the gate.

System databases require the same explicit scope approval as user databases before `ENFORCE`. `OBSERVE` and `RECOMMEND` remain report-only.

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

This read-only preview shows database accessibility, persistent exclusions, enforcement approval, and whether collection can proceed. `ALL` includes supported user databases plus `master`, `model`, and `msdb`, subject to the exclusions above.

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

### 10. Observe supported system databases

```sql
EXEC DBAdmin.dbo.usp_DRE_StatsGovernance_v1
    @Databases = N'SYSTEM_DATABASES',
    @Mode = 'OBSERVE',
    @MinRowCountFloor = 0,
    @MaxExecutionTimeMinutes = 30;
```

This collects statistics context from `master`, `model`, and `msdb`, including their Microsoft-shipped tables. It does not include `tempdb`, `SSISDB`, a replication distribution database, or any local Always On secondary, and it performs no statistics maintenance in `OBSERVE` mode.

Start with `OBSERVE` or `RECOMMEND`. `ENFORCE` requires an enabled database scope approval and writes one CommandLog row per attempted statistic. The public main and targeted interfaces retain their ten and eight parameters, respectively. Default `@MAXDOP` is 4. See `docs/DESIGN_DECISIONS.md` for policy, `docs/PLATFORM_COMPATIBILITY.md` for the Microsoft-documentation review, `docs/QUALIFICATION_20260923.md` and `docs/QUALIFICATION_20260924.md` for tested behavior, and `docs/MANUAL_PLATFORM_VALIDATION.md` for testing on other instances.

## Qualification boundary

The integrated installer, arbitrary utility database context, report modes, system database collection, policy gates, compatibility levels 110–170, CE 70, and controlled `ENFORCE` were exercised on local SQL Server 2025 CU8. Runtime testing on SQL Server 2016–2022 and Azure SQL Managed Instance still requires those target instances. Capability simulations cover their documented feature boundaries but do not replace runtime qualification.
