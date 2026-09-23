# Current Project State — 2026-09-23

The integrated v1.3.2 engine is installed in `DBAdmin` on `DESKTOP-6BVBI90` (SQL Server 2025 CU8, version 17.0.4085.5). Permanent governance schema version remains 1.3.0. The canonical installer is `src/installer/Install_v1.3.2.sql`; 19 module source files are under `src`.

The local installation, installer rerun, fresh installation in a disposable admin database, table contract, report-only smoke, policy/capability matrices, compatibility levels 110–170, CE 70 context, and dedicated-lab `ENFORCE` passed. The final execution test updated one index-associated statistic with `SAMPLE 2500 ROWS` and one standalone statistic with approved `FULLSCAN`; both had `PERSIST_SAMPLE_PERCENT = OFF`, `MAXDOP = 4`, successful postchecks, and exact CommandLog links. See `docs/QUALIFICATION_20260923.md` for run IDs and evidence.

The temporary `AdventureWorks2019` approval, overrides, and lab table were removed. The governance cooldown was restored to 60 minutes. Three disposable databases used for compatibility and fresh-install checks were removed. The third verified installation and OBSERVE when the admin database itself is at compatibility 110. Telemetry and CommandLog evidence are retained in `DBAdmin`.

Remaining qualification: run the same installer and relevant suites on actual SQL Server 2016, 2017, 2019, 2022, and Azure SQL Managed Instance targets. Those environments are not available through the current `localhost` connection, so no runtime-pass claim is made for them.

The code has undergone a separate Microsoft-documentation review for those platforms; see `PLATFORM_COMPATIBILITY.md`. Runtime checks on the closed-off environments belong to the user, using `MANUAL_PLATFORM_VALIDATION.md`.
