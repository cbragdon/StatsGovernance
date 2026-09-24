# Architecture

## Operational modes

The engine exposes three operational modes:

```text
OBSERVE
RECOMMEND
ENFORCE
```

### OBSERVE

Collect and store/report telemetry without executing statistics maintenance.

### RECOMMEND

Evaluate the policy engine and produce proposed actions/commands without executing statistics maintenance.

### ENFORCE

Execute only actions that pass all eligibility, capability, scope, policy, and safety gates.

Only ENFORCE may write execution rows to `dbo.CommandLog` in the selected utility database.

During installation, the engine creates the standard Ola-compatible `dbo.CommandLog` table when it is absent. If the table already exists, installation validates its required columns, nullability, identity, and clustered primary key without replacing the table or changing retained rows.

## Decision separation

The architecture deliberately separates three questions:

```text
1. Does this statistic need maintenance?
2. If maintenance is eligible, how should it be collected?
3. Should the sampling percentage be persisted?
```

These must not be collapsed into one heuristic.

Examples of forbidden shortcuts:

- low sample rate -> FULLSCAN,
- skew -> FULLSCAN,
- identity/datetime -> FULLSCAN,
- legacy CE -> FULLSCAN,
- delta-store state -> FULLSCAN.

## Eligibility

Eligibility can use signals such as:

- modification counter,
- governance modification threshold,
- cooldown,
- load events when explicitly represented,
- approved overrides,
- supported evidence.

The current governance gate uses the existing engine rule based on the larger of:

```text
MinModificationCount
CEILING(StatsRowsAtLastUpdate * UpdateThresholdPercent / 100)
```

with the existing zero-baseline behavior preserved.

## Native threshold telemetry

Native auto-update threshold telemetry is informational context beside governance policy.

It must not be treated as the governance decision itself.

The formula selector is based on SQL Server version/build behavior, compatibility level, and TF 2371 state, not CE mode.

For a qualifying modern dynamic-threshold environment:

```text
MIN(500 + 0.20*n, SQRT(1000*n))
```

For small tables:

```text
n <= 500 -> 500 modifications
```

For legacy behavior:

```text
500 + 0.20*n
```

`modification_counter` tracks changes to the leading statistics column and is not identical to row-count change.

Crossing the estimated native threshold does not guarantee an immediate automatic statistics update; optimizer use/compilation context still matters.

## Statistics context

Statistics are classified as:

```text
INDEX_ASSOCIATED
STANDALONE_ON_TABLE_WITH_COLUMNSTORE
STANDALONE
```

Index families are reported independently.

## Persistence

Persistence policy is independent from collection method.

A one-time FULLSCAN does not imply:

```text
PERSIST_SAMPLE_PERCENT = ON
```

`SAMPLE n ROWS` cannot persist a row count because SQL Server persists a percentage, not a row count.

## Execution logging

Execution must:

1. build the exact command,
2. insert one CommandLog row,
3. capture inserted `ID`,
4. execute the command,
5. update that exact CommandLog row with completion or error details,
6. perform post-check metadata collection,
7. update engine telemetry for the same statistic.

Do not identify an execution row later using only descriptive columns when the inserted ID is available.

## Safety

ENFORCE must be protected by:

- explicit database scope/approval,
- mode validation,
- application lock,
- maintenance-window soft stop,
- capability gates,
- object-existence checks,
- dedicated error capture,
- deterministic CommandLog correlation.
- rejection of `tempdb`, `SSISDB`, and replication distribution databases,
- local-primary validation for Always On availability databases at selection and immediately before work.

## Collation

Governance identifier comparison is a contract, not an incidental database-default behavior.

The project has used:

```text
Latin1_General_100_BIN2
```

for canonical identifier comparison.

Intermediate structures participating in set operations or joins should use the same explicit collation.

## Binary values and XML

Never send raw/character-converted rowversion bytes through XML.

Use:

```sql
sys.fn_varbintohexstr(Revision)
```

for XML/text representation.
