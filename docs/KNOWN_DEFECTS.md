# Known Defects and Lessons from v1.3.1 Qualification

This file records defects discovered during qualification so they are fixed in the integrated v1.3.2 source rather than patched repeatedly.

## 1. Regression assertion math mismatch

A v1.3.1 installer regression fixture used:

```text
ModificationCounter = 20,000,000
GovernanceEffectiveModificationThreshold = 10,000,000
```

The correct progress is:

```text
200 percent
```

The test incorrectly expected 500 percent.

Lesson: policy fixtures must calculate expected values from one authoritative formula and should avoid duplicated handwritten expected math.

## 2. rowversion -> XML serialization failure

Observed error:

```text
Msg 6841
FOR XML could not serialize the data for node 'Revision'
because it contains character 0x0000.
```

Cause:

A binary/rowversion value was converted in a character form unsafe for XML.

Required correction:

```sql
sys.fn_varbintohexstr(Revision)
```

Apply consistently in trigger/procedure/view/report paths.

## 3. Nullable sysname mismatch in scope lookup

Observed error:

```text
Msg 515
Cannot insert the value NULL into column 'ExcludedBy', table '@ScopeRows'
```

Cause:

A table variable used `sysname` columns without explicit NULL, while permanent scope columns such as `ExcludedBy` and `ApprovedBy` are nullable.

Required rule:

Declare nullability explicitly everywhere.

Example:

```sql
ExcludedBy sysname COLLATE <canonical_collation> NULL,
ApprovedBy sysname COLLATE <canonical_collation> NULL
```

## 4. Scope procedure transaction boundary

During qualification, the database-scope change could commit before the procedure's final lookup/readback failed.

This created a recovery requirement even though the caller saw an error.

Required v1.3.2 behavior:

```text
BEGIN TRAN
apply scope change
perform/validate final lookup
COMMIT
return result
```

Any validation/readback failure before COMMIT must roll back the scope change.

## 5. Collation conflict in Phase 7 harness

Observed error:

```text
Msg 468
Cannot resolve the collation conflict between
Latin1_General_100_BIN2
and
SQL_Latin1_General_CP1_CI_AS
in the EXCEPT operation.
```

Cause:

The qualification harness compared an intermediate sysname using DBAdmin default collation with the canonical governance identifier collation.

Required rule:

All identifier-bearing intermediate structures used in equality, joins, set operators, or EXCEPT/INTERSECT should use the canonical identifier collation explicitly.

## 6. Qualification script referenced nonexistent run-table column

Observed error:

```text
Msg 207
Invalid column name 'EndedAtUTC'
```

The canonical project contract uses:

```text
FinishedAtUTC
```

Lesson:

Qualification scripts must consume one canonical schema manifest and should execute contract assertions before using tables/views.

## 7. Layered patching

The v1.3.1 qualification process accumulated r1/r2/r3/r4 repair artifacts.

Required release-management change:

Do not create another incremental hotfix chain.

Build v1.3.2 from one canonical source after live-state inventory and discrepancy review.
