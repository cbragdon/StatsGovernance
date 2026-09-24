# Manual validation on SQL Server 2016–2022 and Azure SQL Managed Instance

Run this on each closed-off target. Keep its SQLCMD output and the product/build string with the test result. The source has already been audited against Microsoft documentation in `PLATFORM_COMPATIBILITY.md`; this procedure verifies the target's actual behavior.

## 1. Record the target

Connect with an administrative identity and run:

```sql
SELECT @@SERVERNAME AS ServerName,
       CONVERT(nvarchar(128),SERVERPROPERTY('ProductVersion')) AS ProductVersion,
       CONVERT(int,SERVERPROPERTY('EngineEdition')) AS EngineEdition,
       CONVERT(nvarchar(128),SERVERPROPERTY('ProductUpdateType')) AS ProductUpdateType;
SELECT name,compatibility_level,collation_name,state_desc,is_read_only,is_distributor,
       sys.fn_hadr_is_primary_replica(name) AS IsLocalPrimaryReplica
FROM sys.databases;
```

Managed Instance reports `EngineEdition = 8`. Its reported `ProductVersion` may begin with `12` and does not define the SQL Server feature level. Record the Azure update policy from the portal as well: `ProductUpdateType = CU` does not distinguish the 2022 and 2025 policies.

## 2. Install and check contracts

Prerequisites: the selected utility database exists and its compatibility level is at least 110. The installer creates an Ola-compatible `dbo.CommandLog` when absent. It validates and preserves an existing table. The installer contains no `USE` statement and installs into the connection database selected with `-d`. Example for Windows Authentication:

```powershell
powershell.exe -ExecutionPolicy Bypass -File D:\Projects\StatsGovernance\scripts\00_Install.ps1 -Server <server> -Database <utility_database>
```

For a self-signed certificate, add `-TrustServerCertificate`; use the connection and authentication method required by the target environment. A successful install prints `TABLE_CONTRACT_PASS` and `STATS_GOVERNANCE_V1_3_2_INSTALL_COMPLETE`. Then run `tests/contract/00_CommandLog.sql`, `01_Tables.sql`, `02_Modules.sql`, and `03_Database_Selection.sql` with `sqlcmd -d <utility_database>`; all must exit zero and print their `*_PASS` markers. Re-run the installer once to check idempotence. Where database creation and deletion are allowed, run `tests/execution/07_CommandLog_Bootstrap.sql` in SQLCMD mode to qualify automatic creation in a disposable utility database.

## 3. Run read-only and policy checks

Run `tests/policy/02_Decision_Matrix.sql` and `tests/policy/03_Capability_Matrix.sql`. They do not perform statistics maintenance. Run `tests/policy/01_Report_Only_Smoke.sql` only if `AdventureWorks2019` is present and contains `Sales.SalesOrderHeader`; it verifies that `OBSERVE` and `RECOMMEND` leave CommandLog unchanged.

Check the target's actual capability report:

```sql
EXEC <utility_database>.dbo.usp_DRE_StatsCapabilities_v1;
```

On SQL Server 2016 before SP2, or SQL Server 2017 before CU3, `SupportsStatisticsMAXDOP = 0` is expected. The engine reports a blocked capability for enforcement because its required `MAXDOP` clause is unavailable; do not treat that as a failed installation. The build boundaries and source links are in `PLATFORM_COMPATIBILITY.md`.

Run `tests/policy/04_System_Database_Smoke.sql` to verify report-only collection for `master`, `model`, and `msdb`. Confirm that `tempdb`, `SSISDB`, replication distribution databases, and local Always On secondary replicas do not appear in the run. On an Always On target, also name a local secondary explicitly in `usp_DRE_StatsDatabaseSelection_v1` and confirm `IsLocalPrimary = 0`, `SelectionStatus = BLOCKED_SECONDARY`, and `WillCollect = 0`.

## 4. Controlled execution

Use only a dedicated test database/table. The included `tests/execution/01_Setup_Lab.sql` through `04_Cleanup_Lab.sql` are scoped to `AdventureWorks2019`; review the names before running on a target. Setup requires that the `DREStatsLab` schema and the temporary approval/override rows do not already exist. The scripts temporarily approve that database for one lab object, lower the cooldown for a fresh fixture, execute two named statistics, and restore the setting and approval. Run them in numeric order, stop on any nonzero SQLCMD exit, inspect state, then perform cleanup. Never point this fixture at business tables.

When `MAXDOP` is supported, success requires `LAB_RECOMMEND_PASS`, `LAB_ENFORCE_PASS`, and `LAB_CLEANUP_PASS`, plus two successful CommandLog records linked to the execution RunID. `SAMPLE n ROWS` is approximate; verify the command rather than expecting exactly `n` sampled rows.

## 5. Report back

For each target, provide: product version/build, engine edition, compatibility level, Managed Instance update policy if applicable, exit code and `*_PASS` marker for each script, and any SQL error number/message. Include the governance RunID for an enforcement test. Leave the original output files intact for diagnosis.
