# Codex First Task (historical handoff)

This first-task checklist was completed on 2026-09-23. Use `CURRENT_STATE.md` and `QUALIFICATION_20260923.md` for current status.

## Goal

Establish the actual live contract and determine the current Phase 7 state before making any change.

## Rules

- Read `AGENTS.md` first.
- Do not run ENFORCE.
- Do not drop the Phase 7 lab object.
- Do not delete governance telemetry.
- Do not delete CommandLog evidence.
- Do not modify DBAdmin or AdventureWorks2019 during this task.
- Windows Authentication only.
- Do not store credentials.

## Step 1 - Determine available local SQL tooling

From the local Windows project environment, determine whether these are available:

```text
sqlcmd
Invoke-Sqlcmd / SqlServer PowerShell module
Microsoft.Data.SqlClient tooling
```

Prefer an installed Microsoft-supported client.

Example connectivity probe if `sqlcmd` is available:

```powershell
sqlcmd -S DESKTOP-6BVBI90 -E -d DBAdmin -Q "SET NOCOUNT ON; SELECT @@SERVERNAME AS ServerName, @@VERSION AS VersionText;"
```

This is read-only.

## Step 2 - Run the repository inventory script

Execute:

```text
scripts\00_ReadOnly_Live_Inventory.sql
```

against `DBAdmin` on `DESKTOP-6BVBI90`.

Capture all result sets to a repository artifact, for example:

```text
artifacts\live_inventory_<timestamp>.txt
```

Do not edit the database if the inventory script reports a mismatch.

## Step 3 - Inspect installed module definitions

Export the definitions of every governance object into:

```text
artifacts\live_modules\
```

Use deterministic filenames.

Example:

```text
dbo.usp_DRE_StatsGovernance_v1.sql
dbo.usp_DRE_StatsGovernanceTargeted_v1.sql
dbo.usp_DRE_StatsScopeLookup_v1.sql
dbo.usp_DRE_SetStatsDatabaseScope_v1.sql
dbo.tr_DRE_StatsScopeAudit_v1.sql
...
```

Do not overwrite repository source as part of this export.

## Step 4 - Determine the Phase 7 execution state

Read-only.

Determine:

1. whether `AdventureWorks2019.DREStatsLab.StatsEnforceQualification` exists,
2. whether a recent ENFORCE run exists for that object,
3. the actual run status,
4. the actual run-table completion timestamp column,
5. how many telemetry rows exist for the lab object,
6. execution status for each statistic,
7. whether CommandLog IDs are present,
8. whether the linked CommandLog rows show successful completion,
9. current modification counters and rows sampled,
10. whether the temporary overrides remain,
11. whether AdventureWorks2019 scope differs from its pre-test state if reconstructable from audit history.

Do not rerun the test.

## Step 5 - Produce documentation

Update:

```text
docs\LIVE_SCHEMA_CONTRACT.md
docs\DISCREPANCY_REPORT.md
```

Also create:

```text
artifacts\PHASE7_CURRENT_STATE.md
```

State explicitly whether evidence indicates:

```text
A. ENFORCE completed successfully and only the harness failed,
B. ENFORCE partially completed,
C. ENFORCE did not execute,
D. evidence is insufficient.
```

Do not make a new execution attempt.

## Step 6 - Stop for user review

Present:

- live contract summary,
- discrepancy report,
- Phase 7 current-state conclusion,
- proposed v1.3.2 work plan.

Do not modify SQL Server until the user approves the next step.
