# Platform compatibility review — 2026-09-23

This review maps the v1.3.2 implementation to Microsoft-documented behavior. It is a design and source audit; runtime evidence is recorded separately in `QUALIFICATION_20260923.md`. The user will test closed-off SQL Server and Managed Instance environments manually.

## Engine and compatibility-level matrix

| Platform | Supported requested compatibility levels | Behavior used by the engine |
| --- | --- | --- |
| SQL Server 2016 | 110–130 | Legacy fixed auto-update threshold below 130; dynamic threshold at 130. |
| SQL Server 2017 | 110–140 | Same threshold boundary; sampling scan is serial regardless of compatibility level. |
| SQL Server 2019 | 110–150 | Same threshold boundary and serial sampling scan. |
| SQL Server 2022 | 110–160 | Same threshold boundary; CE feedback context is advisory and requires compatibility 160 and active Query Store. |
| SQL Server 2025 | 110–170 | Same threshold boundary; JSON index family is classified but deferred from rowstore maintenance. |
| Azure SQL Managed Instance | 110–170 when supported by the instance update policy | Edition 8 is recognized without treating the reported `12.x` product version as SQL Server 2014. The database's actual compatibility level determines threshold and CE context; CE feedback availability is probed rather than assumed. |

The [compatibility-level table](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-database-transact-sql-compatibility-level?view=sql-server-ver17) gives each engine's maximum level and the Managed Instance update-policy differences. CE 70 is identified when compatibility is below 120, `LEGACY_CARDINALITY_ESTIMATION` is enabled, or trace flag 9481 is visible. CE context is advisory and never independently authorizes `FULLSCAN`. The [compatibility-level documentation](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-database-transact-sql-compatibility-level?view=sql-server-ver17) describes the legacy CE switch.

## Build-gated statistics features

| Feature | First documented SQL Server build used by the gate | Source behavior below the gate |
| --- | --- | --- |
| Histogram DMF | 2016 SP1 CU2 (`13.0.4422.0`) | Histogram and skew evidence is unavailable, not zero. |
| `PERSIST_SAMPLE_PERCENT` | 2016 SP1 CU4 (`13.0.4446.0`); 2017 CU1 (`14.0.3006.16`) | A request requiring persistence is explicitly blocked. |
| `UPDATE STATISTICS ... MAXDOP` | 2016 SP2 (`13.0.5026.0`); 2017 CU3 (`14.0.3015.40`) | Enforcement is explicitly blocked because the required MAXDOP clause cannot be honored. |
| Persisted sample survives index rebuild | 2016 SP2 CU17 (`13.0.5888.11`); 2017 CU26 (`14.0.3411.3`); 2019 CU10 (`15.0.4123.1`) | Results warn that a rebuild can clear persisted sampling. |

Sources: [UPDATE STATISTICS](https://learn.microsoft.com/en-us/sql/t-sql/statements/update-statistics-transact-sql?view=sql-server-ver17), [histogram DMF](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-db-stats-histogram-transact-sql?view=sql-server-ver17), [statistics-properties DMF](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-objects/sys-dm-db-stats-properties-transact-sql?view=sql-server-ver17), [2016 build list](https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-2016/build-versions), and [2017 build list](https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-2017/build-versions).

`sys.dm_db_stats_properties.persisted_sample_percent` is referenced only in dynamic SQL after a metadata probe confirms that column exists. Histogram calls are likewise inserted into dynamic SQL only when the build gate allows them. The installer uses `CREATE` stubs followed by `ALTER`, avoiding a dependency on `CREATE OR ALTER` in SQL Server 2016 RTM. Comma-list parsing does not use `STRING_SPLIT`, which is unavailable at compatibility 110–120.

## Thresholds, sampling, and Managed Instance

The native auto-update threshold estimate uses `500 + 0.20 * n` for more than 500 rows below compatibility 130, and `MIN(500 + 0.20 * n, SQRT(1000 * n))` at 130 or above. Global trace flag 2371 enables the dynamic threshold on older compatibility levels where supported. CE 70 does not select the threshold formula. These behaviors follow Microsoft's [statistics guidance](https://learn.microsoft.com/en-us/sql/relational-databases/statistics/statistics?view=sql-server-ver17) and [trace flag documentation](https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-traceon-trace-flags-transact-sql?view=sql-server-ver17).

For Managed Instance, `SERVERPROPERTY('EngineEdition') = 8` identifies the platform even when its reported version begins with `12`. [Microsoft's Managed Instance overview](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/sql-managed-instance-paas-overview?view=azuresql) warns that this reported version is not the underlying SQL Server feature level. `DBCC TRACESTATUS` is [documented for Managed Instance](https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-tracestatus-transact-sql?view=sql-server-ver17); the engine only reads trace state and never changes flags. Global trace flag support on Managed Instance is limited, so compatibility level and database-scoped CE configuration remain the principal context signals.

The [CE_FEEDBACK scoped-configuration documentation](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-database-scoped-configuration-transact-sql?view=sql-server-ver17) applies it to Managed Instance with SQL Server 2025 or always-current update policy. `SERVERPROPERTY('ProductUpdateType') = 'CU'` does not distinguish SQL Server 2022 from 2025 policy. The capability function therefore reports Managed Instance CE feedback support as unknown; the collector checks whether `CE_FEEDBACK` appears in the target database's scoped configuration and reports unavailable when it does not. No maintenance decision depends on this advisory field.

The selector uses [`sys.fn_hadr_is_primary_replica`](https://learn.microsoft.com/en-us/sql/relational-databases/system-functions/sys-fn-hadr-is-primary-replica-transact-sql?view=sql-server-ver17) to reject local Always On secondary replicas and repeats the check immediately before collection or enforcement. The function returns `NULL` for databases that are not in an availability group; the engine treats that as an ordinary local database. The collector also uses `DATABASEPROPERTYEX(DB_NAME(), 'Updateability')` as its writeability gate. Microsoft documents `READ_ONLY` for both [SQL Server availability-group secondaries](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/configure-read-only-access-on-an-availability-replica-sql-server?view=sql-server-ver17) and [Managed Instance read-only replicas](https://learn.microsoft.com/en-us/azure/azure-sql/database/troubleshoot-common-errors-issues?view=azuresql).

`SAMPLE n ROWS` remains approximate because SQL Server samples pages; `FULLSCAN` requires an approved override. The [UPDATE STATISTICS documentation](https://learn.microsoft.com/en-us/sql/t-sql/statements/update-statistics-transact-sql?view=sql-server-ver17) also states that SQL Server 2016 at compatibility 130 can use a parallel sampling scan, while SQL Server 2017 and later reverted to a serial sampling scan. The engine reports this distinction without choosing `FULLSCAN` from it.

## System and excluded databases

`SYSTEM_DATABASES` covers `master`, `model`, and `msdb`. The collector includes Microsoft-shipped tables in those three databases because Microsoft documents that [`sp_updatestats`](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-updatestats-transact-sql?view=sql-server-ver17) updates user-defined and internal tables. The engine keeps its own per-statistic policy and command generation rather than calling `sp_updatestats`.

`tempdb` is excluded because Microsoft maintenance-plan guidance targets every system database [except `tempdb`](https://learn.microsoft.com/en-us/sql/relational-databases/maintenance-plans/update-statistics-task-maintenance-plan?view=sql-server-ver17), and this engine creates temporary work tables during a run. `SSISDB` is excluded by its fixed catalog name, and replication distribution databases are identified with the documented [`sys.databases.is_distributor`](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-databases-transact-sql?view=sql-server-ver17) flag.

## Manual validation boundary

The expanded capability matrix tests the documented build boundaries, including Managed Instance reporting `12.0.2000.8`. Runtime installation and execution on the user's closed-off versions remain for the user's manual testing. A failed feature probe or missing telemetry is surfaced as unavailable or blocked; it is not treated as evidence of a zero value.
