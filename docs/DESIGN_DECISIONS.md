# Frozen Design Decisions

These decisions should be treated as frozen unless the user explicitly changes them.

## Public interfaces

### Main procedure

`dbo.usp_DRE_StatsGovernance_v1`

Exactly ten public parameters:

```text
@Databases
@Mode='RECOMMEND'
@MAXDOP=4
@MinRowCountFloor=1000000
@LowSampleThresholdBase=2.0
@LargeTableThresholdBase=20000000
@DefaultSamplePercentBase=NULL
@MaxExecutionTimeMinutes=300
@IOThroughputTier='STANDARD'
@LegacyCEMultiplier=2.0
```

### Targeted wrapper

`dbo.usp_DRE_StatsGovernanceTargeted_v1`

Exactly eight public parameters:

```text
@Databases
@Tables=NULL
@StatisticsScope='ALL'
@Mode='RECOMMEND'
@MAXDOP=4
@MinRowCountFloor=1000000
@MaxExecutionTimeMinutes=300
@IOThroughputTier='STANDARD'
```

## Targeted table syntax

Table targets are comma-separated and schema-qualified:

```text
schema.table
```

When targets are supplied:

- exactly one database must resolve,
- every table must resolve,
- `ALL` databases plus an explicit table list is invalid.

## Statistics scopes

```text
ALL
INDEX_ONLY
AUTO_ONLY
USER_ONLY
NON_AUTO
```

Definitions:

- `INDEX_ONLY`: index-associated statistics.
- `AUTO_ONLY`: standalone auto-created statistics.
- `USER_ONLY`: standalone user-created statistics.
- `NON_AUTO`: index-associated plus standalone user-created; excludes auto-created.
- `ALL`: all supported statistics contexts.

## FULLSCAN policy

FULLSCAN is never automatic because of skew, identity, datetime, low sampling, legacy CE, or columnstore delta-store state.

Approved `FORCE_FULLSCAN` is an allowed path.

## SAMPLE ROWS policy

`FORCE_SAMPLE_ROWS`:

- `SampleRows` populated,
- `SamplePercent` NULL,
- automatic row sampling does not add persistence,
- KEEP plus an existing persisted percentage must not silently replace that percentage,
- ON is rejected for row-count sampling.

## MAXDOP

Default statistics-maintenance MAXDOP:

```text
4
```

MAXDOP is not a spill cure. It is an execution-resource control and version/build capability must be checked.

## CommandLog

Database:

```text
DBAdmin
```

Never rename to `AdminDB`.

Do not modify the existing CommandLog table schema.

Report-only modes must not insert CommandLog rows.

## Maintenance window

Default:

```text
300 minutes
```

The deadline is a soft stop. Do not start new work after the deadline. Do not imply that an in-flight SQL Server statement can always be stopped cleanly at the deadline.

## Histogram skew defaults

```text
ModerateSkewThresholdPercent = 5.0
HighSkewThresholdPercent = 10.0
ExtremeSkewThresholdPercent = 25.0
HighSkewSampleRows = 5,000,000
ExtremeSkewSampleRows = 10,000,000
SkewSamplingEnabled = 0
```

## Native threshold reporting

Expose native and governance thresholds side-by-side.

Do not describe CE mode as the native threshold selector.

Do not cap progress percent at 100.

## Deletion

Do not automatically delete statistics based on usage signals.

## Columnstore

Distinguish:

- index-associated columnstore statistics,
- standalone statistics on a table that also has columnstore,
- rowstore statistics.

Delta-store observations are advisory, not automatic deletion or FULLSCAN triggers.

## Incremental statistics

Partition-aware handling is a future/explicit feature area. Do not fake partition-specific behavior if it is not implemented.

## Unsupported capabilities

Use explicit blocked/deferred statuses instead of silently changing semantics.

Examples:

```text
BLOCKED_CAPABILITY
COLUMNSTORE_INDEX_STATISTIC_DEFERRED
XML_INDEX_STATISTIC_DEFERRED
SPATIAL_INDEX_STATISTIC_DEFERRED
HASH_INDEX_STATISTIC_DEFERRED
JSON_INDEX_STATISTIC_DEFERRED
UNKNOWN_INDEX_FAMILY_DEFERRED
```
