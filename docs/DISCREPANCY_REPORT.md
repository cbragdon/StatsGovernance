# Discrepancy Report

Evidence: read-only inventory captured 2026-09-23 15:34–15:35 UTC at `artifacts/live_inventory_20260923_153454Z/`. This report distinguishes verified live differences from historical defect reports. No SQL Server change has been made in this review.

| Classification | Object / area | Live value | Repository or intended value | Risk | v1.3.2 treatment | Schema migration | Engine code | Test only |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LIVE_ONLY | Installed governance objects | Seven permanent tables and 19 governance modules are installed; 18 module definitions were exported separately and the scope setter definition is in `inventory.txt`. | `src/` is empty; no canonical installer or source tree exists. | A new installation cannot be reproduced from this repository. | Capture every live definition, script the verified tables and constraints, and build one integrated installer. | Possibly, only if comparison requires it | Yes | Yes |
| BEHAVIORAL_RISK | `dbo.usp_DRE_SetStatsDatabaseScope_v1` | The procedure commits its scope change, then calls `usp_DRE_StatsScopeLookup_v1` outside the transaction. | The documented v1.3.2 behavior requires final lookup validation before COMMIT. | A caller can receive an error after a committed change. | Move lookup/readback validation inside the transaction and test rollback on failure. | No | Yes | Yes |
| TEST_HARNESS_DEFECT | Phase 7 run status | `StatsGovernanceRuns` has `FinishedAtUTC`; individual telemetry has `CommandEndedAtUTC`. | Prior harness selected nonexistent `EndedAtUTC` from the run table. | Status inspection failed. | Use contract-checked column names in the new harness. | No | No | Yes |
| TEST_HARNESS_DEFECT | Phase 7 identifier comparison | Governance identifier columns are `Latin1_General_100_BIN2`; database default is `SQL_Latin1_General_CP1_CI_AS`. | Prior `EXCEPT` compared identifiers with incompatible collations. | A late assertion failed and obscured execution outcome. | Give identifier-bearing test structures explicit canonical collation. | No | No | Yes |
| NO_DISCREPANCY | Public entry points | Main procedure has ten documented parameters; targeted wrapper has eight, with documented order and types. | Matches `AGENTS.md` and `DESIGN_DECISIONS.md`. | None found in shape. | Preserve exactly. | No | No | Yes |
| NO_DISCREPANCY | Binary serialization hotfix | Live scope audit trigger and scope lookup use `sys.fn_varbintohexstr(Revision)` for XML. | Matches documented correction. | None found in these two modules. | Preserve and test all serialization paths. | No | No | Yes |
| NO_DISCREPANCY | Nullable scope hotfix | Live scope lookup explicitly declares `ExcludedBy` and `ApprovedBy` nullable. | Matches documented correction. | None found in this table variable. | Preserve and test. | No | No | Yes |

## Open verification

- The focused Phase 7 query found no retained lab table, `ENFORCE` run, telemetry, CommandLog, override, or scope row. The historical execution outcome remains unproven; see `artifacts/PHASE7_CURRENT_STATE.md`.
- Cross-version and Azure Managed Instance behavior cannot be certified from a single SQL Server 2025 instance. Build-specific capability gates require documented verification and runtime qualification on representative targets.
- The exported module list omitted the scope setter due to the exporter filter. The live inventory contains its complete definition; the release source tree must include it.
