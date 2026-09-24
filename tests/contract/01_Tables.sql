/* Exact permanent-table column contract captured from the live 1.3.0 schema.
   Run read-only before an upgrade and after a new installation. */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @Expected TABLE
(
    TableName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
    ColumnID int NOT NULL,
    ColumnName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
    TypeName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
    MaxLength smallint NOT NULL,
    PrecisionValue tinyint NOT NULL,
    ScaleValue tinyint NOT NULL,
    IsNullable bit NOT NULL,
    CollationName sysname COLLATE Latin1_General_100_BIN2 NULL,
    PRIMARY KEY(TableName,ColumnID)
);
INSERT @Expected(TableName,ColumnID,ColumnName,TypeName,MaxLength,PrecisionValue,ScaleValue,IsNullable,CollationName)
VALUES
(N'StatsGovernanceOverrides',1,N'OverrideID',N'int',4,10,0,0,NULL),
(N'StatsGovernanceOverrides',2,N'DatabaseName',N'sysname',256,0,0,0,N'Latin1_General_100_BIN2'),
(N'StatsGovernanceOverrides',3,N'SchemaName',N'sysname',256,0,0,0,N'Latin1_General_100_BIN2'),
(N'StatsGovernanceOverrides',4,N'TableName',N'sysname',256,0,0,0,N'Latin1_General_100_BIN2'),
(N'StatsGovernanceOverrides',5,N'StatName',N'sysname',256,0,0,1,N'Latin1_General_100_BIN2'),
(N'StatsGovernanceOverrides',6,N'OverrideAction',N'varchar',24,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceOverrides',7,N'SamplePercent',N'decimal',5,9,4,1,NULL),
(N'StatsGovernanceOverrides',8,N'PersistenceMode',N'varchar',4,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceOverrides',9,N'ForceUpdate',N'bit',1,1,0,0,NULL),
(N'StatsGovernanceOverrides',10,N'IsEnabled',N'bit',1,1,0,0,NULL),
(N'StatsGovernanceOverrides',11,N'ApprovedBy',N'sysname',256,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceOverrides',12,N'ApprovedAtUTC',N'datetime2',8,27,7,0,NULL),
(N'StatsGovernanceOverrides',13,N'ExpiresAtUTC',N'datetime2',8,27,7,1,NULL),
(N'StatsGovernanceOverrides',14,N'Notes',N'nvarchar',4000,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceOverrides',15,N'Revision',N'timestamp',8,0,0,0,NULL),
(N'StatsGovernanceOverrides',16,N'SampleRows',N'bigint',8,19,0,1,NULL),
(N'StatsGovernanceRunDatabases',1,N'RunID',N'uniqueidentifier',16,0,0,0,NULL),
(N'StatsGovernanceRunDatabases',2,N'DatabaseName',N'sysname',256,0,0,0,N'Latin1_General_100_BIN2'),
(N'StatsGovernanceRunDatabases',3,N'CollectionStatus',N'varchar',32,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceRunDatabases',4,N'CandidateCount',N'int',4,10,0,0,NULL),
(N'StatsGovernanceRunDatabases',5,N'EnvironmentXml',N'xml',-1,0,0,1,NULL),
(N'StatsGovernanceRunDatabases',6,N'ErrorNumber',N'int',4,10,0,1,NULL),
(N'StatsGovernanceRunDatabases',7,N'ErrorMessage',N'nvarchar',8000,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceRunDatabases',8,N'DatabaseIDAtSelection',N'int',4,10,0,1,NULL),
(N'StatsGovernanceRunDatabases',9,N'DatabaseCreateDateAtSelection',N'datetime2',8,27,7,1,NULL),
(N'StatsGovernanceRunDatabases',10,N'SelectionStatus',N'varchar',24,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceRunDatabases',11,N'SelectionReason',N'varchar',80,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceRunDatabases',12,N'ScopeAtSelectionXml',N'xml',-1,0,0,1,NULL),
(N'StatsGovernanceRunDatabases',13,N'LastScopeStatus',N'varchar',40,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceRunDatabases',14,N'ScopeAtLastCheckXml',N'xml',-1,0,0,1,NULL),
(N'StatsGovernanceRunDatabases',15,N'LastScopeCheckAtUTC',N'datetime2',8,27,7,1,NULL),
(N'StatsGovernanceRuns',1,N'RunID',N'uniqueidentifier',16,0,0,0,NULL),
(N'StatsGovernanceRuns',2,N'EngineVersion',N'varchar',12,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceRuns',3,N'Mode',N'varchar',10,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceRuns',4,N'StartedAtUTC',N'datetime2',8,27,7,0,NULL),
(N'StatsGovernanceRuns',5,N'HeartbeatAtUTC',N'datetime2',8,27,7,0,NULL),
(N'StatsGovernanceRuns',6,N'FinishedAtUTC',N'datetime2',8,27,7,1,NULL),
(N'StatsGovernanceRuns',7,N'DeadlineUTC',N'datetime2',8,27,7,1,NULL),
(N'StatsGovernanceRuns',8,N'SessionID',N'int',4,10,0,0,NULL),
(N'StatsGovernanceRuns',9,N'OriginalLogin',N'sysname',256,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceRuns',10,N'ServerName',N'sysname',256,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceRuns',11,N'ProductVersion',N'nvarchar',256,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceRuns',12,N'RequestedMAXDOP',N'int',4,10,0,0,NULL),
(N'StatsGovernanceRuns',13,N'ParametersXml',N'xml',-1,0,0,0,NULL),
(N'StatsGovernanceRuns',14,N'TraceFlagsXml',N'xml',-1,0,0,1,NULL),
(N'StatsGovernanceRuns',15,N'RunStatus',N'varchar',32,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceRuns',16,N'ErrorNumber',N'int',4,10,0,1,NULL),
(N'StatsGovernanceRuns',17,N'ErrorMessage',N'nvarchar',8000,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceScope',1,N'DatabaseName',N'sysname',256,0,0,0,N'Latin1_General_100_BIN2'),
(N'StatsGovernanceScope',2,N'EnabledForEnforcement',N'bit',1,1,0,0,NULL),
(N'StatsGovernanceScope',3,N'ApprovedBy',N'sysname',256,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceScope',4,N'ApprovedAtUTC',N'datetime2',8,27,7,1,NULL),
(N'StatsGovernanceScope',5,N'Notes',N'nvarchar',4000,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceScope',6,N'IsExcluded',N'bit',1,1,0,0,NULL),
(N'StatsGovernanceScope',7,N'ExclusionReason',N'nvarchar',4000,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceScope',8,N'ExcludedBy',N'sysname',256,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceScope',9,N'ExcludedAtUTC',N'datetime2',8,27,7,1,NULL),
(N'StatsGovernanceScope',10,N'Revision',N'timestamp',8,0,0,0,NULL),
(N'StatsGovernanceScopeAudit',1,N'ScopeAuditID',N'bigint',8,19,0,0,NULL),
(N'StatsGovernanceScopeAudit',2,N'DatabaseName',N'sysname',256,0,0,0,N'Latin1_General_100_BIN2'),
(N'StatsGovernanceScopeAudit',3,N'ChangeType',N'varchar',6,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceScopeAudit',4,N'ChangedAtUTC',N'datetime2',8,27,7,0,NULL),
(N'StatsGovernanceScopeAudit',5,N'ChangedBy',N'sysname',256,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceScopeAudit',6,N'SessionID',N'int',4,10,0,0,NULL),
(N'StatsGovernanceScopeAudit',7,N'OldScopeXml',N'xml',-1,0,0,1,NULL),
(N'StatsGovernanceScopeAudit',8,N'NewScopeXml',N'xml',-1,0,0,1,NULL),
(N'StatsGovernanceSettings',1,N'SettingsID',N'tinyint',1,3,0,0,NULL),
(N'StatsGovernanceSettings',2,N'SchemaVersion',N'varchar',12,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceSettings',3,N'UpdateThresholdPercent',N'decimal',5,9,4,0,NULL),
(N'StatsGovernanceSettings',4,N'MinModificationCount',N'bigint',8,19,0,0,NULL),
(N'StatsGovernanceSettings',5,N'MinUpdateIntervalMinutes',N'int',4,10,0,0,NULL),
(N'StatsGovernanceSettings',6,N'LockTimeoutMilliseconds',N'int',4,10,0,0,NULL),
(N'StatsGovernanceSettings',7,N'SkewSamplingEnabled',N'bit',1,1,0,0,NULL),
(N'StatsGovernanceSettings',8,N'ModerateSkewThresholdPercent',N'decimal',5,9,4,0,NULL),
(N'StatsGovernanceSettings',9,N'HighSkewThresholdPercent',N'decimal',5,9,4,0,NULL),
(N'StatsGovernanceSettings',10,N'ExtremeSkewThresholdPercent',N'decimal',5,9,4,0,NULL),
(N'StatsGovernanceSettings',11,N'HighSkewSampleRows',N'bigint',8,19,0,0,NULL),
(N'StatsGovernanceSettings',12,N'ExtremeSkewSampleRows',N'bigint',8,19,0,0,NULL),
(N'StatsGovernanceTelemetry',1,N'TelemetryID',N'bigint',8,19,0,0,NULL),
(N'StatsGovernanceTelemetry',2,N'RunID',N'uniqueidentifier',16,0,0,0,NULL),
(N'StatsGovernanceTelemetry',3,N'DatabaseName',N'sysname',256,0,0,0,N'Latin1_General_100_BIN2'),
(N'StatsGovernanceTelemetry',4,N'SchemaName',N'sysname',256,0,0,0,N'Latin1_General_100_BIN2'),
(N'StatsGovernanceTelemetry',5,N'TableName',N'sysname',256,0,0,0,N'Latin1_General_100_BIN2'),
(N'StatsGovernanceTelemetry',6,N'StatName',N'sysname',256,0,0,0,N'Latin1_General_100_BIN2'),
(N'StatsGovernanceTelemetry',7,N'ObjectID',N'int',4,10,0,0,NULL),
(N'StatsGovernanceTelemetry',8,N'StatsID',N'int',4,10,0,0,NULL),
(N'StatsGovernanceTelemetry',9,N'OverrideID',N'int',4,10,0,1,NULL),
(N'StatsGovernanceTelemetry',10,N'InitialSnapshotXml',N'xml',-1,0,0,0,NULL),
(N'StatsGovernanceTelemetry',11,N'InitialOverrideXml',N'xml',-1,0,0,1,NULL),
(N'StatsGovernanceTelemetry',12,N'InitialDecisionXml',N'xml',-1,0,0,0,NULL),
(N'StatsGovernanceTelemetry',13,N'RevalidatedSnapshotXml',N'xml',-1,0,0,1,NULL),
(N'StatsGovernanceTelemetry',14,N'RevalidatedOverrideXml',N'xml',-1,0,0,1,NULL),
(N'StatsGovernanceTelemetry',15,N'RevalidatedDecisionXml',N'xml',-1,0,0,1,NULL),
(N'StatsGovernanceTelemetry',16,N'AfterSnapshotXml',N'xml',-1,0,0,1,NULL),
(N'StatsGovernanceTelemetry',17,N'RecommendedCommand',N'nvarchar',-1,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceTelemetry',18,N'ExecutedCommand',N'nvarchar',-1,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceTelemetry',19,N'CommandLogID',N'int',4,10,0,1,NULL),
(N'StatsGovernanceTelemetry',20,N'ExecutionStatus',N'varchar',40,0,0,0,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceTelemetry',21,N'ExecutionReason',N'varchar',80,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceTelemetry',22,N'CommandStartedAtUTC',N'datetime2',8,27,7,1,NULL),
(N'StatsGovernanceTelemetry',23,N'CommandEndedAtUTC',N'datetime2',8,27,7,1,NULL),
(N'StatsGovernanceTelemetry',24,N'CommandElapsedMilliseconds',N'bigint',8,19,0,1,NULL),
(N'StatsGovernanceTelemetry',25,N'ErrorNumber',N'int',4,10,0,1,NULL),
(N'StatsGovernanceTelemetry',26,N'ErrorMessage',N'nvarchar',8000,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceTelemetry',27,N'PostcheckStatus',N'varchar',40,0,0,1,N'SQL_Latin1_General_CP1_CI_AS'),
(N'StatsGovernanceTelemetry',28,N'PostcheckErrorNumber',N'int',4,10,0,1,NULL),
(N'StatsGovernanceTelemetry',29,N'PostcheckErrorMessage',N'nvarchar',8000,0,0,1,N'SQL_Latin1_General_CP1_CI_AS');

;WITH Actual AS
(
    SELECT t.name COLLATE Latin1_General_100_BIN2 AS TableName,
           c.column_id AS ColumnID,
           c.name COLLATE Latin1_General_100_BIN2 AS ColumnName,
           ty.name COLLATE Latin1_General_100_BIN2 AS TypeName,
           c.max_length AS MaxLength,c.precision AS PrecisionValue,
           c.scale AS ScaleValue,c.is_nullable AS IsNullable,
           c.collation_name COLLATE Latin1_General_100_BIN2 AS CollationName
    FROM sys.tables AS t
    JOIN sys.schemas AS s ON s.schema_id=t.schema_id
    JOIN sys.columns AS c ON c.object_id=t.object_id
    JOIN sys.types AS ty ON ty.user_type_id=c.user_type_id
    WHERE s.name=N'dbo' AND t.name LIKE N'StatsGovernance%'
), Diff AS
(
    SELECT * FROM @Expected EXCEPT SELECT * FROM Actual
    UNION ALL
    SELECT * FROM Actual EXCEPT SELECT * FROM @Expected
)
SELECT * FROM Diff ORDER BY TableName,ColumnID;

IF EXISTS
(
    SELECT * FROM @Expected
    EXCEPT
    SELECT t.name COLLATE Latin1_General_100_BIN2,c.column_id,
           c.name COLLATE Latin1_General_100_BIN2,ty.name COLLATE Latin1_General_100_BIN2,
           c.max_length,c.precision,c.scale,c.is_nullable,
           c.collation_name COLLATE Latin1_General_100_BIN2
    FROM sys.tables AS t
    JOIN sys.schemas AS s ON s.schema_id=t.schema_id
    JOIN sys.columns AS c ON c.object_id=t.object_id
    JOIN sys.types AS ty ON ty.user_type_id=c.user_type_id
    WHERE s.name=N'dbo' AND t.name LIKE N'StatsGovernance%'
)
    THROW 51210,'Governance table columns differ from the captured 1.3.0 contract.',1;

IF (SELECT COUNT(*) FROM sys.columns AS c JOIN sys.tables AS t ON t.object_id=c.object_id
    JOIN sys.schemas AS s ON s.schema_id=t.schema_id
    WHERE s.name=N'dbo' AND t.name LIKE N'StatsGovernance%')<>107
    THROW 51211,'Governance table column count differs from the captured contract.',1;

IF NOT EXISTS(SELECT 1 FROM dbo.StatsGovernanceSettings
              WHERE SettingsID=1 AND SchemaVersion='1.3.0')
    THROW 51212,'Governance settings schema version differs from 1.3.0.',1;

SELECT N'TABLE_CONTRACT_PASS' AS Status;
