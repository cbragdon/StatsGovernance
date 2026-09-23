# SQL Server Statistics Governance Engine

Integrated v1.3.2 source and qualification record for statistics maintenance in SQL Server. `DBAdmin` houses the engine; target databases remain separate. The engine records observations, recommends per-statistic commands, and executes approved maintenance only in `ENFORCE` mode.

## Install

Run `src/installer/Install_v1.3.2.sql` in SQLCMD mode with Windows Authentication:

```powershell
sqlcmd -S localhost -E -C -I -d DBAdmin -b -i D:\Projects\StatsGovernance\src\installer\Install_v1.3.2.sql
```

`-C` trusts the local server certificate. The installer checks the existing Ola-compatible `DBAdmin.dbo.CommandLog` and never changes its schema. It creates missing governance tables, validates the 1.3.0 table contract, and installs 19 modules as v1.3.2. A rerun is supported.

## Run

```sql
EXEC DBAdmin.dbo.usp_DRE_StatsGovernanceTargeted_v1
    @Databases = N'AdventureWorks2019',
    @Tables = N'Sales.SalesOrderHeader',
    @StatisticsScope = 'INDEX_ONLY',
    @Mode = 'RECOMMEND';
```

Start with `OBSERVE` or `RECOMMEND`. `ENFORCE` requires an enabled database scope approval and writes one CommandLog row per attempted statistic. The public main and targeted interfaces retain their ten and eight parameters, respectively. Default `@MAXDOP` is 4. See `docs/DESIGN_DECISIONS.md` for policy, `docs/PLATFORM_COMPATIBILITY.md` for the Microsoft-documentation review, `docs/QUALIFICATION_20260923.md` for tested behavior, and `docs/MANUAL_PLATFORM_VALIDATION.md` for testing on other instances.

## Qualification boundary

The integrated installer, report modes, policy gates, compatibility levels 110–170, CE 70, and controlled `ENFORCE` were exercised on local SQL Server 2025 CU8. Runtime testing on SQL Server 2016–2022 and Azure SQL Managed Instance still requires those target instances. Capability simulations cover their documented feature boundaries but do not replace runtime qualification.
