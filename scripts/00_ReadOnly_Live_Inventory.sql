/*
  Statistics Governance Engine
  Codex Handoff - Read-Only Live Inventory

  Target instance: DESKTOP-6BVBI90
  Starting database: supplied by the caller

  This script performs metadata SELECTs only.
  It does not execute maintenance, DDL, configuration DML, or CommandLog DML.
*/

SET NOCOUNT ON;
SET XACT_ABORT OFF;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE
    @TargetDb sysname = N'AdventureWorks2019',
    @AdminDb sysname = DB_NAME(),
    @LabSchema sysname = N'DREStatsLab',
    @LabTable sysname = N'StatsEnforceQualification';

--------------------------------------------------------------------------------
-- 1. SERVER
--------------------------------------------------------------------------------
SELECT
    @@SERVERNAME AS ServerName,
    CONVERT(nvarchar(128), SERVERPROPERTY('MachineName')) AS MachineName,
    CONVERT(nvarchar(128), SERVERPROPERTY('InstanceName')) AS InstanceName,
    CONVERT(nvarchar(128), SERVERPROPERTY('ProductVersion')) AS ProductVersion,
    CONVERT(nvarchar(128), SERVERPROPERTY('ProductLevel')) AS ProductLevel,
    CONVERT(nvarchar(256), SERVERPROPERTY('Edition')) AS Edition,
    CONVERT(int, SERVERPROPERTY('EngineEdition')) AS EngineEdition,
    CONVERT(nvarchar(128), SERVERPROPERTY('ProductUpdateLevel')) AS ProductUpdateLevel,
    CONVERT(nvarchar(256), SERVERPROPERTY('ProductUpdateReference')) AS ProductUpdateReference,
    CONVERT(sysname, SERVERPROPERTY('Collation')) AS ServerCollation,
    SYSDATETIMEOFFSET() AS CapturedAt;

--------------------------------------------------------------------------------
-- 2. DATABASE CONTRACT
--------------------------------------------------------------------------------
SELECT
    database_id,
    name,
    state_desc,
    is_read_only,
    compatibility_level,
    collation_name,
    is_auto_update_stats_on,
    is_auto_update_stats_async_on,
    recovery_model_desc
FROM sys.databases
WHERE name IN (@AdminDb, @TargetDb)
ORDER BY name;

--------------------------------------------------------------------------------
-- 3. GOVERNANCE TABLES
--------------------------------------------------------------------------------
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    t.object_id,
    t.create_date,
    t.modify_date
FROM sys.tables AS t
JOIN sys.schemas AS s
  ON s.schema_id = t.schema_id
WHERE s.name = N'dbo'
  AND t.name LIKE N'StatsGovernance%'
ORDER BY t.name;

--------------------------------------------------------------------------------
-- 4. GOVERNANCE TABLE COLUMN CONTRACT
--------------------------------------------------------------------------------
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    c.column_id,
    c.name AS ColumnName,
    ty.name AS TypeName,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    c.collation_name,
    c.is_identity,
    c.is_computed,
    dc.name AS DefaultConstraintName,
    dc.definition AS DefaultDefinition
FROM sys.tables AS t
JOIN sys.schemas AS s
  ON s.schema_id = t.schema_id
JOIN sys.columns AS c
  ON c.object_id = t.object_id
JOIN sys.types AS ty
  ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.default_constraints AS dc
  ON dc.parent_object_id = c.object_id
 AND dc.parent_column_id = c.column_id
WHERE s.name = N'dbo'
  AND t.name LIKE N'StatsGovernance%'
ORDER BY t.name, c.column_id;

--------------------------------------------------------------------------------
-- 5. GOVERNANCE INDEXES / KEYS
--------------------------------------------------------------------------------
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    i.name AS IndexName,
    i.index_id,
    i.type_desc,
    i.is_unique,
    i.is_primary_key,
    i.is_unique_constraint,
    i.has_filter,
    i.filter_definition,
    ic.key_ordinal,
    ic.is_included_column,
    c.name AS ColumnName
FROM sys.tables AS t
JOIN sys.schemas AS s
  ON s.schema_id = t.schema_id
JOIN sys.indexes AS i
  ON i.object_id = t.object_id
LEFT JOIN sys.index_columns AS ic
  ON ic.object_id = i.object_id
 AND ic.index_id = i.index_id
LEFT JOIN sys.columns AS c
  ON c.object_id = ic.object_id
 AND c.column_id = ic.column_id
WHERE s.name = N'dbo'
  AND t.name LIKE N'StatsGovernance%'
ORDER BY t.name, i.index_id, ic.key_ordinal, ic.index_column_id;

--------------------------------------------------------------------------------
-- 6. CHECK CONSTRAINTS
--------------------------------------------------------------------------------
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    cc.name AS ConstraintName,
    cc.definition,
    cc.is_disabled,
    cc.is_not_trusted
FROM sys.check_constraints AS cc
JOIN sys.tables AS t
  ON t.object_id = cc.parent_object_id
JOIN sys.schemas AS s
  ON s.schema_id = t.schema_id
WHERE s.name = N'dbo'
  AND t.name LIKE N'StatsGovernance%'
ORDER BY t.name, cc.name;

--------------------------------------------------------------------------------
-- 7. GOVERNANCE MODULE INVENTORY
--------------------------------------------------------------------------------
SELECT
    s.name AS SchemaName,
    o.name AS ObjectName,
    o.type,
    o.type_desc,
    o.object_id,
    o.create_date,
    o.modify_date,
    HASHBYTES('SHA2_256', CONVERT(varbinary(max), m.definition)) AS DefinitionSHA256
FROM sys.objects AS o
JOIN sys.schemas AS s
  ON s.schema_id = o.schema_id
LEFT JOIN sys.sql_modules AS m
  ON m.object_id = o.object_id
WHERE s.name = N'dbo'
  AND
  (
      o.name LIKE N'%StatsGovernance%'
      OR o.name LIKE N'%StatsScope%'
      OR o.name LIKE N'%StatsOverride%'
      OR o.name LIKE N'%StatsDatabaseScope%'
  )
ORDER BY o.type_desc, o.name;

--------------------------------------------------------------------------------
-- 8. PROCEDURE/FUNCTION PARAMETERS
--------------------------------------------------------------------------------
SELECT
    s.name AS SchemaName,
    o.name AS ObjectName,
    o.type_desc,
    p.parameter_id,
    p.name AS ParameterName,
    ty.name AS TypeName,
    p.max_length,
    p.precision,
    p.scale,
    p.is_output,
    p.has_default_value,
    p.default_value
FROM sys.objects AS o
JOIN sys.schemas AS s
  ON s.schema_id = o.schema_id
JOIN sys.parameters AS p
  ON p.object_id = o.object_id
JOIN sys.types AS ty
  ON ty.user_type_id = p.user_type_id
WHERE s.name = N'dbo'
  AND
  (
      o.name LIKE N'%StatsGovernance%'
      OR o.name LIKE N'%StatsScope%'
      OR o.name LIKE N'%StatsOverride%'
      OR o.name LIKE N'%StatsDatabaseScope%'
  )
ORDER BY o.name, p.parameter_id;

--------------------------------------------------------------------------------
-- 9. COMMANDLOG CONTRACT
--------------------------------------------------------------------------------
SELECT
    c.column_id,
    c.name AS ColumnName,
    ty.name AS TypeName,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    c.collation_name,
    c.is_identity,
    dc.definition AS DefaultDefinition
FROM sys.columns AS c
JOIN sys.types AS ty
  ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.default_constraints AS dc
  ON dc.parent_object_id = c.object_id
 AND dc.parent_column_id = c.column_id
WHERE c.object_id = OBJECT_ID(N'dbo.CommandLog')
ORDER BY c.column_id;

--------------------------------------------------------------------------------
-- 10. SETTINGS
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.StatsGovernanceSettings', N'U') IS NOT NULL
    SELECT * FROM dbo.StatsGovernanceSettings;

--------------------------------------------------------------------------------
-- 11. SCOPE
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.StatsGovernanceScope', N'U') IS NOT NULL
BEGIN
    SELECT
        DatabaseName,
        EnabledForEnforcement,
        ApprovedBy,
        ApprovedAtUTC,
        Notes,
        IsExcluded,
        ExclusionReason,
        ExcludedBy,
        ExcludedAtUTC,
        sys.fn_varbintohexstr(Revision) AS RevisionHex
    FROM dbo.StatsGovernanceScope
    ORDER BY DatabaseName;
END;

--------------------------------------------------------------------------------
-- 12. OVERRIDES
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.StatsGovernanceOverrides', N'U') IS NOT NULL
    SELECT *
    FROM dbo.StatsGovernanceOverrides
    ORDER BY DatabaseName, SchemaName, TableName, StatName;

--------------------------------------------------------------------------------
-- 13. RUN TABLE CONTRACT
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.StatsGovernanceRuns', N'U') IS NOT NULL
BEGIN
    SELECT
        c.column_id,
        c.name AS ColumnName,
        ty.name AS TypeName,
        c.max_length,
        c.precision,
        c.scale,
        c.is_nullable,
        c.collation_name
    FROM sys.columns AS c
    JOIN sys.types AS ty
      ON ty.user_type_id = c.user_type_id
    WHERE c.object_id = OBJECT_ID(N'dbo.StatsGovernanceRuns')
    ORDER BY c.column_id;
END;

--------------------------------------------------------------------------------
-- 14. TELEMETRY TABLE CONTRACT
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.StatsGovernanceTelemetry', N'U') IS NOT NULL
BEGIN
    SELECT
        c.column_id,
        c.name AS ColumnName,
        ty.name AS TypeName,
        c.max_length,
        c.precision,
        c.scale,
        c.is_nullable,
        c.collation_name
    FROM sys.columns AS c
    JOIN sys.types AS ty
      ON ty.user_type_id = c.user_type_id
    WHERE c.object_id = OBJECT_ID(N'dbo.StatsGovernanceTelemetry')
    ORDER BY c.column_id;
END;

--------------------------------------------------------------------------------
-- 15. RESULT VIEW CONTRACT
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.v_DRE_StatsGovernanceResults_v1', N'V') IS NOT NULL
BEGIN
    SELECT
        c.column_id,
        c.name AS ColumnName,
        ty.name AS TypeName,
        c.max_length,
        c.precision,
        c.scale,
        c.is_nullable,
        c.collation_name
    FROM sys.columns AS c
    JOIN sys.types AS ty
      ON ty.user_type_id = c.user_type_id
    WHERE c.object_id = OBJECT_ID(N'dbo.v_DRE_StatsGovernanceResults_v1')
    ORDER BY c.column_id;
END;

--------------------------------------------------------------------------------
-- 16. RECENT GOVERNANCE RUNS - dynamic projection avoids assuming completion column name
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.StatsGovernanceRuns', N'U') IS NOT NULL
BEGIN
    DECLARE @RunSelect nvarchar(max) =
        N'SELECT TOP (20) * FROM dbo.StatsGovernanceRuns ORDER BY StartedAtUTC DESC;';

    EXEC sys.sp_executesql @RunSelect;
END;

--------------------------------------------------------------------------------
-- 17. RECENT TELEMETRY FOR THE PHASE 7 LAB OBJECT
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.StatsGovernanceTelemetry', N'U') IS NOT NULL
BEGIN
    SELECT TOP (100) *
    FROM dbo.StatsGovernanceTelemetry
    WHERE DatabaseName = @TargetDb COLLATE Latin1_General_100_BIN2
      AND SchemaName = @LabSchema COLLATE Latin1_General_100_BIN2
      AND TableName = @LabTable COLLATE Latin1_General_100_BIN2
    ORDER BY TelemetryID DESC;
END;

--------------------------------------------------------------------------------
-- 18. RESULT VIEW ROWS FOR THE PHASE 7 LAB OBJECT
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.v_DRE_StatsGovernanceResults_v1', N'V') IS NOT NULL
BEGIN
    SELECT TOP (100) *
    FROM dbo.v_DRE_StatsGovernanceResults_v1
    WHERE DatabaseName = @TargetDb COLLATE Latin1_General_100_BIN2
      AND SchemaName = @LabSchema COLLATE Latin1_General_100_BIN2
      AND TableName = @LabTable COLLATE Latin1_General_100_BIN2
    ORDER BY TelemetryID DESC;
END;

--------------------------------------------------------------------------------
-- 19. SCOPE AUDIT CONTRACT AND RECENT ROWS
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.StatsGovernanceScopeAudit', N'U') IS NOT NULL
BEGIN
    SELECT
        c.column_id,
        c.name AS ColumnName,
        ty.name AS TypeName,
        c.max_length,
        c.precision,
        c.scale,
        c.is_nullable,
        c.collation_name
    FROM sys.columns AS c
    JOIN sys.types AS ty
      ON ty.user_type_id = c.user_type_id
    WHERE c.object_id = OBJECT_ID(N'dbo.StatsGovernanceScopeAudit')
    ORDER BY c.column_id;

    SELECT TOP (50) *
    FROM dbo.StatsGovernanceScopeAudit
    ORDER BY ScopeAuditID DESC;
END;

--------------------------------------------------------------------------------
-- 20. COMMANDLOG EVIDENCE FOR THE LAB OBJECT
--------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.CommandLog', N'U') IS NOT NULL
BEGIN
    SELECT TOP (100)
        ID,
        DatabaseName,
        SchemaName,
        ObjectName,
        ObjectType,
        IndexName,
        IndexType,
        StatisticsName,
        PartitionNumber,
        ExtendedInfo,
        Command,
        CommandType,
        StartTime,
        EndTime,
        ErrorNumber,
        ErrorMessage
    FROM dbo.CommandLog
    WHERE DatabaseName = @TargetDb
      AND SchemaName = @LabSchema
      AND ObjectName = @LabTable
    ORDER BY ID DESC;
END;

--------------------------------------------------------------------------------
-- 21. LAB OBJECT EXISTENCE + SCHEMA
--------------------------------------------------------------------------------
IF DB_ID(@TargetDb) IS NOT NULL
BEGIN
    DECLARE @LabSql nvarchar(max) = N'
USE ' + QUOTENAME(@TargetDb) + N';

SELECT
    DB_NAME() AS DatabaseName,
    s.name AS SchemaName,
    t.name AS TableName,
    t.object_id,
    t.create_date,
    t.modify_date
FROM sys.tables AS t
JOIN sys.schemas AS s
  ON s.schema_id=t.schema_id
WHERE s.name=@LabSchema COLLATE DATABASE_DEFAULT
  AND t.name=@LabTable COLLATE DATABASE_DEFAULT;

SELECT
    c.column_id,
    c.name AS ColumnName,
    ty.name AS TypeName,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    c.collation_name,
    c.is_identity
FROM sys.columns AS c
JOIN sys.types AS ty
  ON ty.user_type_id=c.user_type_id
WHERE c.object_id=OBJECT_ID(QUOTENAME(@LabSchema)+N''.''+QUOTENAME(@LabTable))
ORDER BY c.column_id;

SELECT
    i.index_id,
    i.name AS IndexName,
    i.type_desc,
    i.is_unique,
    i.is_primary_key,
    ic.key_ordinal,
    ic.is_included_column,
    c.name AS ColumnName
FROM sys.indexes AS i
LEFT JOIN sys.index_columns AS ic
  ON ic.object_id=i.object_id
 AND ic.index_id=i.index_id
LEFT JOIN sys.columns AS c
  ON c.object_id=ic.object_id
 AND c.column_id=ic.column_id
WHERE i.object_id=OBJECT_ID(QUOTENAME(@LabSchema)+N''.''+QUOTENAME(@LabTable))
ORDER BY i.index_id, ic.key_ordinal, ic.index_column_id;

SELECT
    s.stats_id,
    s.name AS StatisticsName,
    s.auto_created,
    s.user_created,
    s.no_recompute,
    s.has_filter,
    s.filter_definition,
    sp.last_updated,
    sp.rows,
    sp.rows_sampled,
    sp.steps,
    sp.unfiltered_rows,
    sp.modification_counter,
    sp.persisted_sample_percent
FROM sys.stats AS s
OUTER APPLY sys.dm_db_stats_properties(s.object_id,s.stats_id) AS sp
WHERE s.object_id=OBJECT_ID(QUOTENAME(@LabSchema)+N''.''+QUOTENAME(@LabTable))
ORDER BY s.stats_id;

SELECT
    SUM(CASE WHEN index_id IN (0,1) THEN row_count ELSE 0 END) AS CurrentTableRows
FROM sys.dm_db_partition_stats
WHERE object_id=OBJECT_ID(QUOTENAME(@LabSchema)+N''.''+QUOTENAME(@LabTable));';

    EXEC sys.sp_executesql
        @LabSql,
        N'@LabSchema sysname,@LabTable sysname',
        @LabSchema=@LabSchema,
        @LabTable=@LabTable;
END;

--------------------------------------------------------------------------------
-- 22. DEFINITION TEXT FOR GOVERNANCE MODULES
--------------------------------------------------------------------------------
SELECT
    s.name AS SchemaName,
    o.name AS ObjectName,
    o.type_desc,
    m.definition
FROM sys.objects AS o
JOIN sys.schemas AS s
  ON s.schema_id=o.schema_id
JOIN sys.sql_modules AS m
  ON m.object_id=o.object_id
WHERE s.name=N'dbo'
  AND
  (
      o.name LIKE N'%StatsGovernance%'
      OR o.name LIKE N'%StatsScope%'
      OR o.name LIKE N'%StatsOverride%'
      OR o.name LIKE N'%StatsDatabaseScope%'
  )
ORDER BY o.type_desc,o.name;

SELECT
    N'READ_ONLY_LIVE_INVENTORY_COMPLETE' AS InventoryStatus,
    SYSDATETIMEOFFSET() AS CompletedAt;
