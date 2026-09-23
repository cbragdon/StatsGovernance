# v1.3.2 Qualification — 2026-09-23

## Environment and source

- Server: `DESKTOP-6BVBI90`, SQL Server 2025 Enterprise Developer CU8, `17.0.4085.5`.
- Administrative database: `DBAdmin`, compatibility 150.
- Target test database: `AdventureWorks2019`, compatibility 150.
- Source: `src/installer/Install_v1.3.2.sql`, generated from the captured live 1.3.0 schema and 19 module definitions with integrated compatibility and scope fixes.
- Evidence: `artifacts/sql_queue/completed/<number>_<test>/status.json` and `output.txt`; a zero exit code and explicit `*_PASS` marker are required.

## Passed checks

| Check | Evidence |
| --- | --- |
| Exact seven-table, 107-column live contract | `003_Table_Contract`, `TABLE_CONTRACT_PASS` |
| Required modules, public procedure names/order/types, and CommandLog interface | `039_Module_Type_Contract`, `MODULE_AND_PUBLIC_CONTRACT_PASS` |
| Integrated installer and idempotent rerun | `004_Install_v1.3.2`, `018_Installer_Rerun` |
| Fresh install in disposable admin database; seven tables and 19 modules | `020_Fresh_Install_Lab`, `021_Verify_Cleanup_Labs` |
| Fresh install and OBSERVE with the admin database at compatibility 110 | `035_Fresh_Install110`, `036_Admin_Compat110_Observe`, `037_Cleanup_Install110` |
| OBSERVE and RECOMMEND perform no maintenance or CommandLog writes | `005_Report_Only_Smoke` |
| Eligibility, skew/FULLSCAN, override, and capability gates | `006_Decision_Matrix`, `007_Capability_Matrix` |
| Compatibility 110, 120, 130, 140, 150, 160, 170 | `017_Compatibility_Lab`, seven `COMPAT_LEVEL_PASS` markers |
| Legacy CE 70 at compatibility 170 | `017_Compatibility_Lab`, `CE70_PASS` |
| Controlled RECOMMEND and ENFORCE against dedicated lab table | `029_Recommend_Lab_Final`, `030_Enforce_Lab_Final` |
| Restore approval, overrides, lab table, and cooldown | `031_Cleanup_Lab_Final`, `LAB_CLEANUP_PASS` |
| Exact index/standalone CommandLog mapping and restored final state | `033_Final_State_Verification`, `FINAL_STATE_AND_COMMANDLOG_PASS` |
| Rebuilt package after explicit temporary/table-variable nullability audit, module contract, and report-only smoke | `040_Install_Explicit_Nullability`, `041_Module_Contract_Final`, `042_Report_Smoke_Final` |
| Documentation-audited writeability gate, compatibility 110–170 and CE 70, controlled lab enforcement | `043_Platform_Audit_Install` through `051_Platform_Lab_Cleanup`; all nine exits zero |
| Managed Instance policy-dependent CE feedback handling, expanded build matrix, final installer and contracts | `052_Platform_Policy_Install` through `055_Platform_Report_Smoke`; all four exits zero |
| Final-source clean install and OBSERVE with admin compatibility 110 | `056_Final_Setup_Install110` through `059_Final_Cleanup_Install110`; all four exits zero |
| Final installed source and cleanup state | `060_Final_Platform_State`, `FINAL_PLATFORM_STATE_PASS` |
| Final controlled lab run after platform-policy changes and safer setup preflight | `061_Final_Lab_Setup` through `064_Final_Lab_Cleanup`; all four exits zero |
| Released-state check after final cleanup | `065_Released_State`, `FINAL_PLATFORM_STATE_PASS` |

The final recommendation RunID was `1D019F05-3F08-4087-B1FD-6E779696E12F`. The final enforcement RunID was `F95CCE26-E332-4996-9EB1-A44AB964A3DA`. The index-associated statistic used `SAMPLE 2500 ROWS`; the standalone statistic used explicitly approved `FULLSCAN`. Both used `PERSIST_SAMPLE_PERCENT = OFF` and `MAXDOP = 4`, finished `SUCCEEDED`, returned `METADATA_COLLECTED`, and linked to successful CommandLog records. The primary key statistic was deferred.

The 60-minute cooldown initially deferred freshly created statistics with reason `UPDATE_COOLDOWN`. The qualification setup temporarily set the cooldown to zero and the cleanup restored 60. This confirmed the cooldown gate and allowed a fresh dedicated fixture to execute.

## Limits

Runtime tests above ran on SQL Server 2025 only. The capability matrix simulated SQL Server 2016–2022 and Managed Instance builds, but actual installation and execution on those targets remain unverified. `MAXDOP`, persisted sampling, and histogram support are build gated and should be checked on each target. No server-level settings were changed.

The Microsoft-documentation review and the two platform fixes are recorded in `PLATFORM_COMPATIBILITY.md`. The user will run the `MANUAL_PLATFORM_VALIDATION.md` procedure on closed-off targets.
