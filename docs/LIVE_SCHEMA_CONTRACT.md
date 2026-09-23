# Live Schema Contract

This document is the pre-upgrade v1.3.1 capture. The current installed engine is v1.3.2; see `CURRENT_STATE.md` and `QUALIFICATION_20260923.md`. The permanent table schema remains 1.3.0.

Captured read-only on 2026-09-23 15:34–15:35 UTC from `localhost` using Windows Authentication. Evidence: `artifacts/live_inventory_20260923_153454Z/inventory.txt`, `artifacts/live_inventory_20260923_153454Z/modules.csv`, `artifacts/live_inventory_20260923_153454Z/live_modules/`, and `artifacts/live_schema_columns_20260923.txt`. The inventory completed with `READ_ONLY_LIVE_INVENTORY_COMPLETE` and no SQL error.

## Server and databases

| Item | Live value |
| --- | --- |
| Server | `DESKTOP-6BVBI90` |
| Product version | `17.0.4085.5` |
| Product level / update | RTM / CU8 (`KB5122769`) |
| Edition | Enterprise Developer Edition (64-bit) |
| Engine edition | 3 |
| Server collation | `SQL_Latin1_General_CP1_CI_AS` |
| `DBAdmin` | ONLINE, read/write, compatibility 150, auto update statistics ON, async OFF |
| `AdventureWorks2019` | ONLINE, read/write, compatibility 150, auto update statistics ON, async OFF |

Both database collations are `SQL_Latin1_General_CP1_CI_AS`. The canonical governance identifier columns use `Latin1_General_100_BIN2`; other text columns commonly use the database collation.

## Permanent tables

| Table | Columns |
| --- | ---: |
| `dbo.StatsGovernanceOverrides` | 16 |
| `dbo.StatsGovernanceRunDatabases` | 15 |
| `dbo.StatsGovernanceRuns` | 17 |
| `dbo.StatsGovernanceScope` | 10 |
| `dbo.StatsGovernanceScopeAudit` | 8 |
| `dbo.StatsGovernanceSettings` | 12 |
| `dbo.StatsGovernanceTelemetry` | 29 |

The full 107-column ordinal, type, length, precision, scale, nullability, collation, identity, computed, and default capture is in `artifacts/live_schema_columns_20260923.txt`. Index, key, and check-constraint rows are in the raw inventory. `StatsGovernanceRuns` has `FinishedAtUTC`; it has no `EndedAtUTC` column. `StatsGovernanceTelemetry` has `CommandEndedAtUTC` for individual commands.

## Modules and public interfaces

The export contains 18 module definitions: 9 procedures, 3 functions, 5 views, and 1 trigger. The live inventory also contains the definition of `dbo.usp_DRE_SetStatsDatabaseScope_v1`, which the module export filter omitted. Its live definition is captured in the raw inventory and must be added as a separate source file before release packaging.

`dbo.usp_DRE_StatsGovernance_v1` has exactly the ten documented public parameters, in the documented order and SQL types. `dbo.usp_DRE_StatsGovernanceTargeted_v1` has exactly the eight documented public parameters, in the documented order and SQL types. SQL Server's `sys.parameters.has_default_value` reports 0 for these T-SQL procedures; the default literals are present in their live definitions.

The installed code identifies itself as v1.3.1. The settings table reports schema version `1.3.0`.

## CommandLog

`DBAdmin.dbo.CommandLog` exists with the 16 project-used columns in the documented order. `Command` and `CommandType` are NOT NULL. `IndexType` is nullable `tinyint`. The project must preserve this table's schema.

## Phase 7 evidence

The general inventory and focused Phase 7 query returned no row for the named lab table, any `ENFORCE` run, associated telemetry, CommandLog row, override, or current AdventureWorks2019 scope row. See `artifacts/PHASE7_CURRENT_STATE.md` for the evidence limit and conclusion.

## Qualification boundary

This is a contract capture from the SQL Server 2025 development instance only. It does not prove runtime behavior on SQL Server 2016–2022, compatibility levels 110–170, legacy CE 70, or Azure Managed Instance.
