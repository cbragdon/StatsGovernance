# Portability and System Database Qualification — 2026-09-24

## Environment

- Server: `DESKTOP-6BVBI90`
- SQL Server: 2025 CU8, `17.0.4085.5`
- Utility database used for installed-engine tests: `DBAdmin`
- Alternate utility database used for fresh-install testing: `StatsGovCustomUtilityV132`
- CommandLog bootstrap database (compatibility 110, created and removed): `StatsGovCommandLogBootstrapV132`
- Authentication: Windows Authentication through the existing local SQL runner

## Changes under test

- Installer uses the caller-selected connection database and contains no `USE` statement.
- Automation accepts a utility database name.
- Group selectors: `SYSTEM_DATABASES`, `USER_DATABASES`, and `ALL`.
- Supported system targets: `master`, `model`, and `msdb`.
- Exclusions: `tempdb`, `SSISDB`, replication distribution databases, snapshots, unavailable databases, and local Always On secondary replicas.
- Microsoft-shipped tables are visible in supported system databases.
- Always On primary state is checked during selection and again before work.
- A missing `dbo.CommandLog` is created with the standard Ola-compatible schema; an existing compatible table and its rows are preserved.

## Executed evidence

| Queue job | Result | Evidence |
| --- | --- | --- |
| `066_Install_ContextAndSystem` | Exit 0 | Installer, table contract, module contract, and database-selection contract passed. `SYSTEM_DATABASES` resolved three databases. |
| `067_System_Database_Smoke` | Exit 0 | `SYSTEM_DATABASE_OBSERVE_PASS`; RunID `1ABACF74-E68A-40AA-8FA8-6FD25A28A6D6`. `master`, `model`, and `msdb` were collected; `msdb` produced 273 statistic candidates; CommandLog remained unchanged. |
| `068_Custom_Utility_Install` | Exit 0 | Fresh install and all contracts passed in `StatsGovCustomUtilityV132`. The installer preserved that caller-selected context. The disposable database was removed. |
| `069_Policy_Regression` | Exit 0 | Report-only smoke, decision matrix, and capability matrix passed. |
| `070_Context_Lab_Setup_Recommend_Cleanup` | Exit 0 | Revised scripts ran from the supplied utility database; dedicated lab setup, RECOMMEND, and cleanup passed. |
| `071_Context_Compatibility_Lab` | Exit 0 | Compatibility levels 110, 120, 130, 140, 150, 160, and 170 passed; CE 70 context passed. |
| `072_Compatibility_Lab_Cleanup` | Exit 0 | Disposable compatibility database removed. |
| `073_AlwaysOn_Selection_Contract` | Exit 0 | Reinstalled the final modules and passed the expanded database-selection contract. The contract conditionally verifies explicit distribution-database rejection and explicit Always On secondary blocking when those database types exist. |
| `079_CommandLog_Bootstrap_Compat110` | Exit 0 | Created a compatibility-level-110 utility database with no `dbo.CommandLog`; the installer created the table, passed its contract, preserved the same object through a rerun, passed all remaining contracts, and removed the disposable database. |
| `078_Existing_CommandLog_Preserve` | Exit 0 | Reinstalled in `DBAdmin`; the existing `dbo.CommandLog` retained the same object identity, creation date, and all 10 rows. |

All job `stderr.txt` files were empty.

## Evidence boundaries

The local instance has no accessible Always On secondary, SSISDB catalog, or replication distribution database. Their exclusion branches are implemented against `sys.fn_hadr_is_primary_replica`, the fixed `SSISDB` catalog name, and `sys.databases.is_distributor`, and are covered by contract assertions where the corresponding database exists. Runtime validation of an actual secondary and distribution database remains part of manual platform testing.

No `ENFORCE` run was performed for this update. The execution path and CommandLog behavior retain the dedicated-lab qualification from `QUALIFICATION_20260923.md`.
