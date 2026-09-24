# Release History

## v1.2.3

Important repair baseline.

Resolved earlier installer problems including:

- SQLCMD directives passed to the engine,
- invalid `SET LOCK_TIMEOUT @variable` form,
- unconditional success messages,
- missing CommandLog prerequisite handling,
- collation conflicts,
- transactional deployment ordering.

The user confirmed v1.2.3 worked.

## v1.3.0

Added:

- histogram skew analysis,
- SAMPLE n ROWS support,
- index-family classification,
- explicit FULLSCAN governance,
- targeted table/statistics-scope wrapper.

Installation iterations included r1/r2 fixes for compile-time binding and deployment ordering.

The user reported successful execution of the final v1.3.0-r2 installation and verification scripts.

## v1.3.1

Added:

- native SQL Server auto-update threshold telemetry,
- current table rows versus stats rows,
- row-count delta,
- modification counter,
- native threshold policy,
- governance threshold,
- governance-vs-native comparison,
- CE context reporting separated from threshold formula selection.

The user reported successful OBSERVE/RECOMMEND and targeted tests.

## v1.3.1 qualification repairs

During the first controlled ENFORCE phase, defects were discovered in:

- installer/test assertion expected math,
- rowversion XML serialization,
- nullable scope metadata handling,
- scope-change transaction/readback semantics,
- collation handling in the Phase 7 harness,
- run-table column-name assumptions in the Phase 7 status script.

These should be folded into v1.3.2.

## v1.3.2 integrated local release — 2026-09-23

Installed the integrated source on SQL Server 2025 CU8. It includes the captured 1.3.0 table schema, 19 canonical modules, the scope transaction/readback fix, compatibility-110-safe list parsing, explicit nullability in temporary structures, explicit capability gates, and reproducible contract/policy/execution tests. The installer passed an idempotent rerun and fresh installation in disposable admin databases, including compatibility 110. A dedicated-lab `ENFORCE` run passed with exact CommandLog mapping; lab configuration was removed afterward. See `QUALIFICATION_20260923.md`.

Runtime qualification on SQL Server 2016–2022 and Azure SQL Managed Instance is still pending access to those targets. The capability matrix exercises their feature rules but cannot establish runtime success.

The subsequent platform-documentation audit expanded the build-boundary tests and replaced the collector's boxed SQL Server AG function with `DATABASEPROPERTYEX(..., 'Updateability')`, which Microsoft documents for both SQL Server and Managed Instance replicas. It also made Managed Instance CE feedback support policy-dependent by probing the scoped setting. The audited behavior and sources are in `PLATFORM_COMPATIBILITY.md`.

## v1.3.2 portability and database-selection update — 2026-09-24

- Removed every hardcoded `USE [DBAdmin]` from the installer and executable utility scripts.
- Added `scripts/00_Install.ps1` with a required utility database argument.
- Parameterized the inventory exporter and local SQL runner database.
- Added `SYSTEM_DATABASES` and `USER_DATABASES`; `ALL` now includes supported system and user databases.
- Included Microsoft-shipped tables when collecting `master`, `model`, and `msdb`.
- Excluded `tempdb`, `SSISDB`, and replication distribution databases.
- Added selection and last-moment gates for local Always On secondary replicas.
- Added database-selection contracts and a system-database report-only smoke test.
- Verified a fresh install in an arbitrarily named disposable utility database and reran the policy, compatibility-level 110–170, CE 70, and context-independent lab tests.

No new `ENFORCE` test was run for this update. The prior dedicated-lab execution evidence remains the current enforcement qualification.

## Original v1.3.2 objective

Produce one integrated release containing:

- authoritative schema contracts,
- corrected control-plane modules,
- canonical collations/nullability,
- binary-safe serialization,
- robust scope transaction semantics,
- contract tests,
- policy tests,
- controlled execution tests,
- read-only current-state inspection,
- documentation,
- release validation record.

No layered rN hotfix chain.
