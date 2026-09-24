/* Statistics Governance Engine integrated v1.3.2 installer. Run with sqlcmd -b -I
   while connected to the chosen utility database. The installer never changes
   database context and makes no SQL Server instance-level change. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
IF CONVERT(int,SERVERPROPERTY('EngineEdition')) NOT IN (2,3,4,8)
    THROW 51200,'Unsupported SQL Server engine edition.',1;
IF CONVERT(int,SERVERPROPERTY('EngineEdition'))<>8
   AND CONVERT(int,SERVERPROPERTY('ProductMajorVersion')) NOT IN (13,14,15,16,17)
    THROW 51201,'Supported boxed SQL Server versions are 2016 through 2025.',1;
IF (SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID())<110
    THROW 51202,'The utility database compatibility level must be 110 or higher.',1;
BEGIN TRANSACTION;
GO
/* Canonical v1.3.2 table bootstrap. Generated from the captured live 1.3.0 schema.
   Existing tables are never altered here; run contract checks before modules. */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.CommandLog') IS NOT NULL AND OBJECT_ID(N'dbo.CommandLog',N'U') IS NULL
    THROW 51203,'dbo.CommandLog exists but is not a user table.',1;
IF OBJECT_ID(N'dbo.CommandLog',N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CommandLog
    (
        ID int IDENTITY(1,1) NOT NULL,
        DatabaseName sysname NULL,
        SchemaName sysname NULL,
        ObjectName sysname NULL,
        ObjectType char(2) NULL,
        IndexName sysname NULL,
        IndexType tinyint NULL,
        StatisticsName sysname NULL,
        PartitionNumber int NULL,
        ExtendedInfo xml NULL,
        Command nvarchar(max) NOT NULL,
        CommandType nvarchar(60) NOT NULL,
        StartTime datetime2(7) NOT NULL,
        EndTime datetime2(7) NULL,
        ErrorNumber int NULL,
        ErrorMessage nvarchar(max) NULL,
        CONSTRAINT PK_CommandLog PRIMARY KEY CLUSTERED (ID)
    );
    PRINT 'Created dbo.CommandLog in ' + QUOTENAME(DB_NAME()) + '.';
END;

DECLARE @ExpectedCommandLog TABLE
(
    ColumnName sysname COLLATE Latin1_General_100_BIN2 NOT NULL PRIMARY KEY,
    TypeID tinyint NOT NULL,
    MaxLength smallint NOT NULL,
    IsNullable bit NOT NULL
);
INSERT @ExpectedCommandLog(ColumnName,TypeID,MaxLength,IsNullable)
VALUES
(N'ID',56,4,0),(N'DatabaseName',231,256,1),(N'SchemaName',231,256,1),
(N'ObjectName',231,256,1),(N'ObjectType',175,2,1),(N'IndexName',231,256,1),
(N'IndexType',48,1,1),(N'StatisticsName',231,256,1),(N'PartitionNumber',56,4,1),
(N'ExtendedInfo',241,-1,1),(N'Command',231,-1,0),(N'CommandType',231,120,0),
(N'StartTime',42,8,0),(N'EndTime',42,8,1),(N'ErrorNumber',56,4,1),
(N'ErrorMessage',231,-1,1);

IF EXISTS
(
    SELECT 1
    FROM @ExpectedCommandLog AS e
    LEFT JOIN sys.columns AS c
      ON c.object_id=OBJECT_ID(N'dbo.CommandLog',N'U')
     AND c.name COLLATE Latin1_General_100_BIN2=e.ColumnName
    WHERE c.column_id IS NULL
       OR c.system_type_id<>e.TypeID
       OR c.max_length<>e.MaxLength
       OR c.is_nullable<>e.IsNullable
)
OR COLUMNPROPERTY(OBJECT_ID(N'dbo.CommandLog',N'U'),N'ID','IsIdentity')<>1
OR NOT EXISTS
(
    SELECT 1
    FROM sys.indexes AS i
    JOIN sys.index_columns AS ic
      ON ic.object_id=i.object_id AND ic.index_id=i.index_id
    JOIN sys.columns AS c
      ON c.object_id=ic.object_id AND c.column_id=ic.column_id
    WHERE i.object_id=OBJECT_ID(N'dbo.CommandLog',N'U')
      AND i.is_primary_key=1
      AND i.type=1
      AND ic.key_ordinal=1
      AND c.name=N'ID'
      AND NOT EXISTS
          (SELECT 1 FROM sys.index_columns AS x
           WHERE x.object_id=i.object_id AND x.index_id=i.index_id AND x.key_ordinal>1)
)
    THROW 51204,'CommandLog does not match the expected Ola-compatible schema; existing tables are never altered automatically.',1;
GO
IF OBJECT_ID(N'dbo.StatsGovernanceOverrides', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[StatsGovernanceOverrides]
(
    [OverrideID] int IDENTITY(1,1) NOT NULL,
    [DatabaseName] sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
    [SchemaName] sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
    [TableName] sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
    [StatName] sysname COLLATE Latin1_General_100_BIN2 NULL,
    [OverrideAction] varchar(24) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [SamplePercent] decimal(9,4) NULL,
    [PersistenceMode] varchar(4) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL CONSTRAINT [DF_SGO_Persistence] DEFAULT ('KEEP'),
    [ForceUpdate] bit NOT NULL CONSTRAINT [DF_SGO_Force] DEFAULT ((0)),
    [IsEnabled] bit NOT NULL CONSTRAINT [DF_SGO_Enabled] DEFAULT ((1)),
    [ApprovedBy] sysname COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ApprovedAtUTC] datetime2(7) NOT NULL CONSTRAINT [DF_SGO_Approved] DEFAULT (sysutcdatetime()),
    [ExpiresAtUTC] datetime2(7) NULL,
    [Notes] nvarchar(2000) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [Revision] timestamp NOT NULL,
    [SampleRows] bigint NULL,
    CONSTRAINT [PK_StatsGovernanceOverrides] PRIMARY KEY CLUSTERED ([OverrideID]),
    CONSTRAINT [CK_SGO_Action] CHECK ([OverrideAction]='REFRESH_AUTO' OR [OverrideAction]='FORCE_SAMPLE_ROWS' OR [OverrideAction]='FORCE_SAMPLE_PERCENT' OR [OverrideAction]='FORCE_FULLSCAN' OR [OverrideAction]='EXCLUDE'),
    CONSTRAINT [CK_SGO_Approval] CHECK (len(ltrim(rtrim([ApprovedBy])))>(0) AND len(ltrim(rtrim([Notes])))>(0) AND ([ExpiresAtUTC] IS NULL OR [ExpiresAtUTC]>[ApprovedAtUTC])),
    CONSTRAINT [CK_SGO_ForceExpiry] CHECK ([ForceUpdate]=(0) OR [ExpiresAtUTC] IS NOT NULL AND [OverrideAction]<>'EXCLUDE'),
    CONSTRAINT [CK_SGO_Persist] CHECK (([PersistenceMode]='OFF' OR [PersistenceMode]='ON' OR [PersistenceMode]='KEEP') AND (NOT ([OverrideAction]='REFRESH_AUTO' OR [OverrideAction]='EXCLUDE') OR [PersistenceMode]='KEEP') AND ([OverrideAction]<>'FORCE_SAMPLE_ROWS' OR [PersistenceMode]<>'ON')),
    CONSTRAINT [CK_SGO_Sample] CHECK ([OverrideAction]='FORCE_SAMPLE_PERCENT' AND [SamplePercent] IS NOT NULL AND [SamplePercent]>(0) AND [SamplePercent]<=(100) AND [SampleRows] IS NULL OR [OverrideAction]='FORCE_SAMPLE_ROWS' AND [SampleRows] IS NOT NULL AND [SampleRows]>(0) AND [SamplePercent] IS NULL OR NOT ([OverrideAction]='FORCE_SAMPLE_ROWS' OR [OverrideAction]='FORCE_SAMPLE_PERCENT') AND [SamplePercent] IS NULL AND [SampleRows] IS NULL)
);
END;
GO
IF OBJECT_ID(N'dbo.StatsGovernanceRunDatabases', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[StatsGovernanceRunDatabases]
(
    [RunID] uniqueidentifier NOT NULL,
    [DatabaseName] sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
    [CollectionStatus] varchar(32) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [CandidateCount] int NOT NULL CONSTRAINT [DF_SGRD_Count] DEFAULT ((0)),
    [EnvironmentXml] xml NULL,
    [ErrorNumber] int NULL,
    [ErrorMessage] nvarchar(4000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [DatabaseIDAtSelection] int NULL,
    [DatabaseCreateDateAtSelection] datetime2(7) NULL,
    [SelectionStatus] varchar(24) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [SelectionReason] varchar(80) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [ScopeAtSelectionXml] xml NULL,
    [LastScopeStatus] varchar(40) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [ScopeAtLastCheckXml] xml NULL,
    [LastScopeCheckAtUTC] datetime2(7) NULL,
    CONSTRAINT [PK_StatsGovernanceRunDatabases] PRIMARY KEY CLUSTERED ([RunID], [DatabaseName])
);
END;
GO
IF OBJECT_ID(N'dbo.StatsGovernanceRuns', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[StatsGovernanceRuns]
(
    [RunID] uniqueidentifier NOT NULL,
    [EngineVersion] varchar(12) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [Mode] varchar(10) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [StartedAtUTC] datetime2(7) NOT NULL,
    [HeartbeatAtUTC] datetime2(7) NOT NULL,
    [FinishedAtUTC] datetime2(7) NULL,
    [DeadlineUTC] datetime2(7) NULL,
    [SessionID] int NOT NULL,
    [OriginalLogin] sysname COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ServerName] sysname COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [ProductVersion] nvarchar(128) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [RequestedMAXDOP] int NOT NULL,
    [ParametersXml] xml NOT NULL,
    [TraceFlagsXml] xml NULL,
    [RunStatus] varchar(32) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ErrorNumber] int NULL,
    [ErrorMessage] nvarchar(4000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    CONSTRAINT [PK_StatsGovernanceRuns] PRIMARY KEY CLUSTERED ([RunID])
);
END;
GO
IF OBJECT_ID(N'dbo.StatsGovernanceScope', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[StatsGovernanceScope]
(
    [DatabaseName] sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
    [EnabledForEnforcement] bit NOT NULL CONSTRAINT [DF_SGScope_Enabled] DEFAULT ((0)),
    [ApprovedBy] sysname COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [ApprovedAtUTC] datetime2(7) NULL,
    [Notes] nvarchar(2000) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [IsExcluded] bit NOT NULL CONSTRAINT [DF_SGScope_Excluded] DEFAULT ((0)),
    [ExclusionReason] nvarchar(2000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [ExcludedBy] sysname COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [ExcludedAtUTC] datetime2(7) NULL,
    [Revision] timestamp NOT NULL,
    CONSTRAINT [PK_StatsGovernanceScope] PRIMARY KEY CLUSTERED ([DatabaseName]),
    CONSTRAINT [CK_SGScope_Approval] CHECK (len(ltrim(rtrim([Notes])))>(0) AND ([EnabledForEnforcement]=(0) OR [ApprovedBy] IS NOT NULL AND len(ltrim(rtrim([ApprovedBy])))>(0) AND [ApprovedAtUTC] IS NOT NULL)),
    CONSTRAINT [CK_SGScope_Exclusion] CHECK ([IsExcluded]=(0) OR [EnabledForEnforcement]=(0) AND [ExclusionReason] IS NOT NULL AND len(ltrim(rtrim([ExclusionReason])))>(0) AND [ExcludedBy] IS NOT NULL AND len(ltrim(rtrim([ExcludedBy])))>(0) AND [ExcludedAtUTC] IS NOT NULL)
);
END;
GO
IF OBJECT_ID(N'dbo.StatsGovernanceScopeAudit', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[StatsGovernanceScopeAudit]
(
    [ScopeAuditID] bigint IDENTITY(1,1) NOT NULL,
    [DatabaseName] sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
    [ChangeType] varchar(6) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ChangedAtUTC] datetime2(7) NOT NULL,
    [ChangedBy] sysname COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [SessionID] int NOT NULL,
    [OldScopeXml] xml NULL,
    [NewScopeXml] xml NULL,
    CONSTRAINT [PK_StatsGovernanceScopeAudit] PRIMARY KEY CLUSTERED ([ScopeAuditID]),
    CONSTRAINT [CK_SGSA_ChangeType] CHECK ([ChangeType]='DELETE' OR [ChangeType]='UPDATE' OR [ChangeType]='INSERT')
);
END;
GO
IF OBJECT_ID(N'dbo.StatsGovernanceSettings', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[StatsGovernanceSettings]
(
    [SettingsID] tinyint NOT NULL,
    [SchemaVersion] varchar(12) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [UpdateThresholdPercent] decimal(9,4) NOT NULL,
    [MinModificationCount] bigint NOT NULL,
    [MinUpdateIntervalMinutes] int NOT NULL,
    [LockTimeoutMilliseconds] int NOT NULL,
    [SkewSamplingEnabled] bit NOT NULL CONSTRAINT [DF_SGS_SkewEnabled] DEFAULT ((0)),
    [ModerateSkewThresholdPercent] decimal(9,4) NOT NULL CONSTRAINT [DF_SGS_ModerateSkew] DEFAULT ((5.0)),
    [HighSkewThresholdPercent] decimal(9,4) NOT NULL CONSTRAINT [DF_SGS_HighSkew] DEFAULT ((10.0)),
    [ExtremeSkewThresholdPercent] decimal(9,4) NOT NULL CONSTRAINT [DF_SGS_ExtremeSkew] DEFAULT ((25.0)),
    [HighSkewSampleRows] bigint NOT NULL CONSTRAINT [DF_SGS_HighSkewRows] DEFAULT ((5000000)),
    [ExtremeSkewSampleRows] bigint NOT NULL CONSTRAINT [DF_SGS_ExtremeSkewRows] DEFAULT ((10000000)),
    CONSTRAINT [PK_StatsGovernanceSettings] PRIMARY KEY CLUSTERED ([SettingsID]),
    CONSTRAINT [CK_SGS_Singleton] CHECK ([SettingsID]=(1)),
    CONSTRAINT [CK_SGS_SkewPolicy] CHECK ([ModerateSkewThresholdPercent]>=(0) AND [ModerateSkewThresholdPercent]<[HighSkewThresholdPercent] AND [HighSkewThresholdPercent]<[ExtremeSkewThresholdPercent] AND [ExtremeSkewThresholdPercent]<=(100) AND [HighSkewSampleRows]>(0) AND [ExtremeSkewSampleRows]>=[HighSkewSampleRows]),
    CONSTRAINT [CK_SGS_Values] CHECK ([UpdateThresholdPercent]>(0) AND [MinModificationCount]>=(0) AND [MinUpdateIntervalMinutes]>=(0) AND ([LockTimeoutMilliseconds]>=(0) AND [LockTimeoutMilliseconds]<=(600000)))
);
END;
GO
IF OBJECT_ID(N'dbo.StatsGovernanceTelemetry', N'U') IS NULL
BEGIN
CREATE TABLE [dbo].[StatsGovernanceTelemetry]
(
    [TelemetryID] bigint IDENTITY(1,1) NOT NULL,
    [RunID] uniqueidentifier NOT NULL,
    [DatabaseName] sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
    [SchemaName] sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
    [TableName] sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
    [StatName] sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
    [ObjectID] int NOT NULL,
    [StatsID] int NOT NULL,
    [OverrideID] int NULL,
    [InitialSnapshotXml] xml NOT NULL,
    [InitialOverrideXml] xml NULL,
    [InitialDecisionXml] xml NOT NULL,
    [RevalidatedSnapshotXml] xml NULL,
    [RevalidatedOverrideXml] xml NULL,
    [RevalidatedDecisionXml] xml NULL,
    [AfterSnapshotXml] xml NULL,
    [RecommendedCommand] nvarchar(MAX) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [ExecutedCommand] nvarchar(MAX) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [CommandLogID] int NULL,
    [ExecutionStatus] varchar(40) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    [ExecutionReason] varchar(80) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [CommandStartedAtUTC] datetime2(7) NULL,
    [CommandEndedAtUTC] datetime2(7) NULL,
    [CommandElapsedMilliseconds] bigint NULL,
    [ErrorNumber] int NULL,
    [ErrorMessage] nvarchar(4000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [PostcheckStatus] varchar(40) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    [PostcheckErrorNumber] int NULL,
    [PostcheckErrorMessage] nvarchar(4000) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    CONSTRAINT [PK_StatsGovernanceTelemetry] PRIMARY KEY CLUSTERED ([TelemetryID])
);
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.StatsGovernanceOverrides') AND name=N'UX_SGO_Table')
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX [UX_SGO_Table] ON [dbo].[StatsGovernanceOverrides] ([DatabaseName], [SchemaName], [TableName]) WHERE [StatName] IS NULL;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.StatsGovernanceOverrides') AND name=N'UX_SGO_Stat')
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX [UX_SGO_Stat] ON [dbo].[StatsGovernanceOverrides] ([DatabaseName], [SchemaName], [TableName], [StatName]) WHERE [StatName] IS NOT NULL;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.StatsGovernanceScopeAudit') AND name=N'IX_SGSA_DatabaseDate')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_SGSA_DatabaseDate] ON [dbo].[StatsGovernanceScopeAudit] ([DatabaseName], [ScopeAuditID]);
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.StatsGovernanceTelemetry') AND name=N'IX_SGT_Run')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_SGT_Run] ON [dbo].[StatsGovernanceTelemetry] ([RunID], [TelemetryID]);
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.StatsGovernanceTelemetry') AND name=N'IX_SGT_Log')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_SGT_Log] ON [dbo].[StatsGovernanceTelemetry] ([CommandLogID]) WHERE [CommandLogID] IS NOT NULL;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.StatsGovernanceTelemetry') AND name=N'IX_SGT_RunStatus')
BEGIN
    CREATE NONCLUSTERED INDEX [IX_SGT_RunStatus] ON [dbo].[StatsGovernanceTelemetry] ([RunID], [ExecutionStatus], [TelemetryID]);
END;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.StatsGovernanceSettings WHERE SettingsID=1)
BEGIN
    INSERT dbo.StatsGovernanceSettings
        (SettingsID,SchemaVersion,UpdateThresholdPercent,MinModificationCount,MinUpdateIntervalMinutes,LockTimeoutMilliseconds)
    VALUES (1,'1.3.0',10.0,500,60,5000);
END;
GO

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

GO
-- dbo.ufn_DRE_StatsCapabilities_v1.sql
IF OBJECT_ID(N'dbo.ufn_DRE_StatsCapabilities_v1',N'TF') IS NULL EXEC(N'CREATE FUNCTION dbo.ufn_DRE_StatsCapabilities_v1() RETURNS @t TABLE(Placeholder int) AS BEGIN RETURN; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER FUNCTION dbo.ufn_DRE_StatsCapabilities_v1
(
    @ProductVersion nvarchar(128), @EngineEdition int
)
RETURNS @Capabilities TABLE
(
    ProductMajorVersion int NULL, ProductMinorVersion int NULL,
    ProductBuild int NULL, ProductRevision int NULL, EngineEdition int NULL,
    SupportedEngine bit NOT NULL, BuildRuleStatus varchar(64) NOT NULL,
    SupportsCreateOrAlter bit NULL, SupportsStatisticsMAXDOP bit NULL,
    SupportsPersistSamplePercent bit NULL,
    PreservesPersistedSampleAfterRebuild bit NULL,
    SupportsStatsHistogramDMF bit NULL,
    SupportsQueryStore bit NULL, SupportsQueryStoreWaitStats bit NULL,
    SupportsCEFeedback bit NULL
)
AS
BEGIN
    DECLARE @Major int=TRY_CONVERT(int,PARSENAME(@ProductVersion,4)),
            @Minor int=TRY_CONVERT(int,PARSENAME(@ProductVersion,3)),
            @Build int=TRY_CONVERT(int,PARSENAME(@ProductVersion,2)),
            @Revision int=TRY_CONVERT(int,PARSENAME(@ProductVersion,1)),
            @Supported bit=0, @Rule varchar(64)='UNRECOGNIZED_ENGINE_OR_VERSION',
            @CreateAlter bit, @Maxdop bit, @Persist bit, @Rebuild bit,
            @Histogram bit, @QS bit, @QSWait bit, @CE bit;

    IF @EngineEdition=8
    BEGIN
        SELECT @Supported=1,@Rule='MANAGED_INSTANCE_SERVICE_CAPABILITIES',
               @CreateAlter=1,@Maxdop=1,@Persist=1,@Rebuild=1,@Histogram=1,
               @QS=1,@QSWait=1,@CE=NULL;
    END
    ELSE IF @EngineEdition IN (2,3,4) AND @Major IN (13,14,15,16,17)
        AND @Minor=0 AND @Build IS NOT NULL AND @Revision IS NOT NULL
        AND @Build>=0 AND @Revision>=0
        AND LEN(@ProductVersion)-LEN(REPLACE(@ProductVersion,N'.',N''))=3
        AND ((@Major=13 AND @Build>=1601) OR (@Major=14 AND @Build>=1000)
          OR (@Major=15 AND @Build>=2000) OR (@Major IN (16,17) AND @Build>=1000))
    BEGIN
        SELECT @Supported=1,@Rule='DOCUMENTED_BUILD_RULES',@QS=1,
               @QSWait=CASE WHEN @Major>=14 THEN 1 ELSE 0 END,
               @CE=CASE WHEN @Major>=16 THEN 1 ELSE 0 END;
        IF @Major=13
            SELECT @CreateAlter=CASE WHEN @Build>=4001 THEN 1 ELSE 0 END,
                   @Maxdop=CASE WHEN @Build>=5026 THEN 1 ELSE 0 END,
                   @Persist=CASE WHEN @Build>=5026 OR (@Build>=4446 AND @Build<5000) THEN 1 ELSE 0 END,
                   @Rebuild=CASE WHEN @Build>=6300 OR
                       (@Build<6000 AND (@Build>5888 OR (@Build=5888 AND @Revision>=11)))
                       THEN 1 ELSE 0 END,
                   -- sys.dm_db_stats_histogram starts with SQL Server 2016 SP1 CU2 (13.0.4422.0).
                   -- Later SP branches have the feature. RTM/GDR branches below SP1 CU2 do not.
                   @Histogram=CASE WHEN @Build>=5000 OR @Build>=4422 THEN 1 ELSE 0 END;
        ELSE IF @Major=14
            SELECT @CreateAlter=1,
                   @Maxdop=CASE WHEN @Build>3015 OR (@Build=3015 AND @Revision>=40) THEN 1 ELSE 0 END,
                   @Persist=CASE WHEN @Build>3006 OR (@Build=3006 AND @Revision>=16) THEN 1 ELSE 0 END,
                   @Rebuild=CASE WHEN @Build>3411 OR (@Build=3411 AND @Revision>=3) THEN 1 ELSE 0 END,
                   @Histogram=1;
        ELSE IF @Major=15
            SELECT @CreateAlter=1,@Maxdop=1,@Persist=1,@Histogram=1,
                   @Rebuild=CASE WHEN @Build>4123 OR (@Build=4123 AND @Revision>=1) THEN 1 ELSE 0 END;
        ELSE SELECT @CreateAlter=1,@Maxdop=1,@Persist=1,@Rebuild=1,@Histogram=1;
    END;
    INSERT @Capabilities VALUES
        (@Major,@Minor,@Build,@Revision,@EngineEdition,@Supported,@Rule,
         @CreateAlter,@Maxdop,@Persist,@Rebuild,@Histogram,@QS,@QSWait,@CE);
    RETURN;
END;
GO
-- dbo.ufn_DRE_StatsCommand_v1.sql
IF OBJECT_ID(N'dbo.ufn_DRE_StatsCommand_v1',N'FN') IS NULL EXEC(N'CREATE FUNCTION dbo.ufn_DRE_StatsCommand_v1() RETURNS int AS BEGIN RETURN 0; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER FUNCTION dbo.ufn_DRE_StatsCommand_v1
(
    @DatabaseName sysname, @SchemaName sysname, @TableName sysname,
    @StatName sysname, @Method varchar(16), @SamplePercent decimal(19,6),
    @SampleRows bigint, @PersistOption bit, @MAXDOP int, @NoRecompute bit,
    @Capabilities xml
)
RETURNS nvarchar(max)
AS
BEGIN
    IF @DatabaseName IS NULL OR @SchemaName IS NULL OR @TableName IS NULL
       OR @StatName IS NULL OR @MAXDOP IS NULL OR @MAXDOP NOT BETWEEN 1 AND 64
       OR @Method IS NULL OR @Method NOT IN ('AUTO','SAMPLE_PERCENT','SAMPLE_ROWS','FULLSCAN')
        RETURN NULL;
    IF @Method='SAMPLE_PERCENT' AND (@SamplePercent IS NULL OR @SamplePercent<=0 OR @SamplePercent>100)
        RETURN NULL;
    IF @Method='SAMPLE_ROWS' AND (@SampleRows IS NULL OR @SampleRows<=0)
        RETURN NULL;
    IF @Method<>'SAMPLE_PERCENT' AND @SamplePercent IS NOT NULL AND @Method<>'FULLSCAN' RETURN NULL;
    IF @Method<>'SAMPLE_ROWS' AND @SampleRows IS NOT NULL RETURN NULL;

    DECLARE @CanMaxdop bit=CASE WHEN @Capabilities.exist('/Capabilities/SupportsStatisticsMAXDOP[1]')=1
        THEN @Capabilities.value('(/Capabilities/SupportsStatisticsMAXDOP/text())[1]','bit') END,
        @CanPersist bit=CASE WHEN @Capabilities.exist('/Capabilities/SupportsPersistSamplePercent[1]')=1
        THEN @Capabilities.value('(/Capabilities/SupportsPersistSamplePercent/text())[1]','bit') END,
        @HasMetadata bit=CASE WHEN @Capabilities.exist('/Capabilities/HasPersistedSamplePercentMetadata[1]')=1
        THEN @Capabilities.value('(/Capabilities/HasPersistedSamplePercentMetadata/text())[1]','bit') END;
    IF ISNULL(@CanMaxdop,0)<>1 RETURN NULL;
    IF @PersistOption IS NOT NULL
    BEGIN
        IF ISNULL(@CanPersist,0)<>1 OR ISNULL(@HasMetadata,0)<>1 RETURN NULL;
    END;
    IF @Method='AUTO' AND @PersistOption IS NOT NULL RETURN NULL;

    DECLARE @Command nvarchar(max)=N'USE '+QUOTENAME(@DatabaseName)
        +N'; UPDATE STATISTICS '+QUOTENAME(@SchemaName)+N'.'+QUOTENAME(@TableName)
        +N' ('+QUOTENAME(@StatName)+N') WITH ';
    IF @Method='FULLSCAN' SET @Command+=N'FULLSCAN, ';
    IF @Method='SAMPLE_PERCENT'
        SET @Command+=N'SAMPLE '+CONVERT(nvarchar(32),@SamplePercent)+N' PERCENT, ';
    IF @Method='SAMPLE_ROWS'
        SET @Command+=N'SAMPLE '+CONVERT(nvarchar(32),@SampleRows)+N' ROWS, ';
    IF @PersistOption IS NOT NULL
        SET @Command+=N'PERSIST_SAMPLE_PERCENT = '+CASE WHEN @PersistOption=1 THEN N'ON' ELSE N'OFF' END+N', ';
    SET @Command+=N'MAXDOP = '+CONVERT(nvarchar(10),@MAXDOP);
    IF @NoRecompute=1 SET @Command+=N', NORECOMPUTE';
    RETURN @Command+N';';
END;
GO
-- dbo.ufn_DRE_StatsDecision_v1.sql
IF OBJECT_ID(N'dbo.ufn_DRE_StatsDecision_v1',N'TF') IS NULL EXEC(N'CREATE FUNCTION dbo.ufn_DRE_StatsDecision_v1() RETURNS @t TABLE(Placeholder int) AS BEGIN RETURN; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER FUNCTION dbo.ufn_DRE_StatsDecision_v1
(
    @Facts xml,
    @Policy xml,
    @Override xml
)
RETURNS @Decision TABLE
(
    IsEligible bit NOT NULL,
    Reason varchar(80) NOT NULL,
    CollectionMethod varchar(16) NULL,
    RequestedSamplePercent decimal(19,6) NULL,
    RequestedSampleRows bigint NULL,
    SamplingSource varchar(48) NULL,
    PersistOption bit NULL,
    ModRatioPercent decimal(28,6) NULL,
    ActualSamplePercent decimal(19,6) NULL,
    LowSampleWarning bit NOT NULL,
    EffectiveLowSampleThresholdPercent decimal(19,6) NULL,
    HistogramDominantEqualityPercent decimal(19,6) NULL,
    HistogramTop3EqualityPercent decimal(19,6) NULL,
    SkewClassification varchar(12) NOT NULL,
    FullscanEligible bit NOT NULL,
    FullscanReason varchar(80) NULL,
    CanExecute bit NOT NULL,
    CapabilityReason varchar(80) NULL,
    PersistenceAdvisory varchar(80) NULL,
    GovernanceThresholdBasisRows bigint NULL,
    GovernanceEffectiveModificationThreshold bigint NULL,
    GovernanceModificationsRemaining bigint NULL,
    GovernanceThresholdProgressPercent decimal(19,6) NULL,
    GovernanceThresholdReached bit NULL,
    GovernanceVsNativeThresholdDeltaModifications bigint NULL,
    GovernanceVsNativeThresholdComparison varchar(32) NULL
)
AS
BEGIN
    /*
    FULLSCAN GOVERNANCE POLICY
    --------------------------
    Microsoft guidance states that default sampling is adequate for most workloads;
    workloads sensitive to widely varying distributions can require a larger sample
    or even a full scan, but more accurate estimates from FULLSCAN do not guarantee
    material improvement for complex plans.

    Microsoft reference:
    https://learn.microsoft.com/en-us/sql/t-sql/statements/update-statistics-transact-sql?view=sql-server-ver17

    Statistics Governance Engine policy:
      HIGH/EXTREME SKEW != AUTOMATIC FULLSCAN.

    Skew influences HOW an already-eligible statistic is sampled. Skew does not
    independently make a statistic eligible and does not authorize FULLSCAN.
    In v1.3.2 FULLSCAN is authorized only by an approved FORCE_FULLSCAN override.
    Evidence-based automatic FULLSCAN escalation is reserved for a separately
    validated future implementation.

    Units: sample-row values = rows; sample/skew values = percent.
    */
    DECLARE @Rows bigint = CASE WHEN @Facts.exist('/Statistic/StatsRows[1]')=1 THEN @Facts.value('(/Statistic/StatsRows/text())[1]','bigint') END;
    DECLARE @CurrentRows bigint = CASE WHEN @Facts.exist('/Statistic/CurrentTableRows[1]')=1 THEN @Facts.value('(/Statistic/CurrentTableRows/text())[1]','bigint') END;
    DECLARE @RowsForPolicy bigint = COALESCE(@Rows,@CurrentRows);
    DECLARE @SampleRowsObserved bigint = CASE WHEN @Facts.exist('/Statistic/RowsSampled[1]')=1 THEN @Facts.value('(/Statistic/RowsSampled/text())[1]','bigint') END;
    DECLARE @Mods bigint = CASE WHEN @Facts.exist('/Statistic/ModificationCounter[1]')=1 THEN @Facts.value('(/Statistic/ModificationCounter/text())[1]','bigint') END;
    DECLARE @Age bigint = CASE WHEN @Facts.exist('/Statistic/StatsAgeMinutes[1]')=1 THEN @Facts.value('(/Statistic/StatsAgeMinutes/text())[1]','bigint') END;
    DECLARE @Persisted decimal(19,6) = CASE WHEN @Facts.exist('/Statistic/PersistedSamplePercent[1]')=1 THEN @Facts.value('(/Statistic/PersistedSamplePercent/text())[1]','decimal(19,6)') END;
    DECLARE @IndexType int = CASE WHEN @Facts.exist('/Statistic/IndexType[1]')=1 THEN @Facts.value('(/Statistic/IndexType/text())[1]','int') END;
    DECLARE @IndexFamily varchar(20) = CASE WHEN @Facts.exist('/Statistic/IndexFamily[1]')=1 THEN @Facts.value('(/Statistic/IndexFamily/text())[1]','varchar(20)') END;
    DECLARE @Action varchar(24) = CASE WHEN @Override.exist('/Override/OverrideAction[1]')=1 THEN @Override.value('(/Override/OverrideAction/text())[1]','varchar(24)') END;
    DECLARE @OverrideSamplePercent decimal(19,6) = CASE WHEN @Override.exist('/Override/SamplePercent[1]')=1 THEN @Override.value('(/Override/SamplePercent/text())[1]','decimal(19,6)') END;
    DECLARE @OverrideSampleRows bigint = CASE WHEN @Override.exist('/Override/SampleRows[1]')=1 THEN @Override.value('(/Override/SampleRows/text())[1]','bigint') END;
    DECLARE @Force bit = ISNULL(CASE WHEN @Override.exist('/Override/ForceUpdate[1]')=1 THEN @Override.value('(/Override/ForceUpdate/text())[1]','bit') END,0);
    DECLARE @PersistMode varchar(4) = ISNULL(CASE WHEN @Override.exist('/Override/PersistenceMode[1]')=1 THEN @Override.value('(/Override/PersistenceMode/text())[1]','varchar(4)') END,'KEEP');

    DECLARE @Floor bigint = @Policy.value('(/Policy/MinRowCountFloor/text())[1]','bigint');
    DECLARE @Threshold decimal(9,4) = @Policy.value('(/Policy/UpdateThresholdPercent/text())[1]','decimal(9,4)');
    DECLARE @MinMods bigint = @Policy.value('(/Policy/MinModificationCount/text())[1]','bigint');
    DECLARE @Cooldown int = @Policy.value('(/Policy/MinUpdateIntervalMinutes/text())[1]','int');
    DECLARE @Large bigint = @Policy.value('(/Policy/LargeTableThresholdBase/text())[1]','bigint');
    DECLARE @DefaultSample decimal(9,4) = CASE WHEN @Policy.exist('/Policy/DefaultSamplePercentBase[1]')=1 THEN @Policy.value('(/Policy/DefaultSamplePercentBase/text())[1]','decimal(9,4)') END;
    DECLARE @Low decimal(19,6) = @Policy.value('(/Policy/LowSampleThresholdBase/text())[1]','decimal(19,6)');
    DECLARE @LegacyMultiplier decimal(9,4) = @Policy.value('(/Policy/LegacyCEMultiplier/text())[1]','decimal(9,4)');
    DECLARE @SkewEnabled bit = ISNULL(CASE WHEN @Policy.exist('/Policy/SkewSamplingEnabled[1]')=1 THEN @Policy.value('(/Policy/SkewSamplingEnabled/text())[1]','bit') END,0);
    DECLARE @ModerateSkew decimal(19,6) = ISNULL(CASE WHEN @Policy.exist('/Policy/ModerateSkewThresholdPercent[1]')=1 THEN @Policy.value('(/Policy/ModerateSkewThresholdPercent/text())[1]','decimal(19,6)') END,5.0);
    DECLARE @HighSkew decimal(19,6) = ISNULL(CASE WHEN @Policy.exist('/Policy/HighSkewThresholdPercent[1]')=1 THEN @Policy.value('(/Policy/HighSkewThresholdPercent/text())[1]','decimal(19,6)') END,10.0);
    DECLARE @ExtremeSkew decimal(19,6) = ISNULL(CASE WHEN @Policy.exist('/Policy/ExtremeSkewThresholdPercent[1]')=1 THEN @Policy.value('(/Policy/ExtremeSkewThresholdPercent/text())[1]','decimal(19,6)') END,25.0);
    DECLARE @HighSkewRows bigint = ISNULL(CASE WHEN @Policy.exist('/Policy/HighSkewSampleRows[1]')=1 THEN @Policy.value('(/Policy/HighSkewSampleRows/text())[1]','bigint') END,5000000);
    DECLARE @ExtremeSkewRows bigint = ISNULL(CASE WHEN @Policy.exist('/Policy/ExtremeSkewSampleRows[1]')=1 THEN @Policy.value('(/Policy/ExtremeSkewSampleRows/text())[1]','bigint') END,10000000);

    DECLARE @HistogramStatus varchar(40) = CASE WHEN @Facts.exist('/Statistic/HistogramAnalysisStatus[1]')=1 THEN @Facts.value('(/Statistic/HistogramAnalysisStatus/text())[1]','varchar(40)') END;
    DECLARE @DominantPct decimal(19,6) = CASE WHEN @Facts.exist('/Statistic/HistogramDominantEqualityPercent[1]')=1 THEN @Facts.value('(/Statistic/HistogramDominantEqualityPercent/text())[1]','decimal(19,6)') END;
    DECLARE @Top3Pct decimal(19,6) = CASE WHEN @Facts.exist('/Statistic/HistogramTop3EqualityPercent[1]')=1 THEN @Facts.value('(/Statistic/HistogramTop3EqualityPercent/text())[1]','decimal(19,6)') END;
    DECLARE @Skew varchar(12)='UNKNOWN';
    IF @HistogramStatus='AVAILABLE' AND @DominantPct IS NOT NULL
        SET @Skew=CASE WHEN @DominantPct>=@ExtremeSkew THEN 'EXTREME'
                       WHEN @DominantPct>=@HighSkew THEN 'HIGH'
                       WHEN @DominantPct>=@ModerateSkew THEN 'MODERATE'
                       ELSE 'LOW' END;

    DECLARE @MaxdopSupported bit = CASE WHEN @Facts.exist('/Statistic/SupportsStatisticsMAXDOP[1]')=1 THEN @Facts.value('(/Statistic/SupportsStatisticsMAXDOP/text())[1]','bit') END;
    DECLARE @PersistenceSupported bit = CASE WHEN @Facts.exist('/Statistic/SupportsPersistSamplePercent[1]')=1 THEN @Facts.value('(/Statistic/SupportsPersistSamplePercent/text())[1]','bit') END;
    DECLARE @HasPersistedMetadata bit = CASE WHEN @Facts.exist('/Statistic/HasPersistedSamplePercentMetadata[1]')=1 THEN @Facts.value('(/Statistic/HasPersistedSamplePercentMetadata/text())[1]','bit') END;
    DECLARE @RebuildKeepsRate bit = CASE WHEN @Facts.exist('/Statistic/PreservesPersistedSampleAfterRebuild[1]')=1 THEN @Facts.value('(/Statistic/PreservesPersistedSampleAfterRebuild/text())[1]','bit') END;

    DECLARE @CanExecute bit=0,@CapabilityReason varchar(80)=NULL,@PersistenceAdvisory varchar(80)=NULL;
    DECLARE @Method varchar(16)='AUTO',@RequestedPercent decimal(19,6)=NULL,@RequestedRows bigint=NULL,@Persist bit=NULL;
    DECLARE @Reason varchar(80),@Eligible bit=0,@SamplingSource varchar(48)='SQL_DEFAULT';
    DECLARE @ModRatio decimal(28,6),@ActualSample decimal(19,6),@LowWarning bit=0;
    DECLARE @FullscanEligible bit=0,@FullscanReason varchar(80)=NULL;
    DECLARE @NativeThreshold bigint=CASE WHEN @Facts.exist('/Statistic/EstimatedAutoUpdateThresholdModifications[1]')=1
        THEN @Facts.value('(/Statistic/EstimatedAutoUpdateThresholdModifications/text())[1]','bigint') END;
    DECLARE @GovernanceThreshold bigint=NULL,@GovernanceRemaining bigint=NULL,@GovernanceReached bit=NULL,
            @GovernanceProgress decimal(19,6)=NULL,@GovernanceDelta bigint=NULL,@GovernanceComparison varchar(32)=NULL,@GovernancePctThreshold bigint=NULL;
    IF @Rows IS NOT NULL
    BEGIN
        IF @Rows=0 SET @GovernanceThreshold=CASE WHEN @MinMods<1 THEN 1 ELSE @MinMods END;
        ELSE
        BEGIN
            SET @GovernancePctThreshold=TRY_CONVERT(bigint,CEILING(CONVERT(decimal(38,6),@Rows)*CONVERT(decimal(38,6),@Threshold)/100.0));
            IF @GovernancePctThreshold IS NOT NULL
                SET @GovernanceThreshold=CASE WHEN @GovernancePctThreshold>@MinMods THEN @GovernancePctThreshold ELSE @MinMods END;
        END;
    END;
    IF @GovernanceThreshold IS NOT NULL AND @Mods IS NOT NULL
    BEGIN
        SET @GovernanceRemaining=CASE WHEN @Mods>=@GovernanceThreshold THEN 0 ELSE @GovernanceThreshold-@Mods END;
        SET @GovernanceProgress=CASE WHEN @GovernanceThreshold=0 THEN NULL
            ELSE CONVERT(decimal(19,6),CONVERT(decimal(38,6),@Mods)*100.0/CONVERT(decimal(38,6),@GovernanceThreshold)) END;
        SET @GovernanceReached=CASE WHEN @Mods>=@GovernanceThreshold THEN 1 ELSE 0 END;
    END;
    IF @GovernanceThreshold IS NOT NULL AND @NativeThreshold IS NOT NULL
    BEGIN
        SET @GovernanceDelta=TRY_CONVERT(bigint,CONVERT(decimal(38,0),@GovernanceThreshold)-CONVERT(decimal(38,0),@NativeThreshold));
        SET @GovernanceComparison=CASE WHEN @GovernanceThreshold<@NativeThreshold THEN 'GOVERNANCE_EARLIER'
                                       WHEN @GovernanceThreshold>@NativeThreshold THEN 'GOVERNANCE_LATER'
                                       ELSE 'SAME_THRESHOLD' END;
    END;

    IF @Facts.value('(/Statistic/LegacyCEContext/text())[1]','bit')=1 SET @Low=@Low*@LegacyMultiplier;
    IF @Low>100 SET @Low=100;
    IF @Rows>0
    BEGIN
        SET @ModRatio=CONVERT(decimal(28,6),CONVERT(decimal(28,6),@Mods)/NULLIF(@Rows,0)*100.0);
        SET @ActualSample=CONVERT(decimal(19,6),CONVERT(decimal(28,6),@SampleRowsObserved)/NULLIF(@Rows,0)*100.0);
    END;
    IF @ActualSample<@Low SET @LowWarning=1;

    -- Safety restrictions precede manual overrides. Non-rowstore associated
    -- statistics remain visible in INDEX_ONLY reports but are deferred explicitly.
    IF ISNULL(@Facts.value('(/Statistic/WritablePrimary/text())[1]','bit'),0)<>1
        SET @Reason='DATABASE_NOT_WRITABLE_PRIMARY';
    ELSE IF @Facts.value('(/Statistic/IsMemoryOptimized/text())[1]','bit')=1
        SET @Reason='MEMORY_OPTIMIZED_MANUAL_REVIEW_V1';
    ELSE IF @Facts.value('(/Statistic/IsTemporary/text())[1]','bit')=1
        SET @Reason='TEMPORARY_STATISTIC_NOT_SUPPORTED';
    ELSE IF @Facts.value('(/Statistic/BaseIndexDisabled/text())[1]','bit')=1
         OR @Facts.value('(/Statistic/IndexDisabled/text())[1]','bit')=1
         OR @Facts.value('(/Statistic/IndexHypothetical/text())[1]','bit')=1
        SET @Reason='DISABLED_OR_HYPOTHETICAL_INDEX';
    ELSE IF @IndexType IN (5,6) SET @Reason='COLUMNSTORE_INDEX_STATISTIC_DEFERRED';
    ELSE IF @IndexType=3 SET @Reason='XML_INDEX_STATISTIC_DEFERRED';
    ELSE IF @IndexType=4 SET @Reason='SPATIAL_INDEX_STATISTIC_DEFERRED';
    ELSE IF @IndexType=7 SET @Reason='HASH_INDEX_STATISTIC_DEFERRED';
    ELSE IF @IndexType=9 SET @Reason='JSON_INDEX_STATISTIC_DEFERRED';
    ELSE IF @IndexType IS NOT NULL AND @IndexType NOT IN (1,2)
        SET @Reason='UNKNOWN_INDEX_FAMILY_DEFERRED';
    ELSE IF @Facts.value('(/Statistic/IsIncremental/text())[1]','bit')=1
        SET @Reason='INCREMENTAL_PARTITION_EXECUTOR_DEFERRED_V1';
    ELSE IF @Action='EXCLUDE'
        SET @Reason='EXPLICIT_EXCLUSION';
    ELSE IF ISNULL(@Facts.value('(/Statistic/StatsPropertiesAvailable/text())[1]','bit'),0)<>1
        SET @Reason='STATISTICS_PROPERTIES_UNAVAILABLE';
    ELSE IF @CurrentRows IS NULL SET @Reason='CURRENT_ROWCOUNT_UNAVAILABLE';
    ELSE IF @CurrentRows=0 SET @Reason='EMPTY_TABLE';
    ELSE IF @CurrentRows<@Floor AND @Action IS NULL SET @Reason='BELOW_ROWCOUNT_FLOOR';
    ELSE IF @Age IS NOT NULL AND @Age<@Cooldown SET @Reason='UPDATE_COOLDOWN';
    ELSE IF @Force=1 BEGIN SET @Eligible=1; SET @Reason='APPROVED_FORCE_REFRESH'; END
    ELSE IF @Facts.exist('/Statistic/LastUpdatedLocal[1]')=0 AND @Facts.value('(/Statistic/HasFilter/text())[1]','bit')=1
        SET @Reason='FILTERED_EMPTY_OR_UNINITIALIZED_REVIEW';
    ELSE IF @Facts.exist('/Statistic/LastUpdatedLocal[1]')=0 BEGIN SET @Eligible=1; SET @Reason='MISSING_STATISTICS_BLOB'; END
    ELSE IF @Mods IS NULL SET @Reason='MODIFICATION_COUNTER_UNAVAILABLE';
    ELSE IF @Mods<@MinMods OR @Mods=0 SET @Reason='BELOW_MIN_MODIFICATIONS';
    ELSE IF @Rows=0 BEGIN SET @Eligible=1; SET @Reason='ZERO_BASELINE_WITH_MODIFICATIONS'; END
    ELSE IF @ModRatio>=@Threshold BEGIN SET @Eligible=1; SET @Reason='MODIFICATION_THRESHOLD'; END
    ELSE SET @Reason='BELOW_MODIFICATION_THRESHOLD';

    IF @Eligible=1
    BEGIN
        IF @Action='FORCE_FULLSCAN'
        BEGIN
            SET @Method='FULLSCAN'; SET @RequestedPercent=100.0; SET @SamplingSource='APPROVED_OVERRIDE';
            SET @FullscanEligible=1; SET @FullscanReason='APPROVED_FORCE_FULLSCAN_OVERRIDE';
        END
        ELSE IF @Action='FORCE_SAMPLE_PERCENT'
        BEGIN
            SET @Method='SAMPLE_PERCENT'; SET @RequestedPercent=@OverrideSamplePercent; SET @SamplingSource='APPROVED_OVERRIDE';
        END
        ELSE IF @Action='FORCE_SAMPLE_ROWS'
        BEGIN
            IF @OverrideSampleRows IS NULL OR @OverrideSampleRows<=0
            BEGIN SET @Eligible=0; SET @Reason='INVALID_SAMPLE_ROWS_OVERRIDE'; END
            ELSE IF @PersistMode='ON'
            BEGIN SET @Eligible=0; SET @Reason='SAMPLE_ROWS_CANNOT_PERSIST_ROW_COUNT'; END
            ELSE IF ISNULL(@Persisted,0)>0 AND @PersistMode='KEEP'
            BEGIN SET @Eligible=0; SET @Reason='ROW_SAMPLE_CONFLICTS_WITH_PERSISTED_PERCENT'; END
            ELSE
            BEGIN
                SET @Method='SAMPLE_ROWS';
                SET @RequestedRows=CASE WHEN @CurrentRows IS NOT NULL AND @OverrideSampleRows>@CurrentRows THEN @CurrentRows ELSE @OverrideSampleRows END;
                SET @SamplingSource=CASE WHEN @CurrentRows IS NOT NULL AND @OverrideSampleRows>@CurrentRows THEN 'APPROVED_OVERRIDE_CAPPED_TO_ROWS' ELSE 'APPROVED_OVERRIDE' END;
                IF @PersistMode='OFF' SET @Persist=0;
            END;
        END
        ELSE IF ISNULL(@Persisted,0)>0 AND @PersistenceSupported=1 AND @HasPersistedMetadata=1
        BEGIN
            SET @Method='SAMPLE_PERCENT'; SET @RequestedPercent=@Persisted;
            SET @PersistMode='ON'; SET @Persist=1; SET @SamplingSource='EXISTING_PERSISTED_RATE';
        END
        ELSE IF @SkewEnabled=1 AND @RowsForPolicy>=@Large AND @Skew IN ('HIGH','EXTREME')
        BEGIN
            -- Skew can raise the sampling budget, but never promotes to FULLSCAN.
            SET @Method='SAMPLE_ROWS';
            SET @RequestedRows=CASE WHEN @Skew='EXTREME' THEN @ExtremeSkewRows ELSE @HighSkewRows END;
            IF @CurrentRows IS NOT NULL AND @RequestedRows>@CurrentRows SET @RequestedRows=@CurrentRows;
            SET @SamplingSource=CASE WHEN @Skew='EXTREME' THEN 'EXTREME_SKEW_SAMPLE_ROWS' ELSE 'HIGH_SKEW_SAMPLE_ROWS' END;
        END
        ELSE IF @Action IS NULL AND @DefaultSample IS NOT NULL AND @RowsForPolicy>=@Large
        BEGIN
            SET @Method='SAMPLE_PERCENT'; SET @RequestedPercent=@DefaultSample; SET @SamplingSource='REQUESTED_LARGE_TABLE_SAMPLE';
        END;

        IF @Eligible=1 AND @Method IN ('FULLSCAN','SAMPLE_PERCENT') AND @Persist IS NULL
        BEGIN
            IF @PersistMode='ON' SET @Persist=1;
            ELSE IF @PersistMode='OFF' SET @Persist=0;
            ELSE IF ISNULL(@Persisted,0)=0 AND @PersistenceSupported=1 SET @Persist=0;
            ELSE IF @PersistenceSupported=0 SET @Persist=NULL;
            ELSE IF @RequestedPercent IS NOT NULL AND ABS(@Persisted-@RequestedPercent)<=0.0001 SET @Persist=1;
            ELSE BEGIN SET @Eligible=0; SET @Reason='PERSISTENCE_CONFLICT_REQUIRES_EXPLICIT_CHOICE'; END;
        END;
    END;

    -- Capability checks are only execution gates; they do not alter policy eligibility.
    IF @Eligible=1
    BEGIN
        IF @MaxdopSupported IS NULL SET @CapabilityReason='STATISTICS_MAXDOP_CAPABILITY_UNKNOWN';
        ELSE IF @MaxdopSupported=0 SET @CapabilityReason='STATISTICS_MAXDOP_NOT_SUPPORTED_ON_THIS_BUILD';
        ELSE IF @Persist IS NOT NULL AND @PersistenceSupported IS NULL SET @CapabilityReason='PERSIST_SAMPLE_CAPABILITY_UNKNOWN';
        ELSE IF @Persist IS NOT NULL AND @PersistenceSupported=0 SET @CapabilityReason='PERSIST_SAMPLE_OPTION_NOT_SUPPORTED_ON_THIS_BUILD';
        ELSE IF @Persist IS NOT NULL AND @PersistenceSupported=1 AND ISNULL(@HasPersistedMetadata,0)<>1 SET @CapabilityReason='PERSISTED_SAMPLE_METADATA_UNAVAILABLE';
        ELSE IF @Method='SAMPLE_PERCENT' AND @SamplingSource='EXISTING_PERSISTED_RATE' AND (ISNULL(@PersistenceSupported,0)<>1 OR ISNULL(@HasPersistedMetadata,0)<>1)
            SET @CapabilityReason='EXISTING_PERSISTED_RATE_CANNOT_BE_VALIDATED';
    END;
    SET @CanExecute=CASE WHEN @Eligible=1 AND @CapabilityReason IS NULL THEN 1 ELSE 0 END;

    IF @PersistenceSupported=1 AND @RebuildKeepsRate=0 SET @PersistenceAdvisory='INDEX_REBUILD_CAN_RESET_PERSISTED_SAMPLE';
    ELSE IF @PersistenceSupported=1 AND @RebuildKeepsRate IS NULL SET @PersistenceAdvisory='REBUILD_PERSISTENCE_BEHAVIOR_UNKNOWN';
    ELSE IF @PersistenceSupported=0 SET @PersistenceAdvisory='PERSISTED_SAMPLING_NOT_SUPPORTED_ON_THIS_BUILD';

    INSERT @Decision
    VALUES(@Eligible,@Reason,CASE WHEN @Eligible=1 THEN @Method END,
           CASE WHEN @Eligible=1 THEN @RequestedPercent END,
           CASE WHEN @Eligible=1 THEN @RequestedRows END,
           CASE WHEN @Eligible=1 THEN @SamplingSource END,
           CASE WHEN @Eligible=1 THEN @Persist END,
           @ModRatio,@ActualSample,@LowWarning,@Low,@DominantPct,@Top3Pct,@Skew,
           @FullscanEligible,@FullscanReason,@CanExecute,@CapabilityReason,@PersistenceAdvisory,
           @Rows,@GovernanceThreshold,@GovernanceRemaining,@GovernanceProgress,@GovernanceReached,@GovernanceDelta,@GovernanceComparison);
    RETURN;
END;
GO
-- dbo.usp_DRE_StatsCapabilities_v1.sql
IF OBJECT_ID(N'dbo.usp_DRE_StatsCapabilities_v1',N'P') IS NULL EXEC(N'CREATE PROCEDURE dbo.usp_DRE_StatsCapabilities_v1 AS BEGIN SET NOCOUNT ON; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER PROCEDURE dbo.usp_DRE_StatsCapabilities_v1
    @CapabilitiesXml xml=NULL OUTPUT, @EmitResult bit=1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Version nvarchar(128)=CONVERT(nvarchar(128),SERVERPROPERTY('ProductVersion')),
            @Edition int=CONVERT(int,SERVERPROPERTY('EngineEdition')),
            @HasMetadata bit=NULL,@ProbeStatus varchar(40)='NOT_ATTEMPTED',
            @ProbeError int=NULL,@ProbeMessage nvarchar(4000)=NULL;
    DECLARE @Description TABLE(ColumnName sysname COLLATE DATABASE_DEFAULT NULL,ErrorNumber int NULL,ErrorMessage nvarchar(4000) COLLATE DATABASE_DEFAULT NULL);
    BEGIN TRY
        INSERT @Description(ColumnName,ErrorNumber,ErrorMessage)
            SELECT name,error_number,error_message
            FROM sys.dm_exec_describe_first_result_set
                (N'SELECT * FROM sys.dm_db_stats_properties(NULL,NULL);',NULL,0);
        IF EXISTS(SELECT 1 FROM @Description WHERE ErrorNumber IS NOT NULL)
        BEGIN
            SELECT TOP(1) @ProbeError=ErrorNumber,@ProbeMessage=ErrorMessage
            FROM @Description WHERE ErrorNumber IS NOT NULL;
            SET @ProbeStatus='DESCRIPTION_FAILED';
        END
        ELSE IF NOT EXISTS(SELECT 1 FROM @Description WHERE ColumnName=N'rows')
            SET @ProbeStatus='DESCRIPTION_INCOMPLETE';
        ELSE
        BEGIN
            SET @HasMetadata=CASE WHEN EXISTS(SELECT 1 FROM @Description
                WHERE ColumnName=N'persisted_sample_percent') THEN 1 ELSE 0 END;
            SET @ProbeStatus=CASE WHEN @HasMetadata=1 THEN 'COLUMN_PRESENT' ELSE 'COLUMN_NOT_PRESENT' END;
        END;
    END TRY
    BEGIN CATCH
        SELECT @ProbeStatus='DESCRIPTION_FAILED',@ProbeError=ERROR_NUMBER(),@ProbeMessage=ERROR_MESSAGE();
    END CATCH;

    SELECT @CapabilitiesXml=
    (
        SELECT '1.3.2' AS EngineCodeVersion, SYSUTCDATETIME() AS DetectedAtUTC,
            CONVERT(sysname,SERVERPROPERTY('ServerName')) AS ServerName,
            @Version AS ProductVersion,
            CONVERT(nvarchar(128),SERVERPROPERTY('Edition')) AS Edition,
            CONVERT(nvarchar(128),SERVERPROPERTY('ProductLevel')) AS ProductLevel,
            CONVERT(nvarchar(128),SERVERPROPERTY('ProductUpdateLevel')) AS ProductUpdateLevel,
            CONVERT(nvarchar(128),SERVERPROPERTY('ProductUpdateReference')) AS ProductUpdateReference,
            c.*, @HasMetadata AS HasPersistedSamplePercentMetadata,
            @ProbeStatus AS PersistedMetadataProbeStatus,
            @ProbeError AS MetadataProbeErrorNumber,@ProbeMessage AS MetadataProbeErrorMessage,
            'Feature boundaries, not servicing approval or workload certification.' AS CapabilityNote
        FROM dbo.ufn_DRE_StatsCapabilities_v1(@Version,@Edition) c
        FOR XML PATH('Capabilities'),TYPE
    );
    IF @EmitResult=1
        SELECT @Version AS ProductVersion,
            CONVERT(nvarchar(128),SERVERPROPERTY('Edition')) AS Edition,
            CONVERT(nvarchar(128),SERVERPROPERTY('ProductLevel')) AS ProductLevel,
            CONVERT(nvarchar(128),SERVERPROPERTY('ProductUpdateLevel')) AS ProductUpdateLevel,
            CONVERT(nvarchar(128),SERVERPROPERTY('ProductUpdateReference')) AS ProductUpdateReference,
            c.*, @HasMetadata AS HasPersistedSamplePercentMetadata,
            @ProbeStatus AS PersistedMetadataProbeStatus,
            @ProbeError AS MetadataProbeErrorNumber,@ProbeMessage AS MetadataProbeErrorMessage,
            @CapabilitiesXml AS CapabilitiesXml
        FROM dbo.ufn_DRE_StatsCapabilities_v1(@Version,@Edition) c;
END;
GO
-- dbo.usp_DRE_StatsScopeLookup_v1.sql
IF OBJECT_ID(N'dbo.usp_DRE_StatsScopeLookup_v1',N'P') IS NULL EXEC(N'CREATE PROCEDURE dbo.usp_DRE_StatsScopeLookup_v1 AS BEGIN SET NOCOUNT ON; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER PROCEDURE dbo.usp_DRE_StatsScopeLookup_v1
    @DatabaseName sysname,
    @ScopeXml xml OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @ScopeXml = NULL;

    DECLARE
        @DatabaseID int = DB_ID(@DatabaseName),
        @Matches int;

    IF @DatabaseID IS NULL
        THROW 51050,'The scope target database does not exist or is not visible.',1;

    -- Capture once: count and decision use the same configuration snapshot.
    -- Explicit NULL/NOT NULL is intentional. sysname otherwise defaults to NOT NULL.
    DECLARE @ScopeRows TABLE
    (
        DatabaseName sysname COLLATE DATABASE_DEFAULT NOT NULL,
        IsExcluded bit NOT NULL,
        ExclusionReason nvarchar(2000) COLLATE DATABASE_DEFAULT NULL,
        ExcludedBy sysname COLLATE DATABASE_DEFAULT NULL,
        ExcludedAtUTC datetime2(7) NULL,
        EnabledForEnforcement bit NOT NULL,
        ApprovedBy sysname COLLATE DATABASE_DEFAULT NULL,
        ApprovedAtUTC datetime2(7) NULL,
        Notes nvarchar(2000) COLLATE DATABASE_DEFAULT NOT NULL,
        Revision binary(8) NOT NULL
    );

    INSERT @ScopeRows
    (
        DatabaseName,
        IsExcluded,
        ExclusionReason,
        ExcludedBy,
        ExcludedAtUTC,
        EnabledForEnforcement,
        ApprovedBy,
        ApprovedAtUTC,
        Notes,
        Revision
    )
    SELECT
        DatabaseName,
        IsExcluded,
        ExclusionReason,
        ExcludedBy,
        ExcludedAtUTC,
        EnabledForEnforcement,
        ApprovedBy,
        ApprovedAtUTC,
        Notes,
        Revision
    FROM dbo.StatsGovernanceScope
    WHERE DB_ID(DatabaseName) = @DatabaseID;

    SELECT @Matches = COUNT(*)
    FROM @ScopeRows;

    IF @Matches > 1
        THROW 51051,'Multiple scope entries resolve to the same database. Resolve conflicting aliases before proceeding.',1;

    SELECT @ScopeXml =
    (
        SELECT
            DB_NAME(@DatabaseID) AS DatabaseName,
            @DatabaseID AS DatabaseID,
            s.DatabaseName AS ConfiguredDatabaseName,
            CONVERT(bit,CASE WHEN s.DatabaseName IS NULL THEN 0 ELSE 1 END) AS IsConfigured,
            ISNULL(s.IsExcluded,CONVERT(bit,0)) AS IsExcluded,
            s.ExclusionReason,
            s.ExcludedBy,
            s.ExcludedAtUTC,
            ISNULL(s.EnabledForEnforcement,CONVERT(bit,0)) AS EnabledForEnforcement,
            s.ApprovedBy,
            s.ApprovedAtUTC,
            s.Notes,
            sys.fn_varbintohexstr(s.Revision) AS Revision,
            SYSUTCDATETIME() AS CheckedAtUTC
        FROM (VALUES(1)) AS v(n)
        LEFT JOIN @ScopeRows AS s ON 1=1
        FOR XML PATH('Scope'),TYPE
    );
END;
GO
-- dbo.usp_DRE_SetStatsDatabaseScope_v1.sql
IF OBJECT_ID(N'dbo.usp_DRE_SetStatsDatabaseScope_v1',N'P') IS NULL EXEC(N'CREATE PROCEDURE dbo.usp_DRE_SetStatsDatabaseScope_v1 AS BEGIN SET NOCOUNT ON; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER PROCEDURE dbo.usp_DRE_SetStatsDatabaseScope_v1
    @DatabaseName nvarchar(4000),
    @IsExcluded bit=NULL,
    @EnabledForEnforcement bit=NULL,
    @Notes nvarchar(max)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'),0)<>1
        THROW 51052,'Scope configuration requires sysadmin.',1;
    IF @@TRANCOUNT<>0 OR (2 & @@OPTIONS)=2
        THROW 51053,'Configure scope outside an explicit transaction with IMPLICIT_TRANSACTIONS OFF.',1;
    SET @DatabaseName=LTRIM(RTRIM(@DatabaseName));
    SET @Notes=LTRIM(RTRIM(@Notes));
    IF @DatabaseName IS NULL OR LEN(@DatabaseName)=0 OR DATALENGTH(@DatabaseName)>256
        THROW 51054,'Specify one database name of at most 128 UTF-16 code units.',1;
    IF @Notes IS NULL OR LEN(@Notes)=0 OR DATALENGTH(@Notes)>4000
        THROW 51055,'A nonempty change reason of at most 2000 UTF-16 code units is required.',1;
    IF @IsExcluded IS NULL AND @EnabledForEnforcement IS NULL
        THROW 51056,'Specify IsExcluded or EnabledForEnforcement; NULL flags leave existing choices unchanged.',1;
    DECLARE @DatabaseID int=DB_ID(@DatabaseName),@CanonicalName sysname,
        @ConfigName sysname,@OldExcluded bit=0,@OldEnabled bit=0,
        @NewExcluded bit,@NewEnabled bit,@ApprovedBy sysname,@ApprovedAt datetime2(7),
        @ExcludedBy sysname,@ExcludedAt datetime2(7),@ExclusionReason nvarchar(2000),
        @Now datetime2(7)=SYSUTCDATETIME(),@LockResult int,@ScopeXml xml;
    SELECT @CanonicalName=name FROM sys.databases
    WHERE database_id=@DatabaseID AND database_id<>2 AND name<>N'SSISDB'
      AND is_distributor=0 AND source_database_id IS NULL;
    IF @CanonicalName IS NULL
        THROW 51057,'Configure an existing, non-snapshot supported database. tempdb, SSISDB, and replication distribution databases are excluded.',1;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC @LockResult=sys.sp_getapplock @Resource=N'DRE.StatsGovernance.v1.SCOPE_CONFIGURATION',
            @LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=5000,@DbPrincipal='public';
        IF @LockResult<0 THROW 51058,'Scope configuration lock was not acquired. No scope change was made.',1;
        -- HOLDLOCK/UPDLOCK also serializes the read/write decision with normal DML.
        IF (SELECT COUNT(*) FROM dbo.StatsGovernanceScope WITH(UPDLOCK,HOLDLOCK)
            WHERE DB_ID(DatabaseName)=@DatabaseID)>1
            THROW 51051,'Multiple scope entries resolve to the same database. Resolve conflicting aliases before proceeding.',1;
        SELECT @ConfigName=DatabaseName,@OldExcluded=IsExcluded,@OldEnabled=EnabledForEnforcement,
            @ApprovedBy=ApprovedBy,@ApprovedAt=ApprovedAtUTC,
            @ExcludedBy=ExcludedBy,@ExcludedAt=ExcludedAtUTC,@ExclusionReason=ExclusionReason
        FROM dbo.StatsGovernanceScope WITH(UPDLOCK,HOLDLOCK) WHERE DB_ID(DatabaseName)=@DatabaseID;
        SELECT @NewExcluded=COALESCE(@IsExcluded,@OldExcluded),
               @NewEnabled=COALESCE(@EnabledForEnforcement,@OldEnabled);
        IF @NewExcluded=1
        BEGIN
            IF @EnabledForEnforcement=1 THROW 51059,'An excluded database cannot be approved for enforcement. Remove the exclusion explicitly first.',1;
            SELECT @NewEnabled=0,@ApprovedBy=NULL,@ApprovedAt=NULL,
                   @ExcludedBy=ORIGINAL_LOGIN(),@ExcludedAt=@Now,@ExclusionReason=CONVERT(nvarchar(2000),@Notes);
        END
        ELSE
        BEGIN
            SELECT @ExcludedBy=NULL,@ExcludedAt=NULL,@ExclusionReason=NULL;
            IF @OldExcluded=1 AND @EnabledForEnforcement IS NULL SET @NewEnabled=0;
            IF @NewEnabled=0 SELECT @ApprovedBy=NULL,@ApprovedAt=NULL;
            ELSE IF @EnabledForEnforcement=1 OR @OldEnabled=0
                SELECT @ApprovedBy=ORIGINAL_LOGIN(),@ApprovedAt=@Now;
        END;
        IF @ConfigName IS NULL
            INSERT dbo.StatsGovernanceScope(DatabaseName,EnabledForEnforcement,ApprovedBy,ApprovedAtUTC,Notes,
                IsExcluded,ExclusionReason,ExcludedBy,ExcludedAtUTC)
            VALUES(@CanonicalName,@NewEnabled,@ApprovedBy,@ApprovedAt,CONVERT(nvarchar(2000),@Notes),
                @NewExcluded,@ExclusionReason,@ExcludedBy,@ExcludedAt);
        ELSE
            UPDATE dbo.StatsGovernanceScope SET EnabledForEnforcement=@NewEnabled,
                ApprovedBy=@ApprovedBy,ApprovedAtUTC=@ApprovedAt,Notes=CONVERT(nvarchar(2000),@Notes),
                IsExcluded=@NewExcluded,ExclusionReason=@ExclusionReason,ExcludedBy=@ExcludedBy,ExcludedAtUTC=@ExcludedAt
            WHERE DatabaseName=@ConfigName COLLATE Latin1_General_100_BIN2;
        -- Validate the readback while the change is still reversible.
        EXEC dbo.usp_DRE_StatsScopeLookup_v1 @CanonicalName,@ScopeXml OUTPUT;
        IF @ScopeXml IS NULL
            THROW 51061,'Scope readback returned no contract; the change was rolled back.',1;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
    SELECT @CanonicalName AS DatabaseName,@NewExcluded AS IsExcluded,@NewEnabled AS EnabledForEnforcement,
        @ScopeXml AS CurrentScopeXml;
END;
GO
-- dbo.usp_DRE_StatsOverride_v1.sql
IF OBJECT_ID(N'dbo.usp_DRE_StatsOverride_v1',N'P') IS NULL EXEC(N'CREATE PROCEDURE dbo.usp_DRE_StatsOverride_v1 AS BEGIN SET NOCOUNT ON; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER PROCEDURE dbo.usp_DRE_StatsOverride_v1
    @DatabaseName sysname, @SchemaName sysname, @TableName sysname,
    @StatName sysname, @OverrideXml xml OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @OverrideXml=NULL;
    SELECT @OverrideXml=
    (
        SELECT TOP (1) OverrideID,OverrideAction,SamplePercent,SampleRows,
            PersistenceMode,ForceUpdate,ApprovedBy,ApprovedAtUTC,
            ExpiresAtUTC,Notes,sys.fn_varbintohexstr(Revision) AS Revision
        FROM dbo.StatsGovernanceOverrides
        WHERE DatabaseName=@DatabaseName COLLATE Latin1_General_100_BIN2
          AND SchemaName=@SchemaName COLLATE Latin1_General_100_BIN2
          AND TableName=@TableName COLLATE Latin1_General_100_BIN2
          AND (StatName=@StatName COLLATE Latin1_General_100_BIN2 OR StatName IS NULL)
          AND IsEnabled=1 AND (ExpiresAtUTC IS NULL OR ExpiresAtUTC>SYSUTCDATETIME())
        ORDER BY CASE WHEN OverrideAction='EXCLUDE' THEN 0 ELSE 1 END,
                 CASE WHEN StatName IS NOT NULL THEN 0 ELSE 1 END,OverrideID
        FOR XML PATH('Override'),TYPE
    );
    IF @OverrideXml.exist('/Override[1]')=0 SET @OverrideXml=NULL;
END;
GO
-- dbo.usp_DRE_StatsDatabaseSelection_v1.sql
IF OBJECT_ID(N'dbo.usp_DRE_StatsDatabaseSelection_v1',N'P') IS NULL EXEC(N'CREATE PROCEDURE dbo.usp_DRE_StatsDatabaseSelection_v1 AS BEGIN SET NOCOUNT ON; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER PROCEDURE dbo.usp_DRE_StatsDatabaseSelection_v1
    @Databases nvarchar(max), @SelectionXml xml=NULL OUTPUT, @EmitResult bit=1
AS
BEGIN
    SET NOCOUNT ON;
    SET @SelectionXml=NULL;
    IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'),0)<>1
        THROW 51020,'Selection preview requires sysadmin to avoid partial database visibility.',1;
    SET @Databases=LTRIM(RTRIM(@Databases));
    IF @Databases IS NULL OR LEN(@Databases)=0
        THROW 51025,'Specify one database, a comma-separated list, ALL, SYSTEM_DATABASES, or USER_DATABASES.',1;
    DECLARE @List TABLE(DatabaseID int NOT NULL PRIMARY KEY,DatabaseName sysname COLLATE DATABASE_DEFAULT NOT NULL,
        DatabaseCreateDateLocal datetime2(7) NOT NULL,DatabaseState nvarchar(60) COLLATE DATABASE_DEFAULT NOT NULL,
        IsAccessible bit NOT NULL,IsSnapshot bit NOT NULL,IsLocalPrimary bit NOT NULL,IsExcluded bit NULL,
        EnabledForEnforcement bit NULL,ScopeXml xml NULL);
    IF UPPER(@Databases) IN (N'ALL',N'SYSTEM_DATABASES',N'USER_DATABASES')
        INSERT @List(DatabaseID,DatabaseName,DatabaseCreateDateLocal,DatabaseState,IsAccessible,IsSnapshot,IsLocalPrimary)
        SELECT database_id,name,create_date,state_desc,1,0,
            CONVERT(bit,ISNULL(sys.fn_hadr_is_primary_replica(name),1)) FROM sys.databases
        WHERE database_id<>DB_ID() AND database_id<>2 AND name<>N'SSISDB' AND is_distributor=0 AND state=0
            AND source_database_id IS NULL AND HAS_DBACCESS(name)=1
            AND ISNULL(sys.fn_hadr_is_primary_replica(name),1)=1
            AND (UPPER(@Databases)=N'ALL'
              OR (UPPER(@Databases)=N'SYSTEM_DATABASES' AND database_id IN (1,3,4))
              OR (UPPER(@Databases)=N'USER_DATABASES' AND database_id>4));
    ELSE
    BEGIN
        DECLARE @Tokens TABLE(Name nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL);
        DECLARE @TokenStart int=1,@TokenEnd int;
        WHILE 1=1
        BEGIN
            SET @TokenEnd=CHARINDEX(N',',@Databases,@TokenStart);
            IF @TokenEnd=0
            BEGIN
                INSERT @Tokens(Name) VALUES(LTRIM(RTRIM(SUBSTRING(@Databases,@TokenStart,LEN(@Databases)-@TokenStart+1))));
                BREAK;
            END;
            INSERT @Tokens(Name) VALUES(LTRIM(RTRIM(SUBSTRING(@Databases,@TokenStart,@TokenEnd-@TokenStart))));
            SET @TokenStart=@TokenEnd+1;
        END;
        IF EXISTS(SELECT 1 FROM @Tokens WHERE LEN(Name)=0 OR DATALENGTH(Name)>256)
            THROW 51031,'Database list contains an empty or overlength name. Use unbracketed names, without empty comma tokens.',1;
        IF EXISTS(SELECT 1 FROM @Tokens WHERE UPPER(Name) IN (N'ALL',N'SYSTEM_DATABASES',N'USER_DATABASES'))
            THROW 51031,'ALL, SYSTEM_DATABASES, and USER_DATABASES must be used alone. Use persistent database exclusions rather than negative list tokens.',1;
        IF EXISTS(SELECT 1 FROM @Tokens WHERE DB_ID(CONVERT(sysname,Name)) IS NULL)
            THROW 51031,'Database list contains a nonexistent or invisible database name. No database will be processed.',1;
        IF EXISTS(SELECT 1 FROM @Tokens t JOIN sys.databases d ON d.database_id=DB_ID(CONVERT(sysname,t.Name))
                  WHERE d.database_id=2 OR d.name=N'SSISDB' OR d.is_distributor=1)
            THROW 51031,'tempdb, SSISDB, and replication distribution databases are not supported governance targets.',1;
        INSERT @List(DatabaseID,DatabaseName,DatabaseCreateDateLocal,DatabaseState,IsAccessible,IsSnapshot,IsLocalPrimary)
        SELECT DISTINCT d.database_id,d.name,d.create_date,d.state_desc,
            CONVERT(bit,ISNULL(HAS_DBACCESS(d.name),0)),CONVERT(bit,CASE WHEN d.source_database_id IS NULL THEN 0 ELSE 1 END),
            CONVERT(bit,ISNULL(sys.fn_hadr_is_primary_replica(d.name),1))
        FROM @Tokens t JOIN sys.databases d ON d.database_id=DB_ID(CONVERT(sysname,t.Name));
    END;
    IF NOT EXISTS(SELECT 1 FROM @List) THROW 51032,'No databases matched the requested catalog selection.',1;
    DECLARE @ID int=0,@Db sysname,@Scope xml;
    WHILE EXISTS(SELECT 1 FROM @List WHERE DatabaseID>@ID)
    BEGIN
        SELECT TOP(1) @ID=DatabaseID,@Db=DatabaseName FROM @List WHERE DatabaseID>@ID ORDER BY DatabaseID;
        EXEC dbo.usp_DRE_StatsScopeLookup_v1 @Db,@Scope OUTPUT;
        UPDATE @List SET ScopeXml=@Scope,
            IsExcluded=@Scope.value('(/Scope/IsExcluded/text())[1]','bit'),
            EnabledForEnforcement=@Scope.value('(/Scope/EnabledForEnforcement/text())[1]','bit')
        WHERE DatabaseID=@ID;
    END;
    SELECT @SelectionXml=(SELECT DatabaseID,DatabaseName,DatabaseCreateDateLocal,DatabaseState,IsAccessible,IsSnapshot,IsLocalPrimary,
        IsExcluded,EnabledForEnforcement,
        CASE WHEN IsExcluded=1 THEN 'EXCLUDED' WHEN IsLocalPrimary=0 THEN 'BLOCKED_SECONDARY' ELSE 'SELECTED' END AS SelectionStatus,
        CASE WHEN IsExcluded=1 THEN 'PERSISTENT_DATABASE_EXCLUSION'
             WHEN IsLocalPrimary=0 THEN 'ALWAYS_ON_SECONDARY_REPLICA' ELSE 'REQUESTED_DATABASE' END AS SelectionReason,
        CONVERT(bit,CASE WHEN DatabaseID<>2 AND DatabaseState=N'ONLINE' AND IsAccessible=1 AND IsSnapshot=0 AND IsLocalPrimary=1 THEN 1 ELSE 0 END) AS ReadyForCollection,
        ScopeXml.query('/Scope')
        FROM @List ORDER BY DatabaseName FOR XML PATH('Database'),ROOT('DatabaseSelection'),TYPE);
    IF @EmitResult=1
        SELECT DatabaseID,DatabaseName,DatabaseState,IsAccessible,IsSnapshot,IsLocalPrimary,
            CASE WHEN IsExcluded=1 THEN 'EXCLUDED' WHEN IsLocalPrimary=0 THEN 'BLOCKED_SECONDARY' ELSE 'SELECTED' END AS SelectionStatus,
            CASE WHEN IsExcluded=1 THEN 'PERSISTENT_DATABASE_EXCLUSION'
                 WHEN IsLocalPrimary=0 THEN 'ALWAYS_ON_SECONDARY_REPLICA' ELSE 'REQUESTED_DATABASE' END AS SelectionReason,
            IsExcluded,EnabledForEnforcement,
            CONVERT(bit,CASE WHEN IsExcluded=0 AND DatabaseID<>2 AND DatabaseState=N'ONLINE'
                AND IsAccessible=1 AND IsSnapshot=0 AND IsLocalPrimary=1 THEN 1 ELSE 0 END) AS WillCollect,
            CASE WHEN ScopeXml.exist('/Scope/ExclusionReason[1]')=1
                THEN ScopeXml.value('(/Scope/ExclusionReason/text())[1]','nvarchar(2000)') END AS ExclusionReason,
            ScopeXml
        FROM @List ORDER BY DatabaseName;
END;
GO
-- dbo.usp_DRE_StatsCollect_v1.sql
IF OBJECT_ID(N'dbo.usp_DRE_StatsCollect_v1',N'P') IS NULL EXEC(N'CREATE PROCEDURE dbo.usp_DRE_StatsCollect_v1 AS BEGIN SET NOCOUNT ON; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER PROCEDURE dbo.usp_DRE_StatsCollect_v1
    @DatabaseName sysname,
    @ObjectID int = NULL,
    @StatsID int = NULL,
    @IncludeEnvironment bit = 1,
    @LegacyTraceFlagVisible bit = 0,
    @SnapshotXml xml = NULL OUTPUT,
    @EnvironmentXml xml = NULL OUTPUT,
    @CapabilitiesXml xml = NULL,
    @ModernTraceFlagVisible bit = 0,
    @DynamicStatsTraceFlagGlobal bit = 0,
    @TargetTablesXml xml = NULL,
    @StatisticsScope varchar(20) = 'ALL'
AS
BEGIN
    SET NOCOUNT ON;
    SET @SnapshotXml=NULL;
    SET @EnvironmentXml=NULL;
    SET @StatisticsScope=UPPER(LTRIM(RTRIM(@StatisticsScope)));
    IF DB_ID(@DatabaseName) IS NULL THROW 51010,'Target database does not exist or is not visible.',1;
    IF @StatisticsScope IS NULL OR @StatisticsScope NOT IN ('ALL','INDEX_ONLY','AUTO_ONLY','USER_ONLY','NON_AUTO')
        THROW 51120,'StatisticsScope must be ALL, INDEX_ONLY, AUTO_ONLY, USER_ONLY, or NON_AUTO.',1;

    IF @CapabilitiesXml IS NULL
        EXEC dbo.usp_DRE_StatsCapabilities_v1 @CapabilitiesXml=@CapabilitiesXml OUTPUT,@EmitResult=0;
    DECLARE @HasMetadata bit=CASE WHEN @CapabilitiesXml.exist('/Capabilities/HasPersistedSamplePercentMetadata[1]')=1
                THEN @CapabilitiesXml.value('(/Capabilities/HasPersistedSamplePercentMetadata/text())[1]','bit') END,
            @SupportsPersist bit=CASE WHEN @CapabilitiesXml.exist('/Capabilities/SupportsPersistSamplePercent[1]')=1
                THEN @CapabilitiesXml.value('(/Capabilities/SupportsPersistSamplePercent/text())[1]','bit') END,
            @SupportsHistogram bit=CASE WHEN @CapabilitiesXml.exist('/Capabilities/SupportsStatsHistogramDMF[1]')=1
                THEN @CapabilitiesXml.value('(/Capabilities/SupportsStatsHistogramDMF/text())[1]','bit') END;
    IF ISNULL(@CapabilitiesXml.value('(/Capabilities/SupportedEngine/text())[1]','bit'),0)<>1
        THROW 51011,'Unrecognized engine/build for metadata collection.',1;

    DECLARE @HistogramSelect nvarchar(max),@HistogramApply nvarchar(max);
    IF @SupportsHistogram=1
    BEGIN
        SET @HistogramSelect=N'
                h.HistogramObservedSteps,h.HistogramEstimatedRows,
                h.HistogramMaxEqualityRows,h.HistogramMaxRangeRows,h.HistogramTop3EqualityRows,
                CONVERT(decimal(19,6),100.0*h.HistogramMaxEqualityRows/NULLIF(h.HistogramEstimatedRows,0)) AS HistogramDominantEqualityPercent,
                CONVERT(decimal(19,6),100.0*h.HistogramTop3EqualityRows/NULLIF(h.HistogramEstimatedRows,0)) AS HistogramTop3EqualityPercent,
                CASE WHEN sp.object_id IS NULL THEN ''STATISTICS_PROPERTIES_UNAVAILABLE''
                     WHEN ISNULL(h.HistogramObservedSteps,0)=0 THEN ''NO_HISTOGRAM_ROWS''
                     ELSE ''AVAILABLE'' END AS HistogramAnalysisStatus,';
        SET @HistogramApply=N'
            OUTER APPLY
            (
                SELECT COUNT_BIG(*) AS HistogramObservedSteps,
                    CONVERT(decimal(38,6),SUM(CONVERT(decimal(38,6),ISNULL(hg.equal_rows,0)+ISNULL(hg.range_rows,0)))) AS HistogramEstimatedRows,
                    CONVERT(decimal(38,6),MAX(ISNULL(hg.equal_rows,0))) AS HistogramMaxEqualityRows,
                    CONVERT(decimal(38,6),MAX(ISNULL(hg.range_rows,0))) AS HistogramMaxRangeRows,
                    CONVERT(decimal(38,6),(SELECT SUM(CONVERT(decimal(38,6),x.equal_rows))
                       FROM (SELECT TOP (3) h3.equal_rows
                             FROM sys.dm_db_stats_histogram(s.object_id,s.stats_id) AS h3
                             ORDER BY h3.equal_rows DESC) AS x)) AS HistogramTop3EqualityRows
                FROM sys.dm_db_stats_histogram(s.object_id,s.stats_id) AS hg
            ) AS h';
    END
    ELSE
    BEGIN
        SET @HistogramSelect=N'
                CONVERT(bigint,NULL) AS HistogramObservedSteps,
                CONVERT(decimal(38,6),NULL) AS HistogramEstimatedRows,
                CONVERT(decimal(38,6),NULL) AS HistogramMaxEqualityRows,
                CONVERT(decimal(38,6),NULL) AS HistogramMaxRangeRows,
                CONVERT(decimal(38,6),NULL) AS HistogramTop3EqualityRows,
                CONVERT(decimal(19,6),NULL) AS HistogramDominantEqualityPercent,
                CONVERT(decimal(19,6),NULL) AS HistogramTop3EqualityPercent,
                CASE WHEN @HistogramCap=0 THEN ''NOT_SUPPORTED_ON_THIS_BUILD'' ELSE ''CAPABILITY_UNKNOWN'' END AS HistogramAnalysisStatus,';
        SET @HistogramApply=N'';
    END;

    DECLARE @Sql nvarchar(max)=N'USE '+QUOTENAME(@DatabaseName)+N';
        DECLARE @CapturedUTC datetime2(7)=SYSUTCDATETIME();
        DECLARE @CapturedLocal datetime2(7)=SYSDATETIME();
        DECLARE @Compat int=(SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID());
        DECLARE @ScopedLegacy bit=(SELECT CONVERT(bit,value) FROM sys.database_scoped_configurations WHERE name=N''LEGACY_CARDINALITY_ESTIMATION'');
        DECLARE @Major int=@Caps.value(''(/Capabilities/ProductMajorVersion/text())[1]'',''int'');
        DECLARE @EngineEdition int=@Caps.value(''(/Capabilities/EngineEdition/text())[1]'',''int'');
        DECLARE @QSState nvarchar(60)=(SELECT actual_state_desc FROM sys.database_query_store_options);
        DECLARE @AutoUpdateStats bit=(SELECT is_auto_update_stats_on FROM sys.databases WHERE database_id=DB_ID());
        DECLARE @AutoUpdateStatsAsync bit=(SELECT is_auto_update_stats_async_on FROM sys.databases WHERE database_id=DB_ID());
        DECLARE @CEFeedbackSetting bit=(SELECT CONVERT(bit,value) FROM sys.database_scoped_configurations WHERE name=N''CE_FEEDBACK'');
        DECLARE @Legacy bit=CASE WHEN @LegacyFlag=1 AND @ModernFlag=1 THEN NULL WHEN @ModernFlag=1 THEN 0
            WHEN @Compat<120 OR @ScopedLegacy=1 OR @LegacyFlag=1 THEN 1 ELSE 0 END;
        DECLARE @SamplingScanBehavior varchar(100)=CASE
            WHEN @EngineEdition=8 OR @Major>=14 THEN ''SERIAL_SAMPLING_SCAN_OTHER_OPERATORS_MAY_PARALLELIZE''
            WHEN @Major=13 AND @Compat=130 THEN ''PARALLEL_SAMPLING_SCAN_POSSIBLE''
            ELSE ''SERIAL_SAMPLING_SCAN'' END;
        -- Updateability reports READ_ONLY on SQL Server AG secondaries and
        -- Azure SQL Managed Instance read-only replicas.
        DECLARE @Writable bit=CASE WHEN DATABASEPROPERTYEX(DB_NAME(),''Updateability'')=''READ_WRITE''
               THEN 1 ELSE 0 END;
        DECLARE @Targets TABLE(SchemaName sysname COLLATE DATABASE_DEFAULT NOT NULL,TableName sysname COLLATE DATABASE_DEFAULT NOT NULL,
                               PRIMARY KEY(SchemaName,TableName));
        IF @TargetTables IS NOT NULL
            INSERT @Targets(SchemaName,TableName)
            SELECT T.n.value(''(SchemaName/text())[1]'',''nvarchar(128)''),T.n.value(''(TableName/text())[1]'',''nvarchar(128)'')
            FROM @TargetTables.nodes(''/TableTargets/Table'') AS T(n);

        ;WITH RowTotals AS
        (
            SELECT object_id,SUM(row_count) AS CurrentTableRows,COUNT_BIG(*) AS BasePartitionCount
            FROM sys.dm_db_partition_stats WHERE index_id IN(0,1) AND (@OID IS NULL OR object_id=@OID)
            GROUP BY object_id
        )
        SELECT @Out=(SELECT @CapturedUTC AS CapturedAtUTC,@CapturedLocal AS CapturedAtLocal,
                DB_ID() AS DatabaseID,DB_NAME() AS DatabaseName,t.object_id AS ObjectID,t.create_date AS ObjectCreateDateLocal,
                s.stats_id AS StatsID,sch.name AS SchemaName,t.name AS TableName,s.name AS StatName,t.type AS ObjectType,
                i.name AS IndexName,i.type AS IndexType,i.type_desc AS IndexTypeDescription,
                CASE WHEN i.index_id IS NULL THEN ''STANDALONE''
                     WHEN i.type IN(1,2) THEN ''ROWSTORE'' WHEN i.type=3 THEN ''XML'' WHEN i.type=4 THEN ''SPATIAL''
                     WHEN i.type IN(5,6) THEN ''COLUMNSTORE'' WHEN i.type=7 THEN ''HASH'' WHEN i.type=9 THEN ''JSON'' ELSE ''UNKNOWN'' END AS IndexFamily,
                CASE WHEN i.index_id IS NOT NULL THEN ''INDEX_ASSOCIATED''
                     WHEN EXISTS(SELECT 1 FROM sys.indexes ci2 WHERE ci2.object_id=t.object_id AND ci2.type IN(5,6))
                         THEN ''STANDALONE_ON_TABLE_WITH_COLUMNSTORE'' ELSE ''STANDALONE'' END AS StatisticsContext,
                ISNULL(i.is_disabled,0) AS IndexDisabled,ISNULL(i.is_hypothetical,0) AS IndexHypothetical,ISNULL(b.is_disabled,0) AS BaseIndexDisabled,
                CASE WHEN b.type=5 THEN ''CLUSTERED_COLUMNSTORE'' WHEN b.type=1 THEN ''CLUSTERED_ROWSTORE'' ELSE ''HEAP'' END AS BaseStorage,
                CONVERT(bit,CASE WHEN EXISTS(SELECT 1 FROM sys.indexes ci WHERE ci.object_id=t.object_id AND ci.type IN(5,6)) THEN 1 ELSE 0 END) AS HasColumnstore,
                t.is_memory_optimized AS IsMemoryOptimized,s.auto_created AS AutoCreated,s.user_created AS UserCreated,
                CASE WHEN i.index_id IS NOT NULL THEN ''Index'' WHEN s.auto_created=1 THEN ''AutoCreated'' ELSE ''UserCreated'' END AS StatisticType,
                s.no_recompute AS NoRecompute,s.is_temporary AS IsTemporary,s.is_incremental AS IsIncremental,s.has_filter AS HasFilter,
                s.filter_definition AS FilterDefinition,c.name AS LeadingColumnName,TYPE_NAME(c.system_type_id) AS LeadingColumnDataType,
                c.max_length AS LeadingColumnMaxLengthBytes,c.is_identity AS LeadingColumnIsIdentity,rt.CurrentTableRows,rt.BasePartitionCount,
                CONVERT(bit,CASE WHEN sp.object_id IS NULL THEN 0 ELSE 1 END) AS StatsPropertiesAvailable,
                sp.rows AS StatsRows,sp.rows_sampled AS RowsSampled,sp.unfiltered_rows AS UnfilteredRowsAtLastUpdate,
                sp.last_updated AS LastUpdatedLocal,DATEDIFF_BIG(MINUTE,sp.last_updated,@CapturedLocal) AS StatsAgeMinutes,
                sp.modification_counter AS ModificationCounter,
                TRY_CONVERT(bigint,CONVERT(decimal(38,0),rt.CurrentTableRows)-CONVERT(decimal(38,0),COALESCE(sp.unfiltered_rows,sp.rows))) AS RowCountDeltaSinceStatsUpdate,
                nt.AutoUpdateThresholdBasisRows,
                nt.EstimatedAutoUpdateThresholdModifications,
                nt.EstimatedAutoUpdateThresholdModifications AS EstimatedNextAutoUpdateAtModificationCounter,
                CONVERT(bit,CASE WHEN nt.EstimatedAutoUpdateThresholdModifications IS NULL THEN 0 ELSE 1 END) AS AutoUpdateThresholdIsEstimate,
                CASE WHEN nt.EstimatedAutoUpdateThresholdModifications IS NULL OR sp.modification_counter IS NULL THEN NULL
                     WHEN sp.modification_counter>=nt.EstimatedAutoUpdateThresholdModifications THEN CONVERT(bigint,0)
                     ELSE nt.EstimatedAutoUpdateThresholdModifications-sp.modification_counter END AS EstimatedModificationsRemainingToAutoUpdate,
                CASE WHEN nt.EstimatedAutoUpdateThresholdModifications IS NULL OR nt.EstimatedAutoUpdateThresholdModifications=0 OR sp.modification_counter IS NULL THEN NULL
                     ELSE CONVERT(decimal(19,6),CONVERT(decimal(38,6),sp.modification_counter)*100.0/nt.EstimatedAutoUpdateThresholdModifications) END AS AutoUpdateThresholdProgressPercent,
                CASE WHEN nt.EstimatedAutoUpdateThresholdModifications IS NULL OR sp.modification_counter IS NULL THEN NULL
                     WHEN sp.modification_counter>=nt.EstimatedAutoUpdateThresholdModifications THEN CONVERT(bit,1) ELSE CONVERT(bit,0) END AS AutoUpdateThresholdReached,
                nt.AutoUpdateThresholdPolicy,nt.AutoUpdateThresholdFormula,
                CONVERT(bit,CASE WHEN sp.object_id IS NULL OR nt.AutoUpdateThresholdBasisRows IS NULL OR nt.EstimatedAutoUpdateThresholdModifications IS NULL
                                      OR sp.modification_counter IS NULL OR s.no_recompute=1 OR s.is_temporary=1 THEN 0 ELSE 1 END) AS AutoUpdateThresholdApplicable,
                CASE WHEN sp.object_id IS NULL THEN ''STATISTICS_PROPERTIES_UNAVAILABLE''
                     WHEN nt.AutoUpdateThresholdBasisRows IS NULL OR nt.EstimatedAutoUpdateThresholdModifications IS NULL THEN ''THRESHOLD_BASIS_UNAVAILABLE''
                     WHEN sp.modification_counter IS NULL THEN ''MODIFICATION_COUNTER_UNAVAILABLE''
                     WHEN s.is_temporary=1 THEN ''TEMPORARY_STATISTIC_CONTEXT_REVIEW''
                     WHEN s.no_recompute=1 THEN ''NORECOMPUTE_AUTO_UPDATE_DISABLED''
                     WHEN @AutoUpdateStats=0 AND sp.modification_counter>=nt.EstimatedAutoUpdateThresholdModifications THEN ''THRESHOLD_REACHED_AUTO_UPDATE_OFF''
                     WHEN @AutoUpdateStats=0 THEN ''BELOW_THRESHOLD_AUTO_UPDATE_OFF''
                     WHEN sp.modification_counter>=nt.EstimatedAutoUpdateThresholdModifications AND @AutoUpdateStatsAsync=1 THEN ''THRESHOLD_REACHED_ASYNC''
                     WHEN sp.modification_counter>=nt.EstimatedAutoUpdateThresholdModifications THEN ''THRESHOLD_REACHED_SYNC''
                     ELSE ''BELOW_THRESHOLD'' END AS AutoUpdateThresholdState,
                @AutoUpdateStats AS AutoUpdateStatisticsOn,@AutoUpdateStatsAsync AS AutoUpdateStatisticsAsyncOn,
                @Major AS ThresholdProductMajorVersion,@Compat AS ThresholdCompatibilityLevel,@DynamicFlag AS ThresholdTraceFlag2371,
                CASE WHEN @Legacy=1 THEN ''LEGACY_CE_CONTEXT'' WHEN @Legacy=0 THEN ''MODERN_CE_CONTEXT'' ELSE ''AMBIGUOUS_CE_CONTEXT'' END AS ThresholdCEContext,
                '+CASE WHEN @HasMetadata=1 THEN N'CONVERT(decimal(19,6),sp.persisted_sample_percent)' ELSE N'CONVERT(decimal(19,6),NULL)' END+N' AS PersistedSamplePercent,
                @HasMeta AS HasPersistedSamplePercentMetadata,@Caps.value(''(/Capabilities/SupportsStatisticsMAXDOP/text())[1]'',''bit'') AS SupportsStatisticsMAXDOP,
                @SupportsPersist AS SupportsPersistSamplePercent,@Caps.value(''(/Capabilities/PreservesPersistedSampleAfterRebuild/text())[1]'',''bit'') AS PreservesPersistedSampleAfterRebuild,
                CASE WHEN @HasMeta=1 THEN ''AVAILABLE'' WHEN @HasMeta=0 AND @SupportsPersist=0 THEN ''NOT_SUPPORTED_ON_THIS_BUILD'' ELSE ''UNAVAILABLE_OR_PROBE_FAILED'' END AS PersistedSampleMetadataStatus,
                @SamplingScanBehavior AS ExpectedSamplingScanBehavior,''NOT_CAPTURED'' AS ObservedDOPStatus,''NOT_CAPTURED'' AS MemoryGrantCaptureStatus,''NOT_CAPTURED'' AS SpillCaptureStatus,
                sp.steps AS HistogramSteps,'+@HistogramSelect+N'
                @Compat AS CompatibilityLevel,@ScopedLegacy AS ScopedLegacyCE,@LegacyFlag AS LegacyTraceFlagVisible,@Legacy AS LegacyCEContext,
                @Writable AS WritablePrimary,''NOT_COLLECTED_V1'' AS QueryRegressionEvidenceStatus,''NOT_COLLECTED_V1'' AS StatisticsUsageEvidenceStatus
            FROM sys.stats s JOIN sys.tables t ON t.object_id=s.object_id JOIN sys.schemas sch ON sch.schema_id=t.schema_id
            LEFT JOIN sys.indexes i ON i.object_id=s.object_id AND i.index_id=s.stats_id
            LEFT JOIN sys.indexes b ON b.object_id=t.object_id AND b.index_id=1
            LEFT JOIN RowTotals rt ON rt.object_id=t.object_id
            LEFT JOIN sys.stats_columns sc ON sc.object_id=s.object_id AND sc.stats_id=s.stats_id AND sc.stats_column_id=1
            LEFT JOIN sys.columns c ON c.object_id=sc.object_id AND c.column_id=sc.column_id
            OUTER APPLY sys.dm_db_stats_properties(s.object_id,s.stats_id) sp
            OUTER APPLY
            (
                SELECT COALESCE(sp.unfiltered_rows,sp.rows) AS AutoUpdateThresholdBasisRows
            ) AS tb
            OUTER APPLY
            (
                SELECT tb.AutoUpdateThresholdBasisRows,
                    TRY_CONVERT(bigint,FLOOR(CASE
                        WHEN tb.AutoUpdateThresholdBasisRows IS NULL THEN NULL
                        WHEN tb.AutoUpdateThresholdBasisRows<=500 THEN CONVERT(float,500.0)
                        WHEN ((@Major>=13 OR @EngineEdition=8) AND @Compat>=130) OR @DynamicFlag=1
                            THEN CASE WHEN 500.0+(0.20*CONVERT(float,tb.AutoUpdateThresholdBasisRows))
                                           <=SQRT(1000.0*CONVERT(float,tb.AutoUpdateThresholdBasisRows))
                                      THEN 500.0+(0.20*CONVERT(float,tb.AutoUpdateThresholdBasisRows))
                                      ELSE SQRT(1000.0*CONVERT(float,tb.AutoUpdateThresholdBasisRows)) END
                        ELSE 500.0+(0.20*CONVERT(float,tb.AutoUpdateThresholdBasisRows)) END)) AS EstimatedAutoUpdateThresholdModifications,
                    CASE WHEN tb.AutoUpdateThresholdBasisRows IS NULL THEN ''UNAVAILABLE''
                         WHEN tb.AutoUpdateThresholdBasisRows<=500 THEN ''SMALL_TABLE_FIXED_500''
                         WHEN (@Major>=13 OR @EngineEdition=8) AND @Compat>=130 THEN ''DYNAMIC_COMPAT_130_PLUS''
                         WHEN @DynamicFlag=1 THEN ''DYNAMIC_GLOBAL_TF2371''
                         ELSE ''LEGACY_FIXED_20_PERCENT_PLUS_500'' END AS AutoUpdateThresholdPolicy,
                    CASE WHEN tb.AutoUpdateThresholdBasisRows IS NULL THEN ''UNAVAILABLE''
                         WHEN tb.AutoUpdateThresholdBasisRows<=500 THEN ''500''
                         WHEN ((@Major>=13 OR @EngineEdition=8) AND @Compat>=130) OR @DynamicFlag=1
                              THEN ''MIN(500 + (0.20 * n), SQRT(1000 * n))''
                         ELSE ''500 + (0.20 * n)'' END AS AutoUpdateThresholdFormula
            ) AS nt
            '+@HistogramApply+N'
            WHERE (t.is_ms_shipped=0 OR DB_ID() IN (1,3,4)) AND t.is_external=0
              AND (@OID IS NULL OR s.object_id=@OID) AND (@SID IS NULL OR s.stats_id=@SID)
              AND (NOT EXISTS(SELECT 1 FROM @Targets) OR EXISTS(SELECT 1 FROM @Targets q WHERE q.SchemaName=sch.name AND q.TableName=t.name))
              AND (@Scope=''ALL'' OR (@Scope=''INDEX_ONLY'' AND i.index_id IS NOT NULL)
                   OR (@Scope=''AUTO_ONLY'' AND i.index_id IS NULL AND s.auto_created=1)
                   OR (@Scope=''USER_ONLY'' AND i.index_id IS NULL AND s.user_created=1)
                   OR (@Scope=''NON_AUTO'' AND s.auto_created=0))
            ORDER BY sch.name,t.name,s.name FOR XML PATH(''Statistic''),ROOT(''Statistics''),TYPE);

        IF @IncludeEnv=1
        BEGIN
            SELECT @Env=(SELECT @CapturedUTC AS CapturedAtUTC,DB_NAME() AS DatabaseName,@Compat AS CompatibilityLevel,
                    @ScopedLegacy AS ScopedLegacyCE,@LegacyFlag AS LegacyTraceFlagVisible,@Writable AS WritablePrimary,
                    d.is_auto_create_stats_on AS AutoCreateStatisticsOn,d.is_auto_update_stats_on AS AutoUpdateStatisticsOn,
                    d.is_auto_update_stats_async_on AS AutoUpdateStatisticsAsyncOn,@QSState AS QueryStoreState,@Caps.query(''/Capabilities''),
                    @SamplingScanBehavior AS ExpectedSamplingScanBehavior,@ModernFlag AS ModernTraceFlagVisible,@DynamicFlag AS GlobalTraceFlag2371,
                    @Scope AS StatisticsScope,@TargetTables AS TargetTables,
                    CASE WHEN (@Major>=13 OR @EngineEdition=8) AND @Compat>=130 THEN ''DYNAMIC_COMPAT_130_PLUS''
                         WHEN @DynamicFlag=1 THEN ''DYNAMIC_GLOBAL_TF2371'' ELSE ''LEGACY_FIXED_20_PERCENT_PLUS_500'' END AS AutoUpdateThresholdContext,
                    CASE WHEN @Caps.value(''(/Capabilities/SupportsQueryStoreWaitStats/text())[1]'',''bit'')=0 THEN ''NOT_SUPPORTED_ON_THIS_BUILD''
                         WHEN @QSState NOT IN(''READ_WRITE'',''READ_ONLY'') THEN ''QUERY_STORE_NOT_ACTIVE'' ELSE ''AVAILABLE_NOT_COLLECTED'' END AS QueryStoreWaitEvidenceStatus,
                    @CEFeedbackSetting AS ScopedCEFeedback,
                    CASE WHEN @Caps.exist(''/Capabilities/SupportsCEFeedback[1]'')=1
                                   AND @Caps.value(''(/Capabilities/SupportsCEFeedback/text())[1]'',''bit'')=0
                              THEN ''NOT_SUPPORTED_ON_THIS_BUILD''
                         WHEN @CEFeedbackSetting IS NULL THEN ''SCOPED_SETTING_UNAVAILABLE_ON_THIS_POLICY''
                         WHEN @Compat<160 THEN ''COMPATIBILITY_BELOW_160'' WHEN @QSState<>''READ_WRITE'' THEN ''QUERY_STORE_NOT_READ_WRITE''
                         WHEN ISNULL(@CEFeedbackSetting,0)<>1 THEN ''SCOPED_SETTING_NOT_ENABLED'' ELSE ''DATABASE_PREREQUISITES_MET_NOT_COLLECTED'' END AS CEFeedbackEvidenceStatus,
                    (SELECT CONVERT(int,value) FROM sys.database_scoped_configurations WHERE name=N''MAXDOP'') AS DatabaseScopedMAXDOP,
                    (SELECT CONVERT(int,value_in_use) FROM sys.configurations WHERE name=N''max degree of parallelism'') AS ServerMAXDOP,
                    ''Unavailable telemetry is not zero usage; query-specific feedback and CE are not evaluated.'' AS EvidenceCoverage,
                    ''Database defaults and this maintenance session only; query-specific CE is unknown.'' AS CECoverage,
                    (SELECT OBJECT_SCHEMA_NAME(rg.object_id) AS SchemaName,OBJECT_NAME(rg.object_id) AS TableName,rg.object_id AS ObjectID,rg.index_id AS IndexID,
                            i.name AS IndexName,rg.partition_number AS PartitionNumber,SUM(CONVERT(bigint,CASE WHEN rg.state=1 THEN 1 ELSE 0 END)) AS OpenRowgroups,
                            SUM(CONVERT(bigint,CASE WHEN rg.state=2 THEN 1 ELSE 0 END)) AS ClosedRowgroups,SUM(CASE WHEN rg.state IN(1,2) THEN rg.total_rows ELSE 0 END) AS DeltaRows,
                            SUM(CASE WHEN rg.state=3 THEN rg.total_rows ELSE 0 END) AS CompressedPhysicalRows,SUM(CASE WHEN rg.state=3 THEN rg.deleted_rows ELSE 0 END) AS CompressedDeletedRows,
                            CONVERT(decimal(19,6),100.0*SUM(CASE WHEN rg.state IN(1,2) THEN CONVERT(decimal(28,6),rg.total_rows) ELSE 0 END)
                              /NULLIF(SUM(CASE WHEN rg.state IN(1,2,3) THEN CONVERT(decimal(28,6),rg.total_rows-rg.deleted_rows) ELSE 0 END),0)) AS DeltaPercentApprox,
                            ''Approximate: excludes NCCI delete-buffer rows; advisory, not an update gate.'' AS MeasurementNote
                     FROM sys.column_store_row_groups rg JOIN sys.indexes i ON i.object_id=rg.object_id AND i.index_id=rg.index_id
                     GROUP BY rg.object_id,rg.index_id,i.name,rg.partition_number FOR XML PATH(''IndexPartition''),ROOT(''ColumnstoreHealth''),TYPE)
                FROM sys.databases d WHERE d.database_id=DB_ID() FOR XML PATH(''Environment''),TYPE);
        END;';

    EXEC sys.sp_executesql @Sql,
        N'@OID int,@SID int,@IncludeEnv bit,@LegacyFlag bit,@ModernFlag bit,@DynamicFlag bit,@Caps xml,@HasMeta bit,@SupportsPersist bit,
          @HistogramCap bit,@TargetTables xml,@Scope varchar(20),@Out xml OUTPUT,@Env xml OUTPUT',
        @OID=@ObjectID,@SID=@StatsID,@IncludeEnv=@IncludeEnvironment,@LegacyFlag=@LegacyTraceFlagVisible,@ModernFlag=@ModernTraceFlagVisible,
        @DynamicFlag=@DynamicStatsTraceFlagGlobal,@Caps=@CapabilitiesXml,@HasMeta=@HasMetadata,@SupportsPersist=@SupportsPersist,
        @HistogramCap=@SupportsHistogram,@TargetTables=@TargetTablesXml,@Scope=@StatisticsScope,@Out=@SnapshotXml OUTPUT,@Env=@EnvironmentXml OUTPUT;
END;
GO
-- dbo.usp_DRE_StatsCheckDatabaseGate_v1.sql
IF OBJECT_ID(N'dbo.usp_DRE_StatsCheckDatabaseGate_v1',N'P') IS NULL EXEC(N'CREATE PROCEDURE dbo.usp_DRE_StatsCheckDatabaseGate_v1 AS BEGIN SET NOCOUNT ON; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER PROCEDURE dbo.usp_DRE_StatsCheckDatabaseGate_v1
    @RunID uniqueidentifier,@DatabaseName sysname,@CanProcess bit OUTPUT,@GateReason varchar(80) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @CanProcess=0,@GateReason=NULL;
    DECLARE @Mode varchar(10),@ExpectedID int,@ExpectedCreated datetime2(7),
        @InitialStatus varchar(24),@Scope xml,@CheckUTC datetime2(7)=SYSUTCDATETIME(),
        @Error int=NULL,@Message nvarchar(4000)=NULL,@Status varchar(40);
    SELECT @Mode=r.Mode,@ExpectedID=d.DatabaseIDAtSelection,@ExpectedCreated=d.DatabaseCreateDateAtSelection,
        @InitialStatus=d.SelectionStatus
    FROM dbo.StatsGovernanceRuns r JOIN dbo.StatsGovernanceRunDatabases d ON d.RunID=r.RunID
    WHERE r.RunID=@RunID AND r.RunStatus='RUNNING' AND d.DatabaseName=@DatabaseName COLLATE Latin1_General_100_BIN2;
    IF @Mode IS NULL THROW 51061,'An active run/database selection is required for scope revalidation.',1;
    BEGIN TRY
        IF NOT EXISTS(SELECT 1 FROM sys.databases WHERE database_id=@ExpectedID
            AND name=@DatabaseName COLLATE Latin1_General_100_BIN2 AND CONVERT(datetime2(7),create_date)=@ExpectedCreated)
            THROW 51062,'Database identity changed since selection. Review database creation, rename, restore, and scope configuration.',1;
        EXEC dbo.usp_DRE_StatsScopeLookup_v1 @DatabaseName,@Scope OUTPUT;
        IF @InitialStatus='EXCLUDED' OR @Scope.value('(/Scope/IsExcluded/text())[1]','bit')=1
            SELECT @Status='EXCLUDED',@GateReason='DATABASE_EXCLUDED';
        ELSE IF @Mode='ENFORCE' AND ISNULL(@Scope.value('(/Scope/EnabledForEnforcement/text())[1]','bit'),0)<>1
            SELECT @Status='APPROVAL_REVOKED',@GateReason='DATABASE_NOT_APPROVED',
                   @Error=51040,@Message=N'Database approval was revoked; remaining work was skipped.';
        ELSE IF NOT EXISTS(SELECT 1 FROM sys.databases WHERE database_id=@ExpectedID AND database_id<>2
            AND name<>N'SSISDB' AND is_distributor=0 AND state=0
            AND source_database_id IS NULL AND HAS_DBACCESS(name)=1
            AND ISNULL(sys.fn_hadr_is_primary_replica(name),1)=1)
            SELECT @Status='DATABASE_UNAVAILABLE',@GateReason='DATABASE_UNAVAILABLE',
                   @Error=51063,@Message=N'Database is unavailable, unsupported, or no longer hosted on the local primary replica; remaining work was skipped.';
        ELSE SELECT @Status='ALLOWED',@GateReason='SCOPE_ALLOWED',@CanProcess=1;
    END TRY
    BEGIN CATCH
        SELECT @Error=ERROR_NUMBER(),@Message=ERROR_MESSAGE(),@Status='SCOPE_CHECK_FAILED',@GateReason='SCOPE_CHECK_FAILED';
    END CATCH;
    UPDATE dbo.StatsGovernanceRunDatabases
    SET LastScopeStatus=@Status,ScopeAtLastCheckXml=@Scope,LastScopeCheckAtUTC=@CheckUTC,
        CollectionStatus=CASE WHEN @CanProcess=0 AND CollectionStatus='PENDING'
            THEN CASE WHEN @GateReason='DATABASE_EXCLUDED' THEN 'SKIPPED_EXCLUDED' ELSE 'SKIPPED_SCOPE_BLOCKED' END ELSE CollectionStatus END,
        ErrorNumber=COALESCE(@Error,ErrorNumber),ErrorMessage=COALESCE(@Message,ErrorMessage)
    WHERE RunID=@RunID AND DatabaseName=@DatabaseName COLLATE Latin1_General_100_BIN2;
    IF @CanProcess=0
        UPDATE dbo.StatsGovernanceTelemetry
        SET ExecutionStatus=CASE WHEN @GateReason='DATABASE_EXCLUDED' THEN 'SKIPPED_DATABASE_EXCLUDED' ELSE 'SKIPPED_SCOPE_BLOCKED' END,
            ExecutionReason=@GateReason,ErrorNumber=@Error,ErrorMessage=@Message
        WHERE RunID=@RunID AND DatabaseName=@DatabaseName COLLATE Latin1_General_100_BIN2
            AND ExecutionStatus IN ('PENDING','BLOCKED_CAPABILITY');
END;
GO
-- dbo.usp_DRE_StatsGovernanceWorker_v1.sql
IF OBJECT_ID(N'dbo.usp_DRE_StatsGovernanceWorker_v1',N'P') IS NULL EXEC(N'CREATE PROCEDURE dbo.usp_DRE_StatsGovernanceWorker_v1 AS BEGIN SET NOCOUNT ON; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER PROCEDURE dbo.usp_DRE_StatsGovernanceWorker_v1
    @Databases nvarchar(max),
    @Mode varchar(10) = 'RECOMMEND',
    @MAXDOP int = 4,
    @MinRowCountFloor bigint = 1000000,
    @LowSampleThresholdBase decimal(9,4) = 2.0,
    @LargeTableThresholdBase bigint = 20000000,
    @DefaultSamplePercentBase decimal(9,4) = NULL,
    @MaxExecutionTimeMinutes int = 300,
    @IOThroughputTier varchar(8) = 'STANDARD',
    @LegacyCEMultiplier decimal(9,4) = 2.0,
    @TargetTablesXml xml = NULL,
    @StatisticsScope varchar(20) = 'ALL'
AS
BEGIN
    -- Engine v1.3.2. Internal implementation; call a public dispatcher.
    -- The dispatcher applies the validated literal LOCK_TIMEOUT in the SAME
    -- dynamic batch that calls this worker. All nested work inherits it.
    DECLARE @InvocationStartedUTC datetime2(7)=SYSUTCDATETIME();
    SET NOCOUNT ON;
    SET ANSI_WARNINGS ON;
    SET NUMERIC_ROUNDABORT OFF;
    SET ROWCOUNT 0;
    SET ARITHABORT ON;
    SET ANSI_PADDING ON;
    SET CONCAT_NULL_YIELDS_NULL ON;

    -- No unrequested impersonation, TRUSTWORTHY changes, or permission grants.
    IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'),0)<>1
        THROW 51020, 'v1 is an administrative procedure; execute as sysadmin or an authorized sysadmin-owned Agent job.', 1;
    IF @@TRANCOUNT<>0 OR (2 & @@OPTIONS)=2
        THROW 51021, 'Run outside an explicit transaction with IMPLICIT_TRANSACTIONS OFF.', 1;
    IF (CONVERT(int,SERVERPROPERTY('ProductMajorVersion')) NOT IN (13,14,15,16,17)
        AND CONVERT(int,SERVERPROPERTY('EngineEdition'))<>8)
        OR CONVERT(int,SERVERPROPERTY('EngineEdition')) NOT IN (2,3,4,8)
        THROW 51022, 'Unsupported engine/version for v1.', 1;
    IF (SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID())<110
        THROW 51023, 'The utility database compatibility level must be 110 or higher.', 1;

    DECLARE @Capabilities xml;
    EXEC dbo.usp_DRE_StatsCapabilities_v1 @CapabilitiesXml=@Capabilities OUTPUT,@EmitResult=0;
    IF ISNULL(@Capabilities.value('(/Capabilities/SupportedEngine/text())[1]','bit'),0)<>1
        THROW 51046, 'Unrecognized engine/build. Capability rules did not authorize this target.',1;

    SET @Mode=UPPER(LTRIM(RTRIM(@Mode)));
    SET @IOThroughputTier=UPPER(LTRIM(RTRIM(@IOThroughputTier)));
    SET @Databases=LTRIM(RTRIM(@Databases));
    SET @StatisticsScope=UPPER(LTRIM(RTRIM(@StatisticsScope)));
    IF @Mode IS NULL OR @Mode NOT IN ('OBSERVE','RECOMMEND','ENFORCE')
        THROW 51024, 'Mode must be OBSERVE, RECOMMEND, or ENFORCE.', 1;
    IF @Databases IS NULL OR LEN(@Databases)=0
        THROW 51025, 'Specify one database, a comma-separated list, ALL, SYSTEM_DATABASES, or USER_DATABASES.', 1;
    IF @StatisticsScope IS NULL OR @StatisticsScope NOT IN ('ALL','INDEX_ONLY','AUTO_ONLY','USER_ONLY','NON_AUTO')
        THROW 51120, 'StatisticsScope must be ALL, INDEX_ONLY, AUTO_ONLY, USER_ONLY, or NON_AUTO.', 1;
    IF @MAXDOP IS NULL OR @MAXDOP NOT BETWEEN 1 AND 64
        THROW 51026, 'MAXDOP must be 1 through 64; zero/unbounded parallelism is not accepted by this engine.', 1;
    IF @MinRowCountFloor IS NULL OR @MinRowCountFloor<0
       OR @LargeTableThresholdBase IS NULL OR @LargeTableThresholdBase<@MinRowCountFloor
       OR @LargeTableThresholdBase<1
        THROW 51027, 'Invalid row-count floor or large-table threshold.', 1;
    IF @LowSampleThresholdBase IS NULL OR @LowSampleThresholdBase<0 OR @LowSampleThresholdBase>100
       OR (@DefaultSamplePercentBase IS NOT NULL AND (@DefaultSamplePercentBase<=0 OR @DefaultSamplePercentBase>100))
       OR @LegacyCEMultiplier IS NULL OR @LegacyCEMultiplier<1 OR @LegacyCEMultiplier>100
        THROW 51028, 'Invalid percentage or advisory CE multiplier.', 1;
    IF @MaxExecutionTimeMinutes IS NULL OR @MaxExecutionTimeMinutes NOT BETWEEN 0 AND 525600
        THROW 51029, 'MaxExecutionTimeMinutes must be 0 through 525600; zero means unlimited.', 1;
    IF @IOThroughputTier IS NULL OR @IOThroughputTier NOT IN ('LOW','STANDARD','HIGH')
        THROW 51030, 'IOThroughputTier must be LOW, STANDARD, or HIGH.', 1;

    DECLARE @SelectionXml xml;
    EXEC dbo.usp_DRE_StatsDatabaseSelection_v1
        @Databases=@Databases,@SelectionXml=@SelectionXml OUTPUT,@EmitResult=0;
    DECLARE @DbList TABLE
    (
        DatabaseID int NOT NULL PRIMARY KEY,DatabaseName sysname COLLATE DATABASE_DEFAULT NOT NULL,
        DatabaseCreateDateLocal datetime2(7) NOT NULL,IsExcluded bit NOT NULL,
        EnabledForEnforcement bit NOT NULL,ReadyForCollection bit NOT NULL,
        SelectionStatus varchar(24) COLLATE DATABASE_DEFAULT NOT NULL,SelectionReason varchar(80) COLLATE DATABASE_DEFAULT NOT NULL,ScopeXml xml NOT NULL
    );
    INSERT @DbList
    SELECT n.d.value('(DatabaseID/text())[1]','int'),n.d.value('(DatabaseName/text())[1]','nvarchar(128)'),
        n.d.value('(DatabaseCreateDateLocal/text())[1]','datetime2(7)'),n.d.value('(IsExcluded/text())[1]','bit'),
        n.d.value('(EnabledForEnforcement/text())[1]','bit'),n.d.value('(ReadyForCollection/text())[1]','bit'),
        n.d.value('(SelectionStatus/text())[1]','varchar(24)'),n.d.value('(SelectionReason/text())[1]','varchar(80)'),
        n.d.query('Scope')
    FROM @SelectionXml.nodes('/DatabaseSelection/Database') n(d);

    -- Targeted table execution is deliberately restricted to one resolved database.
    -- This protects object-name resolution and prevents the same token from silently
    -- binding to different schemas/tables in different databases.
    DECLARE @TargetDatabaseName sysname=NULL,@TargetXmlDatabaseName sysname=NULL;
    IF @TargetTablesXml IS NOT NULL
    BEGIN
        IF @TargetTablesXml.exist('/TableTargets/Table[1]')<>1
            THROW 51121, 'TargetTablesXml was supplied but contains no canonical table targets.',1;
        IF (SELECT COUNT(*) FROM @DbList)<>1
            THROW 51122, 'Table targeting requires exactly one resolved database.',1;
        SELECT TOP(1) @TargetDatabaseName=DatabaseName FROM @DbList;
        SET @TargetXmlDatabaseName=CASE WHEN @TargetTablesXml.exist('/TableTargets/DatabaseName[1]')=1
             THEN @TargetTablesXml.value('(/TableTargets/DatabaseName/text())[1]','nvarchar(128)') END;
        IF @TargetXmlDatabaseName IS NULL
           OR @TargetXmlDatabaseName COLLATE Latin1_General_100_BIN2<>@TargetDatabaseName COLLATE Latin1_General_100_BIN2
            THROW 51123, 'Canonical target-table database identity does not match the resolved database.',1;
    END;
    -- Excluded databases do not participate in target availability/approval checks.
    IF EXISTS(SELECT 1 FROM @DbList WHERE IsExcluded=0 AND ReadyForCollection=0)
        THROW 51033, 'Non-excluded selections must be online, accessible, non-snapshot supported databases.', 1;
    DECLARE @SelectedDatabaseCount int=(SELECT COUNT(*) FROM @DbList WHERE IsExcluded=0),
            @InitialExcludedDatabaseCount int=(SELECT COUNT(*) FROM @DbList WHERE IsExcluded=1);

    IF @Mode='ENFORCE' AND @SelectedDatabaseCount>0
    BEGIN
        IF OBJECT_ID(N'dbo.CommandLog',N'U') IS NULL
            THROW 51034, 'Install the standard Ola Hallengren dbo.CommandLog table in the utility database before ENFORCE.', 1;
        -- Check standard column types without changing the table.
        IF EXISTS
        (
            SELECT 1 FROM (VALUES
                (N'ID',56,4),(N'DatabaseName',231,256),(N'SchemaName',231,256),
                (N'ObjectName',231,256),(N'ObjectType',175,2),(N'IndexName',231,256),
                (N'IndexType',48,1),(N'StatisticsName',231,256),(N'PartitionNumber',56,4),
                (N'ExtendedInfo',241,-1),(N'Command',231,-1),(N'CommandType',231,120),
                (N'StartTime',42,8),(N'EndTime',42,8),(N'ErrorNumber',56,4),(N'ErrorMessage',231,-1)
            ) expected(ColumnName,TypeID,LengthBytes)
            LEFT JOIN sys.columns c ON c.object_id=OBJECT_ID(N'dbo.CommandLog') AND c.name COLLATE DATABASE_DEFAULT = expected.ColumnName COLLATE DATABASE_DEFAULT
            WHERE c.column_id IS NULL OR c.system_type_id<>expected.TypeID OR c.max_length<>expected.LengthBytes
        ) OR COLUMNPROPERTY(OBJECT_ID(N'dbo.CommandLog'),N'ID','IsIdentity')<>1
            THROW 51035, 'CommandLog does not match the expected standard schema. Review it; do not alter it automatically.', 1;
        IF EXISTS(SELECT 1 FROM @DbList WHERE IsExcluded=0 AND EnabledForEnforcement<>1)
            THROW 51036, 'Every non-excluded database must be explicitly approved in StatsGovernanceScope before ENFORCE.', 1;
    END;

    DECLARE @RunID uniqueidentifier=NEWID(), @StartedUTC datetime2(7)=@InvocationStartedUTC,
            @DeadlineUTC datetime2(7),
            @LockTimeout int, @HaveAppLock bit=0, @LockResult int,
            @FailedCount int=0, @PostcheckFailures int=0, @BlockedCount int=0, @WindowExpired bit=0,
            @Db sysname, @StatsXml xml, @EnvXml xml, @Facts xml, @NewFacts xml,
            @Override xml, @Decision xml, @Policy xml, @Command nvarchar(max),
            @TelemetryID bigint, @LogID int, @ObjectID int, @StatsID int,
            @Schema sysname, @Table sysname, @Stat sysname, @Eligible bit,
            @Reason varchar(80), @Method varchar(16), @Sample decimal(19,6), @SampleRows bigint,
            @CanExecute bit,@CapabilityReason varchar(80),@PostStatus varchar(40),@AfterPersist decimal(19,6),
            @Persist bit, @NoRecompute bit, @IndexName sysname, @IndexType tinyint,
            @ObjectType char(2), @ExtendedInfo xml, @CmdStartedUTC datetime2(7),
            @CmdEndedUTC datetime2(7), @CmdError int, @CmdMessage nvarchar(4000),
            @TraceFlags xml, @LegacyFlag bit=0,@ModernFlag bit=0,@DynamicFlag bit=0,@Progress nvarchar(4000),
            @RunStatus varchar(32), @OverrideID int, @GateAllowed bit, @GateReason varchar(80);

    SET @DeadlineUTC=CASE WHEN @MaxExecutionTimeMinutes=0 THEN NULL
                          ELSE DATEADD(MINUTE,@MaxExecutionTimeMinutes,@StartedUTC) END;
    SELECT @LockTimeout=LockTimeoutMilliseconds,
           @Policy=(SELECT @MinRowCountFloor AS MinRowCountFloor,
                    s.UpdateThresholdPercent,s.MinModificationCount,s.MinUpdateIntervalMinutes,
                    @LowSampleThresholdBase AS LowSampleThresholdBase,
                    @LargeTableThresholdBase AS LargeTableThresholdBase,
                    @DefaultSamplePercentBase AS DefaultSamplePercentBase,
                    @LegacyCEMultiplier AS LegacyCEMultiplier,
                    s.SkewSamplingEnabled,s.ModerateSkewThresholdPercent,
                    s.HighSkewThresholdPercent,s.ExtremeSkewThresholdPercent,
                    s.HighSkewSampleRows,s.ExtremeSkewSampleRows,
                    @Mode AS Mode,@Databases AS Databases,@MAXDOP AS RequestedMAXDOP,
                    @MaxExecutionTimeMinutes AS MaxExecutionTimeMinutes,
                    @IOThroughputTier AS IOThroughputTier,@StatisticsScope AS StatisticsScope,
                    @TargetTablesXml AS TargetTablesXml,s.LockTimeoutMilliseconds,
                    @Capabilities.query('/Capabilities')
                    FOR XML PATH('Policy'),TYPE)
    FROM dbo.StatsGovernanceSettings s WHERE SettingsID=1 AND SchemaVersion='1.3.0';
    IF @Policy IS NULL THROW 51037, 'Missing or incompatible governance settings.', 1;

    CREATE TABLE #SGTraceFlags(TraceFlag int NULL,Status int NULL,[Global] int NULL,[Session] int NULL);
    INSERT #SGTraceFlags EXEC(N'DBCC TRACESTATUS (9481,2312,2371,-1) WITH NO_INFOMSGS;');
    SELECT @TraceFlags=(SELECT * FROM #SGTraceFlags FOR XML PATH('Flag'),ROOT('TraceFlags'),TYPE);
    IF EXISTS(SELECT 1 FROM #SGTraceFlags WHERE TraceFlag=9481 AND Status=1) SET @LegacyFlag=1;
    IF EXISTS(SELECT 1 FROM #SGTraceFlags WHERE TraceFlag=2312 AND Status=1) SET @ModernFlag=1;
    IF EXISTS(SELECT 1 FROM #SGTraceFlags WHERE TraceFlag=2371 AND Status=1 AND [Global]=1) SET @DynamicFlag=1;

    BEGIN TRY
        -- Fail closed if configuration changed between dispatch and policy read,
        -- or a direct caller failed to establish the configured timeout.
        IF @LockTimeout IS NULL OR @@LOCK_TIMEOUT <> @LockTimeout
            THROW 51075, 'Configured lock timeout does not match the active execution scope. Call the public procedure; retry after configuration changes settle.', 1;
        IF @Mode='ENFORCE' AND @SelectedDatabaseCount>0
        BEGIN
            EXEC @LockResult=sys.sp_getapplock
                @Resource=N'DRE.StatsGovernance.v1.ENFORCE',@LockMode='Exclusive',
                @LockOwner='Session',@LockTimeout=0,@DbPrincipal='public';
            IF @LockResult<0 THROW 51038, 'Another enforcement run is active; this run did not start.', 1;
            SET @HaveAppLock=1;
        END;

        INSERT dbo.StatsGovernanceRuns
        (RunID,EngineVersion,Mode,StartedAtUTC,HeartbeatAtUTC,DeadlineUTC,SessionID,
         OriginalLogin,ServerName,ProductVersion,RequestedMAXDOP,ParametersXml,TraceFlagsXml,RunStatus)
        VALUES(@RunID,'1.3.2',@Mode,@StartedUTC,@StartedUTC,@DeadlineUTC,@@SPID,
         ORIGINAL_LOGIN(),CONVERT(sysname,SERVERPROPERTY('ServerName')),
         CONVERT(nvarchar(128),SERVERPROPERTY('ProductVersion')),@MAXDOP,@Policy,@TraceFlags,'RUNNING');
        SET @Progress=N'Governance RunID: '+CONVERT(nvarchar(36),@RunID);
        RAISERROR(N'%s',10,1,@Progress) WITH NOWAIT;
        INSERT dbo.StatsGovernanceRunDatabases
            (RunID,DatabaseName,CollectionStatus,DatabaseIDAtSelection,DatabaseCreateDateAtSelection,
             SelectionStatus,SelectionReason,ScopeAtSelectionXml,LastScopeStatus,ScopeAtLastCheckXml,LastScopeCheckAtUTC)
        SELECT @RunID,DatabaseName,CASE WHEN IsExcluded=1 THEN 'SKIPPED_EXCLUDED' ELSE 'PENDING' END,
            DatabaseID,DatabaseCreateDateLocal,SelectionStatus,SelectionReason,ScopeXml,
            CASE WHEN IsExcluded=1 THEN 'EXCLUDED' ELSE 'ALLOWED' END,ScopeXml,@StartedUTC
        FROM @DbList;

        CREATE TABLE #SGWork
        (
            WorkID int IDENTITY(1,1) NOT NULL PRIMARY KEY,
            FactsXml xml NOT NULL
        );
        DECLARE @WorkID int;
        DECLARE sg_db_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT DatabaseName FROM @DbList WHERE IsExcluded=0 ORDER BY DatabaseName;
        OPEN sg_db_cursor;
        FETCH NEXT FROM sg_db_cursor INTO @Db;
        WHILE @@FETCH_STATUS=0
        BEGIN
            IF @DeadlineUTC IS NOT NULL AND SYSUTCDATETIME()>=@DeadlineUTC
            BEGIN
                SET @WindowExpired=1;
                BREAK;
            END;
            BEGIN TRY
                EXEC dbo.usp_DRE_StatsCheckDatabaseGate_v1 @RunID,@Db,@GateAllowed OUTPUT,@GateReason OUTPUT;
                IF @GateAllowed=0
                BEGIN
                    IF @GateReason<>'DATABASE_EXCLUDED' SET @FailedCount+=1;
                    FETCH NEXT FROM sg_db_cursor INTO @Db;
                    CONTINUE;
                END;
                EXEC dbo.usp_DRE_StatsCollect_v1 @DatabaseName=@Db,
                    @LegacyTraceFlagVisible=@LegacyFlag,@ModernTraceFlagVisible=@ModernFlag,
                    @DynamicStatsTraceFlagGlobal=@DynamicFlag,@CapabilitiesXml=@Capabilities,
                    @TargetTablesXml=@TargetTablesXml,@StatisticsScope=@StatisticsScope,
                    @SnapshotXml=@StatsXml OUTPUT,@EnvironmentXml=@EnvXml OUTPUT;
                EXEC dbo.usp_DRE_StatsCheckDatabaseGate_v1 @RunID,@Db,@GateAllowed OUTPUT,@GateReason OUTPUT;
                IF @GateAllowed=0
                BEGIN
                    -- A scope change during a running metadata query is observed
                    -- here. Do not persist its application-statistic snapshots.
                    IF @GateReason<>'DATABASE_EXCLUDED' SET @FailedCount+=1;
                    FETCH NEXT FROM sg_db_cursor INTO @Db;
                    CONTINUE;
                END;
                TRUNCATE TABLE #SGWork;
                INSERT #SGWork(FactsXml)
                    SELECT n.s.query('.') FROM @StatsXml.nodes('/Statistics/Statistic') AS n(s);
                UPDATE dbo.StatsGovernanceRunDatabases
                    SET CollectionStatus='COLLECTED',EnvironmentXml=@EnvXml,
                        CandidateCount=(SELECT COUNT(*) FROM #SGWork)
                    WHERE RunID=@RunID AND DatabaseName=@Db COLLATE Latin1_General_100_BIN2;
                WHILE EXISTS(SELECT 1 FROM #SGWork)
                BEGIN
                    IF @DeadlineUTC IS NOT NULL AND SYSUTCDATETIME()>=@DeadlineUTC
                    BEGIN
                        SET @WindowExpired=1;
                        UPDATE dbo.StatsGovernanceRunDatabases SET CollectionStatus='PARTIAL_WINDOW'
                        WHERE RunID=@RunID AND DatabaseName=@Db COLLATE Latin1_General_100_BIN2;
                        BREAK;
                    END;
                    EXEC dbo.usp_DRE_StatsCheckDatabaseGate_v1 @RunID,@Db,@GateAllowed OUTPUT,@GateReason OUTPUT;
                    IF @GateAllowed=0
                    BEGIN
                        IF @GateReason<>'DATABASE_EXCLUDED' SET @FailedCount+=1;
                        UPDATE dbo.StatsGovernanceRunDatabases SET CollectionStatus='PARTIAL_SCOPE_CHANGE'
                        WHERE RunID=@RunID AND DatabaseName=@Db COLLATE Latin1_General_100_BIN2;
                        BREAK;
                    END;
                    SELECT TOP(1) @WorkID=WorkID,@Facts=FactsXml FROM #SGWork ORDER BY WorkID;
                    SELECT @Schema=@Facts.value('(/Statistic/SchemaName/text())[1]','nvarchar(128)'),
                           @Table=@Facts.value('(/Statistic/TableName/text())[1]','nvarchar(128)'),
                           @Stat=@Facts.value('(/Statistic/StatName/text())[1]','nvarchar(128)'),
                           @ObjectID=@Facts.value('(/Statistic/ObjectID/text())[1]','int'),
                           @StatsID=@Facts.value('(/Statistic/StatsID/text())[1]','int');
                    EXEC dbo.usp_DRE_StatsOverride_v1 @Db,@Schema,@Table,@Stat,@Override OUTPUT;
                    SELECT @Decision=(SELECT * FROM dbo.ufn_DRE_StatsDecision_v1(@Facts,@Policy,@Override)
                                      FOR XML PATH('Decision'),TYPE);
                    SELECT @Eligible=@Decision.value('(/Decision/IsEligible/text())[1]','bit'),
                           @Reason=@Decision.value('(/Decision/Reason/text())[1]','varchar(80)'),
                           @CanExecute=@Decision.value('(/Decision/CanExecute/text())[1]','bit'),
                           @CapabilityReason=CASE WHEN @Decision.exist('/Decision/CapabilityReason[1]')=1
                               THEN @Decision.value('(/Decision/CapabilityReason/text())[1]','varchar(80)') END,
                           @Method=(CASE WHEN @Decision.exist('/Decision/CollectionMethod[1]')=1 THEN @Decision.value('(/Decision/CollectionMethod/text())[1]','varchar(16)') END),
                           @Sample=(CASE WHEN @Decision.exist('/Decision/RequestedSamplePercent[1]')=1 THEN @Decision.value('(/Decision/RequestedSamplePercent/text())[1]','decimal(19,6)') END),
                           @SampleRows=(CASE WHEN @Decision.exist('/Decision/RequestedSampleRows[1]')=1 THEN @Decision.value('(/Decision/RequestedSampleRows/text())[1]','bigint') END),
                           @Persist=(CASE WHEN @Decision.exist('/Decision/PersistOption[1]')=1 THEN @Decision.value('(/Decision/PersistOption/text())[1]','bit') END),
                           @NoRecompute=@Facts.value('(/Statistic/NoRecompute/text())[1]','bit'),
                           @OverrideID=(CASE WHEN @Override.exist('/Override/OverrideID[1]')=1 THEN @Override.value('(/Override/OverrideID/text())[1]','int') END);
                    SET @Command=NULL;
                    IF @Mode<>'OBSERVE' AND @CanExecute=1
                    BEGIN
                        SET @Command=dbo.ufn_DRE_StatsCommand_v1(@Db,@Schema,@Table,@Stat,@Method,@Sample,@SampleRows,@Persist,@MAXDOP,@NoRecompute,@Capabilities);
                        IF @Command IS NULL THROW 51039, 'Command construction failed; no command was executed.', 1;
                    END;
                    INSERT dbo.StatsGovernanceTelemetry
                    (RunID,DatabaseName,SchemaName,TableName,StatName,ObjectID,StatsID,OverrideID,
                     InitialSnapshotXml,InitialOverrideXml,InitialDecisionXml,RecommendedCommand,ExecutionStatus,ExecutionReason)
                    VALUES(@RunID,@Db,@Schema,@Table,@Stat,@ObjectID,@StatsID,@OverrideID,
                        @Facts,@Override,@Decision,@Command,
                        CASE WHEN @Mode='OBSERVE' THEN 'OBSERVED'
                             WHEN @Eligible=0 THEN 'DEFERRED'
                             WHEN @CanExecute=0 THEN 'BLOCKED_CAPABILITY'
                             WHEN @Mode='RECOMMEND' THEN 'RECOMMENDED' ELSE 'PENDING' END,
                        CASE WHEN @Eligible=1 AND @CanExecute=0 THEN @CapabilityReason ELSE NULL END);
                    IF @Eligible=1 AND @CanExecute=0 SET @BlockedCount+=1;
                    DELETE #SGWork WHERE WorkID=@WorkID;
                END;
            END TRY
            BEGIN CATCH
                UPDATE dbo.StatsGovernanceRunDatabases
                SET CollectionStatus='FAILED',ErrorNumber=ERROR_NUMBER(),ErrorMessage=ERROR_MESSAGE()
                WHERE RunID=@RunID AND DatabaseName=@Db COLLATE Latin1_General_100_BIN2;
                -- Do not execute a partly collected database after a collection failure.
                UPDATE dbo.StatsGovernanceTelemetry
                SET ExecutionStatus='SKIPPED_COLLECTION_ERROR',ExecutionReason='DATABASE_COLLECTION_FAILED'
                WHERE RunID=@RunID AND DatabaseName=@Db COLLATE Latin1_General_100_BIN2 AND ExecutionStatus='PENDING';
                SET @FailedCount+=1;
            END CATCH;
            UPDATE dbo.StatsGovernanceRuns SET HeartbeatAtUTC=SYSUTCDATETIME() WHERE RunID=@RunID;
            FETCH NEXT FROM sg_db_cursor INTO @Db;
        END;
        CLOSE sg_db_cursor;
        DEALLOCATE sg_db_cursor;
        IF @WindowExpired=1
            UPDATE dbo.StatsGovernanceRunDatabases SET CollectionStatus='NOT_COLLECTED_WINDOW'
            WHERE RunID=@RunID AND CollectionStatus='PENDING';

        /* The only CommandLog DML and UPDATE STATISTICS execution are below
           this execution-only boundary. No fallback fake commands are logged. */
        IF @Mode='ENFORCE'
        BEGIN
            WHILE EXISTS(SELECT 1 FROM dbo.StatsGovernanceTelemetry WHERE RunID=@RunID AND ExecutionStatus='PENDING')
            BEGIN
                IF @DeadlineUTC IS NOT NULL AND SYSUTCDATETIME()>=@DeadlineUTC
                BEGIN
                    SET @WindowExpired=1;
                    UPDATE dbo.StatsGovernanceTelemetry
                    SET ExecutionStatus='NOT_STARTED_WINDOW',ExecutionReason='MAINTENANCE_DEADLINE'
                    WHERE RunID=@RunID AND ExecutionStatus='PENDING';
                    BREAK;
                END;
                SELECT TOP(1) @TelemetryID=TelemetryID,@Db=DatabaseName,
                    @Schema=SchemaName,@Table=TableName,@Stat=StatName,@ObjectID=ObjectID,
                    @StatsID=StatsID,@Facts=InitialSnapshotXml
                FROM dbo.StatsGovernanceTelemetry
                WHERE RunID=@RunID AND ExecutionStatus='PENDING'
                ORDER BY TelemetryID;

                EXEC dbo.usp_DRE_StatsCheckDatabaseGate_v1 @RunID,@Db,@GateAllowed OUTPUT,@GateReason OUTPUT;
                IF @GateAllowed=0
                BEGIN
                    IF @GateReason<>'DATABASE_EXCLUDED' SET @FailedCount+=1;
                    CONTINUE;
                END;
                SET @NewFacts=NULL;
                SET @CmdError=0;
                SET @CmdMessage=NULL;
                BEGIN TRY
                    EXEC dbo.usp_DRE_StatsCollect_v1 @DatabaseName=@Db,
                        @ObjectID=@ObjectID,@StatsID=@StatsID,@IncludeEnvironment=0,
                        @LegacyTraceFlagVisible=@LegacyFlag,@ModernTraceFlagVisible=@ModernFlag,
                        @DynamicStatsTraceFlagGlobal=@DynamicFlag,@CapabilitiesXml=@Capabilities,
                        @TargetTablesXml=@TargetTablesXml,@StatisticsScope=@StatisticsScope,
                        @SnapshotXml=@StatsXml OUTPUT,@EnvironmentXml=@EnvXml OUTPUT;
                    SET @NewFacts=@StatsXml.query('/Statistics/Statistic[1]');
                    IF @NewFacts.exist('/Statistic[1]')=0
                        THROW 51041, 'Statistic was dropped or is no longer visible; command skipped.', 1;
                    IF @NewFacts.value('(/Statistic/DatabaseID/text())[1]','int')
                         <>@Facts.value('(/Statistic/DatabaseID/text())[1]','int')
                       OR @NewFacts.value('(/Statistic/SchemaName/text())[1]','nvarchar(128)') COLLATE Latin1_General_100_BIN2
                         <>@Schema COLLATE Latin1_General_100_BIN2
                       OR @NewFacts.value('(/Statistic/TableName/text())[1]','nvarchar(128)') COLLATE Latin1_General_100_BIN2
                         <>@Table COLLATE Latin1_General_100_BIN2
                       OR @NewFacts.value('(/Statistic/StatName/text())[1]','nvarchar(128)') COLLATE Latin1_General_100_BIN2
                         <>@Stat COLLATE Latin1_General_100_BIN2
                       OR @NewFacts.value('(/Statistic/ObjectCreateDateLocal/text())[1]','datetime2(7)')
                         <>@Facts.value('(/Statistic/ObjectCreateDateLocal/text())[1]','datetime2(7)')
                        THROW 51042, 'Object identity/name changed since collection; command skipped.', 1;
                    EXEC dbo.usp_DRE_StatsOverride_v1 @Db,@Schema,@Table,@Stat,@Override OUTPUT;
                    SELECT @Decision=(SELECT * FROM dbo.ufn_DRE_StatsDecision_v1(@NewFacts,@Policy,@Override)
                                      FOR XML PATH('Decision'),TYPE);
                    SELECT @Eligible=@Decision.value('(/Decision/IsEligible/text())[1]','bit'),
                           @Reason=@Decision.value('(/Decision/Reason/text())[1]','varchar(80)'),
                           @CanExecute=@Decision.value('(/Decision/CanExecute/text())[1]','bit'),
                           @CapabilityReason=CASE WHEN @Decision.exist('/Decision/CapabilityReason[1]')=1
                               THEN @Decision.value('(/Decision/CapabilityReason/text())[1]','varchar(80)') END,
                           @Method=(CASE WHEN @Decision.exist('/Decision/CollectionMethod[1]')=1 THEN @Decision.value('(/Decision/CollectionMethod/text())[1]','varchar(16)') END),
                           @Sample=(CASE WHEN @Decision.exist('/Decision/RequestedSamplePercent[1]')=1 THEN @Decision.value('(/Decision/RequestedSamplePercent/text())[1]','decimal(19,6)') END),
                           @SampleRows=(CASE WHEN @Decision.exist('/Decision/RequestedSampleRows[1]')=1 THEN @Decision.value('(/Decision/RequestedSampleRows/text())[1]','bigint') END),
                           @Persist=(CASE WHEN @Decision.exist('/Decision/PersistOption[1]')=1 THEN @Decision.value('(/Decision/PersistOption/text())[1]','bit') END),
                           @NoRecompute=@NewFacts.value('(/Statistic/NoRecompute/text())[1]','bit');
                    UPDATE dbo.StatsGovernanceTelemetry
                    SET RevalidatedSnapshotXml=@NewFacts,RevalidatedOverrideXml=@Override,
                        RevalidatedDecisionXml=@Decision,ExecutionReason=@Reason
                    WHERE TelemetryID=@TelemetryID;
                END TRY
                BEGIN CATCH
                    SET @CmdError=ERROR_NUMBER();
                    SET @CmdMessage=ERROR_MESSAGE();
                    SET @Eligible=0;
                    SET @FailedCount+=1;
                    UPDATE dbo.StatsGovernanceTelemetry
                    SET ExecutionStatus='SKIPPED_REVALIDATION_ERROR',ErrorNumber=@CmdError,ErrorMessage=@CmdMessage
                    WHERE TelemetryID=@TelemetryID;
                END CATCH;

                IF @CmdError=0 AND @Eligible=0
                    UPDATE dbo.StatsGovernanceTelemetry SET ExecutionStatus='SKIPPED_REVALIDATED'
                    WHERE TelemetryID=@TelemetryID;

                IF @CmdError=0 AND @Eligible=1 AND @CanExecute=0
                BEGIN
                    UPDATE dbo.StatsGovernanceTelemetry
                    SET ExecutionStatus='BLOCKED_CAPABILITY',ExecutionReason=@CapabilityReason
                    WHERE TelemetryID=@TelemetryID;
                    SET @BlockedCount+=1;
                END;
                IF @CmdError=0 AND @CanExecute=1
                BEGIN
                    SET @Command=dbo.ufn_DRE_StatsCommand_v1(@Db,@Schema,@Table,@Stat,@Method,@Sample,@SampleRows,@Persist,@MAXDOP,@NoRecompute,@Capabilities);
                    IF @Command IS NULL THROW 51043, 'Invalid revalidated command; stopping without executing it.', 1;
                    SELECT @IndexName=(CASE WHEN @NewFacts.exist('/Statistic/IndexName[1]')=1 THEN @NewFacts.value('(/Statistic/IndexName/text())[1]','nvarchar(128)') END),
                           @IndexType=(CASE WHEN @NewFacts.exist('/Statistic/IndexType[1]')=1 THEN @NewFacts.value('(/Statistic/IndexType/text())[1]','tinyint') END),
                           @ObjectType=@NewFacts.value('(/Statistic/ObjectType/text())[1]','char(2)');
                    SELECT @ExtendedInfo=(SELECT @RunID AS RunID,@TelemetryID AS TelemetryID,
                           'StatsGovernance-v1.3.2' AS Engine,@MAXDOP AS RequestedMAXDOP,
                           @Decision AS PolicyDecision,@NewFacts AS BeforeSnapshot
                           FOR XML PATH('StatisticsGovernance'),TYPE);

                    -- Last checkpoint before logging and starting a command.
                    IF @DeadlineUTC IS NOT NULL AND SYSUTCDATETIME()>=@DeadlineUTC
                        CONTINUE;
                    EXEC dbo.usp_DRE_StatsCheckDatabaseGate_v1 @RunID,@Db,@GateAllowed OUTPUT,@GateReason OUTPUT;
                    IF @GateAllowed=0
                    BEGIN
                        IF @GateReason<>'DATABASE_EXCLUDED' SET @FailedCount+=1;
                        CONTINUE;
                    END;
                    INSERT dbo.CommandLog
                    (DatabaseName,SchemaName,ObjectName,ObjectType,IndexName,IndexType,
                     StatisticsName,PartitionNumber,ExtendedInfo,Command,CommandType,StartTime)
                    VALUES(@Db,@Schema,@Table,@ObjectType,@IndexName,@IndexType,
                         @Stat,NULL,@ExtendedInfo,@Command,N'UPDATE_STATISTICS',SYSDATETIME());
                    SET @LogID=CONVERT(int,SCOPE_IDENTITY());
                    UPDATE dbo.StatsGovernanceTelemetry
                    SET CommandLogID=@LogID,ExecutedCommand=@Command,ExecutionStatus='EXECUTING'
                    WHERE TelemetryID=@TelemetryID;

                    SET @CmdStartedUTC=SYSUTCDATETIME();
                    SET @CmdError=0;
                    SET @CmdMessage=NULL;
                    BEGIN TRY
                        EXEC sys.sp_executesql @Command;
                    END TRY
                    BEGIN CATCH
                        SET @CmdError=ERROR_NUMBER();
                        SET @CmdMessage=ERROR_MESSAGE();
                    END CATCH;
                    SET @CmdEndedUTC=SYSUTCDATETIME();

                    -- Exactly this log row is finalized, including failures.
                    UPDATE dbo.CommandLog
                    SET EndTime=SYSDATETIME(),ErrorNumber=@CmdError,ErrorMessage=@CmdMessage
                    WHERE ID=@LogID;
                    UPDATE dbo.StatsGovernanceTelemetry
                    SET ExecutionStatus=CASE WHEN @CmdError=0 THEN 'SUCCEEDED' ELSE 'FAILED' END,
                        CommandStartedAtUTC=@CmdStartedUTC,CommandEndedAtUTC=@CmdEndedUTC,
                        CommandElapsedMilliseconds=DATEDIFF_BIG(MILLISECOND,@CmdStartedUTC,@CmdEndedUTC),
                        ErrorNumber=@CmdError,ErrorMessage=@CmdMessage
                    WHERE TelemetryID=@TelemetryID;
                    IF @CmdError<>0 SET @FailedCount+=1;
                    ELSE
                    BEGIN
                        -- A postcheck failure must NOT cause the successful command to run again.
                        EXEC dbo.usp_DRE_StatsCheckDatabaseGate_v1 @RunID,@Db,@GateAllowed OUTPUT,@GateReason OUTPUT;
                        IF @GateAllowed=0
                        BEGIN
                            SET @PostcheckFailures+=1;
                            IF @GateReason<>'DATABASE_EXCLUDED' SET @FailedCount+=1;
                            UPDATE dbo.StatsGovernanceTelemetry
                            SET PostcheckStatus='SKIPPED_SCOPE_CHANGE',PostcheckErrorMessage=@GateReason
                            WHERE TelemetryID=@TelemetryID;
                        END
                        ELSE
                        BEGIN
                        BEGIN TRY
                            EXEC dbo.usp_DRE_StatsCollect_v1 @DatabaseName=@Db,
                                @ObjectID=@ObjectID,@StatsID=@StatsID,@IncludeEnvironment=0,
                                @LegacyTraceFlagVisible=@LegacyFlag,@ModernTraceFlagVisible=@ModernFlag,
                                @DynamicStatsTraceFlagGlobal=@DynamicFlag,@CapabilitiesXml=@Capabilities,
                                @TargetTablesXml=@TargetTablesXml,@StatisticsScope=@StatisticsScope,
                                @SnapshotXml=@StatsXml OUTPUT,@EnvironmentXml=@EnvXml OUTPUT;
                            SET @NewFacts=@StatsXml.query('/Statistics/Statistic[1]');
                            SET @AfterPersist=CASE WHEN @NewFacts.exist('/Statistic/PersistedSamplePercent[1]')=1
                                THEN @NewFacts.value('(/Statistic/PersistedSamplePercent/text())[1]','decimal(19,6)') END;
                            SET @PostStatus=CASE
                                WHEN @NewFacts.exist('/Statistic[1]')=0 THEN 'STATISTIC_NOT_FOUND'
                                WHEN @NewFacts.exist('/Statistic/LastUpdatedLocal[1]')=0 THEN 'NO_STATISTICS_BLOB'
                                WHEN @Persist=1 AND (@AfterPersist IS NULL OR ABS(@AfterPersist-@Sample)>0.0001)
                                    THEN 'PERSISTENCE_VALIDATION_FAILED'
                                WHEN @Persist=0 AND (@AfterPersist IS NULL OR @AfterPersist<>0)
                                    THEN 'PERSISTENCE_VALIDATION_FAILED'
                                ELSE 'METADATA_COLLECTED' END;
                            IF @PostStatus<>'METADATA_COLLECTED' SET @PostcheckFailures+=1;
                            UPDATE dbo.StatsGovernanceTelemetry
                            SET AfterSnapshotXml=@NewFacts,PostcheckStatus=@PostStatus
                            WHERE TelemetryID=@TelemetryID;
                        END TRY
                        BEGIN CATCH
                            SET @PostcheckFailures+=1;
                            UPDATE dbo.StatsGovernanceTelemetry
                            SET PostcheckStatus='COLLECTION_FAILED',PostcheckErrorNumber=ERROR_NUMBER(),
                                PostcheckErrorMessage=ERROR_MESSAGE() WHERE TelemetryID=@TelemetryID;
                        END CATCH;
                        END;
                    END;
                END;
                UPDATE dbo.StatsGovernanceRuns SET HeartbeatAtUTC=SYSUTCDATETIME() WHERE RunID=@RunID;
                -- LOW means pacing, NOT lowering sample quality. HIGH does not
                -- increase concurrency: all tiers use a single worker in v1.
                IF @IOThroughputTier='LOW' AND EXISTS
                    (SELECT 1 FROM dbo.StatsGovernanceTelemetry WHERE RunID=@RunID AND ExecutionStatus='PENDING')
                    WAITFOR DELAY '00:00:01';
            END;
        END;

        SELECT @BlockedCount=COUNT(*)
        FROM dbo.StatsGovernanceTelemetry t JOIN dbo.StatsGovernanceRunDatabases d
            ON d.RunID=t.RunID AND d.DatabaseName COLLATE Latin1_General_100_BIN2=t.DatabaseName COLLATE Latin1_General_100_BIN2
        WHERE t.RunID=@RunID AND d.LastScopeStatus='ALLOWED'
            AND ((@Mode='ENFORCE' AND t.ExecutionStatus='BLOCKED_CAPABILITY')
              OR (@Mode<>'ENFORCE' AND t.InitialDecisionXml.value('(/Decision/IsEligible/text())[1]','bit')=1
                AND t.InitialDecisionXml.value('(/Decision/CanExecute/text())[1]','bit')=0));
        SET @RunStatus=CASE WHEN @FailedCount>0 THEN 'COMPLETED_WITH_ERRORS'
                            WHEN @SelectedDatabaseCount=0 THEN 'NO_DATABASES_TO_PROCESS'
                            WHEN @BlockedCount>0 THEN 'COMPLETED_WITH_BLOCKED_ACTIONS'
                            WHEN @WindowExpired=1 THEN 'WINDOW_EXPIRED'
                            WHEN @PostcheckFailures>0 THEN 'COMPLETED_WITH_WARNINGS'
                            ELSE 'COMPLETED' END;
        UPDATE dbo.StatsGovernanceRuns
        SET RunStatus=@RunStatus,FinishedAtUTC=SYSUTCDATETIME(),HeartbeatAtUTC=SYSUTCDATETIME()
        WHERE RunID=@RunID;
        IF @HaveAppLock=1
        BEGIN
            EXEC sys.sp_releaseapplock @Resource=N'DRE.StatsGovernance.v1.ENFORCE',
                @LockOwner='Session',@DbPrincipal='public';
            SET @HaveAppLock=0;
        END;
        -- The dispatcher batch owns LOCK_TIMEOUT; SQL Server restores it on exit.

        SELECT RunID,Mode,RunStatus,StartedAtUTC,FinishedAtUTC,RequestedMAXDOP,
               @FailedCount AS ErrorCount,@BlockedCount AS BlockedCapabilityCount,
               @PostcheckFailures AS PostcheckFailureCount,
               (SELECT COUNT(*) FROM @DbList) AS RequestedDatabaseCount,
               @SelectedDatabaseCount AS InitiallySelectedDatabaseCount,
               @InitialExcludedDatabaseCount AS InitiallyExcludedDatabaseCount,
               (SELECT COUNT(*) FROM dbo.StatsGovernanceRunDatabases
                 WHERE RunID=@RunID AND LastScopeStatus='EXCLUDED') AS ExcludedDatabaseCount
        FROM dbo.StatsGovernanceRuns WHERE RunID=@RunID;
        SELECT * FROM dbo.v_DRE_StatsGovernanceResults_v1 WHERE RunID=@RunID ORDER BY TelemetryID;
        SELECT * FROM dbo.v_DRE_StatsDatabaseSelection_v1 WHERE RunID=@RunID ORDER BY DatabaseName;
        IF @FailedCount>0
            THROW 51044, 'The run completed with errors. Inspect governance telemetry using the printed RunID.', 1;
        IF @Mode='ENFORCE' AND @BlockedCount>0
            THROW 51045, 'Eligible actions were blocked by build/capability checks. No unsupported commands were attempted. Review the RunID.',1;
    END TRY
    BEGIN CATCH
        DECLARE @OuterError int=ERROR_NUMBER(),@OuterMessage nvarchar(4000)=ERROR_MESSAGE();
        IF CURSOR_STATUS('local','sg_db_cursor')>=0 CLOSE sg_db_cursor;
        IF CURSOR_STATUS('local','sg_db_cursor')>=-1 DEALLOCATE sg_db_cursor;
        IF @HaveAppLock=1
            EXEC sys.sp_releaseapplock @Resource=N'DRE.StatsGovernance.v1.ENFORCE',
                @LockOwner='Session',@DbPrincipal='public';
        -- The dispatcher batch owns LOCK_TIMEOUT; SQL Server restores it on exit.
        UPDATE dbo.StatsGovernanceTelemetry
        SET ExecutionStatus='SKIPPED_RUN_ABORTED',ExecutionReason='RUN_ABORTED',
            ErrorNumber=@OuterError,ErrorMessage=@OuterMessage
        WHERE RunID=@RunID AND ExecutionStatus='PENDING';
        UPDATE dbo.StatsGovernanceRunDatabases SET CollectionStatus='NOT_COLLECTED_RUN_ABORTED'
        WHERE RunID=@RunID AND CollectionStatus='PENDING';
        UPDATE dbo.StatsGovernanceRuns
        SET RunStatus=CASE WHEN @OuterError=51044 THEN 'COMPLETED_WITH_ERRORS'
                           WHEN @OuterError=51045 THEN 'COMPLETED_WITH_BLOCKED_ACTIONS' ELSE 'FAILED' END,
            FinishedAtUTC=SYSUTCDATETIME(),HeartbeatAtUTC=SYSUTCDATETIME(),
            ErrorNumber=@OuterError,ErrorMessage=@OuterMessage WHERE RunID=@RunID;
        THROW;
    END CATCH;
END;
GO
-- dbo.usp_DRE_StatsGovernance_v1.sql
IF OBJECT_ID(N'dbo.usp_DRE_StatsGovernance_v1',N'P') IS NULL EXEC(N'CREATE PROCEDURE dbo.usp_DRE_StatsGovernance_v1 AS BEGIN SET NOCOUNT ON; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER PROCEDURE dbo.usp_DRE_StatsGovernance_v1
    @Databases nvarchar(max),
    @Mode varchar(10) = 'RECOMMEND',
    @MAXDOP int = 4,
    @MinRowCountFloor bigint = 1000000,
    @LowSampleThresholdBase decimal(9,4) = 2.0,
    @LargeTableThresholdBase bigint = 20000000,
    @DefaultSamplePercentBase decimal(9,4) = NULL,
    @MaxExecutionTimeMinutes int = 300,
    @IOThroughputTier varchar(8) = 'STANDARD',
    @LegacyCEMultiplier decimal(9,4) = 2.0
AS
BEGIN
    -- Engine v1.3.2: scoped LOCK_TIMEOUT dispatcher. Public interface remains
    -- exactly ten parameters for backward compatibility. Table/statistics-scope
    -- targeting is exposed separately by usp_DRE_StatsGovernanceTargeted_v1.
    SET NOCOUNT ON;
    SET ROWCOUNT 0;
    IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'), 0) <> 1
        THROW 51020, 'v1 is an administrative procedure; execute as sysadmin or an authorized sysadmin-owned Agent job.', 1;
    IF @@TRANCOUNT <> 0 OR (2 & @@OPTIONS) = 2
        THROW 51021, 'Run outside an explicit transaction with IMPLICIT_TRANSACTIONS OFF.', 1;

    DECLARE @LockTimeout int, @DispatchSql nvarchar(max), @ReturnCode int = 0;
    SELECT @LockTimeout = LockTimeoutMilliseconds
    FROM dbo.StatsGovernanceSettings
    WHERE SettingsID = 1 AND SchemaVersion = '1.3.0';
    IF @LockTimeout IS NULL OR @LockTimeout NOT BETWEEN 0 AND 600000
        THROW 51037, 'Missing/incompatible governance settings or lock timeout outside 0 through 600000 milliseconds.', 1;

    -- SET LOCK_TIMEOUT requires a numeric literal, not a local-variable operand.
    -- Only the validated integer is concatenated. Every public input remains a
    -- typed sp_executesql parameter. SET and worker execution stay in one batch.
    SET @DispatchSql = N'SET LOCK_TIMEOUT ' + CONVERT(nvarchar(11), @LockTimeout) + N';
EXEC @WorkerReturnCode = dbo.usp_DRE_StatsGovernanceWorker_v1
    @Databases = @pDatabases,
    @Mode = @pMode,
    @MAXDOP = @pMAXDOP,
    @MinRowCountFloor = @pMinRowCountFloor,
    @LowSampleThresholdBase = @pLowSampleThresholdBase,
    @LargeTableThresholdBase = @pLargeTableThresholdBase,
    @DefaultSamplePercentBase = @pDefaultSamplePercentBase,
    @MaxExecutionTimeMinutes = @pMaxExecutionTimeMinutes,
    @IOThroughputTier = @pIOThroughputTier,
    @LegacyCEMultiplier = @pLegacyCEMultiplier,
    @TargetTablesXml = NULL,
    @StatisticsScope = ''ALL'';';

    EXEC sys.sp_executesql @DispatchSql,
        N'@pDatabases nvarchar(max), @pMode varchar(10), @pMAXDOP int,
          @pMinRowCountFloor bigint, @pLowSampleThresholdBase decimal(9,4),
          @pLargeTableThresholdBase bigint, @pDefaultSamplePercentBase decimal(9,4),
          @pMaxExecutionTimeMinutes int, @pIOThroughputTier varchar(8),
          @pLegacyCEMultiplier decimal(9,4), @WorkerReturnCode int OUTPUT',
        @pDatabases = @Databases,
        @pMode = @Mode,
        @pMAXDOP = @MAXDOP,
        @pMinRowCountFloor = @MinRowCountFloor,
        @pLowSampleThresholdBase = @LowSampleThresholdBase,
        @pLargeTableThresholdBase = @LargeTableThresholdBase,
        @pDefaultSamplePercentBase = @DefaultSamplePercentBase,
        @pMaxExecutionTimeMinutes = @MaxExecutionTimeMinutes,
        @pIOThroughputTier = @IOThroughputTier,
        @pLegacyCEMultiplier = @LegacyCEMultiplier,
        @WorkerReturnCode = @ReturnCode OUTPUT;
    RETURN @ReturnCode;
END;
GO
-- dbo.usp_DRE_StatsGovernanceTargeted_v1.sql
IF OBJECT_ID(N'dbo.usp_DRE_StatsGovernanceTargeted_v1',N'P') IS NULL EXEC(N'CREATE PROCEDURE dbo.usp_DRE_StatsGovernanceTargeted_v1 AS BEGIN SET NOCOUNT ON; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER PROCEDURE dbo.usp_DRE_StatsGovernanceTargeted_v1
    @Databases nvarchar(max),
    @Tables nvarchar(max) = NULL,
    @StatisticsScope varchar(20) = 'ALL',
    @Mode varchar(10) = 'RECOMMEND',
    @MAXDOP int = 4,
    @MinRowCountFloor bigint = 1000000,
    @MaxExecutionTimeMinutes int = 300,
    @IOThroughputTier varchar(8) = 'STANDARD'
AS
BEGIN
    /*
      Targeted public interface intentionally stays below ten parameters.
      Advanced policy knobs remain on dbo.usp_DRE_StatsGovernance_v1 and are
      fixed here to the documented v1.3 targeted defaults:
          LowSampleThresholdBase   = 2.0 percent
          LargeTableThresholdBase = 20,000,000 rows
          DefaultSamplePercentBase= NULL (SQL Server default unless policy/override chooses otherwise)
          LegacyCEMultiplier      = 2.0

      @Tables accepts a comma-separated list of two-part table names:
          schema.table,schema.table
      Bracketed two-part names are accepted by PARSENAME. A comma in an object
      name is not supported by this interface. When @Tables is supplied,
      @Databases must resolve to exactly one database and ALL is rejected.

      @StatisticsScope:
        ALL        = every supported statistic
        INDEX_ONLY = statistics associated with indexes
        AUTO_ONLY  = standalone auto-created statistics only
        USER_ONLY  = standalone user-created statistics only
        NON_AUTO   = every statistic that is not auto-created
    */
    SET NOCOUNT ON;
    SET ROWCOUNT 0;
    IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'),0)<>1
        THROW 51020, 'v1 is an administrative procedure; execute as sysadmin or an authorized sysadmin-owned Agent job.',1;
    IF @@TRANCOUNT<>0 OR (2 & @@OPTIONS)=2
        THROW 51021, 'Run outside an explicit transaction with IMPLICIT_TRANSACTIONS OFF.',1;

    SET @Databases=LTRIM(RTRIM(@Databases));
    SET @StatisticsScope=UPPER(LTRIM(RTRIM(@StatisticsScope)));
    SET @Tables=NULLIF(LTRIM(RTRIM(@Tables)),N'');
    SET @Mode=UPPER(LTRIM(RTRIM(@Mode)));
    SET @IOThroughputTier=UPPER(LTRIM(RTRIM(@IOThroughputTier)));
    IF @Databases IS NULL OR LEN(@Databases)=0
        THROW 51025, 'Specify one database, a comma-separated list, or ALL.',1;
    IF @StatisticsScope IS NULL OR @StatisticsScope NOT IN ('ALL','INDEX_ONLY','AUTO_ONLY','USER_ONLY','NON_AUTO')
        THROW 51120, 'StatisticsScope must be ALL, INDEX_ONLY, AUTO_ONLY, USER_ONLY, or NON_AUTO.',1;

    DECLARE @TargetTablesXml xml=NULL,@ResolvedDatabase sysname=NULL;
    IF @Tables IS NOT NULL
    BEGIN
        IF UPPER(@Databases) IN ('ALL','SYSTEM_DATABASES','USER_DATABASES')
            THROW 51130, 'When @Tables is supplied, @Databases must name exactly one database; database-group selectors are not allowed.',1;

        DECLARE @SelectionXml xml;
        EXEC dbo.usp_DRE_StatsDatabaseSelection_v1
            @Databases=@Databases,@SelectionXml=@SelectionXml OUTPUT,@EmitResult=0;
        IF @SelectionXml IS NULL OR @SelectionXml.value('count(/DatabaseSelection/Database)','int')<>1
            THROW 51131, 'When @Tables is supplied, @Databases must resolve to exactly one database.',1;
        SET @ResolvedDatabase=@SelectionXml.value('(/DatabaseSelection/Database/DatabaseName/text())[1]','nvarchar(128)');
        IF ISNULL(@SelectionXml.value('(/DatabaseSelection/Database/ReadyForCollection/text())[1]','bit'),0)<>1
            THROW 51132, 'The single targeted database must be online, accessible, non-snapshot, and ready for metadata resolution.',1;

        DECLARE @Compact nvarchar(max)=REPLACE(REPLACE(REPLACE(REPLACE(@Tables,N' ',N''),NCHAR(9),N''),NCHAR(13),N''),NCHAR(10),N'');
        IF LEFT(@Compact,1)=N',' OR RIGHT(@Compact,1)=N',' OR CHARINDEX(N',,',@Compact)>0
            THROW 51133, 'The @Tables list contains an empty item.',1;

        CREATE TABLE #RequestedTargets
        (
            SchemaName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
            TableName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
            PRIMARY KEY(SchemaName,TableName)
        );
        CREATE TABLE #CanonicalTargets
        (
            SchemaName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
            TableName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
            PRIMARY KEY(SchemaName,TableName)
        );
        CREATE TABLE #MissingTargets
        (
            SchemaName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
            TableName sysname COLLATE Latin1_General_100_BIN2 NOT NULL,
            PRIMARY KEY(SchemaName,TableName)
        );

        DECLARE @TableTokens TABLE(Token nvarchar(max) COLLATE Latin1_General_100_BIN2 NOT NULL);
        DECLARE @TokenStart int=1,@TokenEnd int;
        WHILE 1=1
        BEGIN
            SET @TokenEnd=CHARINDEX(N',',@Tables,@TokenStart);
            IF @TokenEnd=0
            BEGIN
                INSERT @TableTokens(Token) VALUES(LTRIM(RTRIM(SUBSTRING(@Tables,@TokenStart,LEN(@Tables)-@TokenStart+1))));
                BREAK;
            END;
            INSERT @TableTokens(Token) VALUES(LTRIM(RTRIM(SUBSTRING(@Tables,@TokenStart,@TokenEnd-@TokenStart))));
            SET @TokenStart=@TokenEnd+1;
        END;

        DECLARE @BadToken nvarchar(4000)=NULL;
        SELECT TOP(1) @BadToken=Token
        FROM @TableTokens
        WHERE PARSENAME(Token,1) IS NULL
           OR PARSENAME(Token,2) IS NULL
           OR PARSENAME(Token,3) IS NOT NULL
           OR PARSENAME(Token,4) IS NOT NULL;
        IF @BadToken IS NOT NULL
            THROW 51134, 'Every @Tables item must be a valid two-part schema.table identifier.',1;

        INSERT #RequestedTargets(SchemaName,TableName)
        SELECT DISTINCT CONVERT(sysname,PARSENAME(Token,2)),
                        CONVERT(sysname,PARSENAME(Token,1))
        FROM @TableTokens;
        IF NOT EXISTS(SELECT 1 FROM #RequestedTargets)
            THROW 51135, 'No table targets were parsed from @Tables.',1;

        DECLARE @ResolveSql nvarchar(max)=N'USE '+QUOTENAME(@ResolvedDatabase)+N';
INSERT #MissingTargets(SchemaName,TableName)
SELECT r.SchemaName,r.TableName
FROM #RequestedTargets AS r
WHERE NOT EXISTS
(
    SELECT 1
    FROM sys.tables AS t
    JOIN sys.schemas AS s ON s.schema_id=t.schema_id
    WHERE (t.is_ms_shipped=0 OR DB_ID() IN (1,3,4)) AND t.is_external=0
      AND s.name COLLATE DATABASE_DEFAULT=r.SchemaName COLLATE DATABASE_DEFAULT
      AND t.name COLLATE DATABASE_DEFAULT=r.TableName COLLATE DATABASE_DEFAULT
);
INSERT #CanonicalTargets(SchemaName,TableName)
SELECT DISTINCT s.name,t.name
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id=t.schema_id
JOIN #RequestedTargets AS r
  ON s.name COLLATE DATABASE_DEFAULT=r.SchemaName COLLATE DATABASE_DEFAULT
 AND t.name COLLATE DATABASE_DEFAULT=r.TableName COLLATE DATABASE_DEFAULT
WHERE (t.is_ms_shipped=0 OR DB_ID() IN (1,3,4)) AND t.is_external=0;';
        EXEC sys.sp_executesql @ResolveSql;

        IF EXISTS(SELECT 1 FROM #MissingTargets)
        BEGIN
            DECLARE @MissingSchema sysname,@MissingTable sysname,@MissingMessage nvarchar(2048);
            SELECT TOP(1) @MissingSchema=SchemaName,@MissingTable=TableName
            FROM #MissingTargets ORDER BY SchemaName,TableName;
            SET @MissingMessage=N'Target table not found: '+QUOTENAME(@ResolvedDatabase)+N'.'+QUOTENAME(@MissingSchema)+N'.'+QUOTENAME(@MissingTable)+N'.';
            THROW 51136,@MissingMessage,1;
        END;

        SELECT @TargetTablesXml=
        (
            SELECT @ResolvedDatabase AS DatabaseName,
                   (SELECT SchemaName,TableName FROM #CanonicalTargets ORDER BY SchemaName,TableName FOR XML PATH('Table'),TYPE)
            FOR XML PATH('TableTargets'),TYPE
        );
        IF @TargetTablesXml IS NULL OR @TargetTablesXml.exist('/TableTargets/Table[1]')<>1
            THROW 51137, 'Canonical target-table resolution returned no tables.',1;
    END;

    -- Keep the targeted interface operationally compact. These four advanced
    -- controls use the same documented defaults as the legacy public procedure.
    DECLARE @LowSampleThresholdBase decimal(9,4)=2.0,
            @LargeTableThresholdBase bigint=20000000,
            @DefaultSamplePercentBase decimal(9,4)=NULL,
            @LegacyCEMultiplier decimal(9,4)=2.0;

    DECLARE @LockTimeout int,@DispatchSql nvarchar(max),@ReturnCode int=0;
    SELECT @LockTimeout=LockTimeoutMilliseconds
    FROM dbo.StatsGovernanceSettings
    WHERE SettingsID=1 AND SchemaVersion='1.3.0';
    IF @LockTimeout IS NULL OR @LockTimeout NOT BETWEEN 0 AND 600000
        THROW 51037, 'Missing/incompatible governance settings or lock timeout outside 0 through 600000 milliseconds.',1;

    SET @DispatchSql=N'SET LOCK_TIMEOUT '+CONVERT(nvarchar(11),@LockTimeout)+N';
EXEC @WorkerReturnCode = dbo.usp_DRE_StatsGovernanceWorker_v1
    @Databases=@pDatabases,
    @Mode=@pMode,
    @MAXDOP=@pMAXDOP,
    @MinRowCountFloor=@pMinRowCountFloor,
    @LowSampleThresholdBase=@pLowSampleThresholdBase,
    @LargeTableThresholdBase=@pLargeTableThresholdBase,
    @DefaultSamplePercentBase=@pDefaultSamplePercentBase,
    @MaxExecutionTimeMinutes=@pMaxExecutionTimeMinutes,
    @IOThroughputTier=@pIOThroughputTier,
    @LegacyCEMultiplier=@pLegacyCEMultiplier,
    @TargetTablesXml=@pTargetTablesXml,
    @StatisticsScope=@pStatisticsScope;';

    EXEC sys.sp_executesql @DispatchSql,
        N'@pDatabases nvarchar(max),@pMode varchar(10),@pMAXDOP int,
          @pMinRowCountFloor bigint,@pLowSampleThresholdBase decimal(9,4),
          @pLargeTableThresholdBase bigint,@pDefaultSamplePercentBase decimal(9,4),
          @pMaxExecutionTimeMinutes int,@pIOThroughputTier varchar(8),
          @pLegacyCEMultiplier decimal(9,4),@pTargetTablesXml xml,
          @pStatisticsScope varchar(20),@WorkerReturnCode int OUTPUT',
        @pDatabases=@Databases,@pMode=@Mode,@pMAXDOP=@MAXDOP,
        @pMinRowCountFloor=@MinRowCountFloor,@pLowSampleThresholdBase=@LowSampleThresholdBase,
        @pLargeTableThresholdBase=@LargeTableThresholdBase,@pDefaultSamplePercentBase=@DefaultSamplePercentBase,
        @pMaxExecutionTimeMinutes=@MaxExecutionTimeMinutes,@pIOThroughputTier=@IOThroughputTier,
        @pLegacyCEMultiplier=@LegacyCEMultiplier,@pTargetTablesXml=@TargetTablesXml,
        @pStatisticsScope=@StatisticsScope,@WorkerReturnCode=@ReturnCode OUTPUT;
    RETURN @ReturnCode;
END;
GO
-- dbo.v_DRE_StatsColumnstoreHealth_v1.sql
IF OBJECT_ID(N'dbo.v_DRE_StatsColumnstoreHealth_v1',N'V') IS NULL EXEC(N'CREATE VIEW dbo.v_DRE_StatsColumnstoreHealth_v1 AS SELECT CONVERT(int,1) AS Placeholder;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER VIEW dbo.v_DRE_StatsColumnstoreHealth_v1
AS
SELECT d.RunID,d.DatabaseName,
       n.p.value('(SchemaName/text())[1]','nvarchar(128)') AS SchemaName,
       n.p.value('(TableName/text())[1]','nvarchar(128)') AS TableName,
       n.p.value('(IndexName/text())[1]','nvarchar(128)') AS IndexName,
       n.p.value('(IndexID/text())[1]','int') AS IndexID,
       n.p.value('(PartitionNumber/text())[1]','int') AS PartitionNumber,
       n.p.value('(OpenRowgroups/text())[1]','bigint') AS OpenRowgroups,
       n.p.value('(ClosedRowgroups/text())[1]','bigint') AS ClosedRowgroups,
       n.p.value('(DeltaRows/text())[1]','bigint') AS DeltaRows,
       n.p.value('(CompressedPhysicalRows/text())[1]','bigint') AS CompressedPhysicalRows,
       n.p.value('(CompressedDeletedRows/text())[1]','bigint') AS CompressedDeletedRows,
       CASE WHEN n.p.exist('DeltaPercentApprox[1]')=1
            THEN n.p.value('(DeltaPercentApprox/text())[1]','decimal(19,6)') END AS DeltaPercentApprox,
       n.p.value('(MeasurementNote/text())[1]','nvarchar(200)') AS MeasurementNote
FROM dbo.StatsGovernanceRunDatabases AS d
CROSS APPLY d.EnvironmentXml.nodes('/Environment/ColumnstoreHealth/IndexPartition') AS n(p);
GO
-- dbo.v_DRE_StatsDatabaseContext_v1.sql
IF OBJECT_ID(N'dbo.v_DRE_StatsDatabaseContext_v1',N'V') IS NULL EXEC(N'CREATE VIEW dbo.v_DRE_StatsDatabaseContext_v1 AS SELECT CONVERT(int,1) AS Placeholder;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER VIEW dbo.v_DRE_StatsDatabaseContext_v1
AS
SELECT d.RunID,r.EngineVersion,d.DatabaseName,d.CollectionStatus,r.RequestedMAXDOP,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/ProductVersion[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/ProductVersion/text())[1]','nvarchar(128)') END AS DetectedProductVersion,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/ProductLevel[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/ProductLevel/text())[1]','nvarchar(128)') END AS ProductLevel,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/ProductUpdateLevel[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/ProductUpdateLevel/text())[1]','nvarchar(128)') END AS ProductUpdateLevel,
    CASE WHEN d.EnvironmentXml.exist('/Environment/CompatibilityLevel[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/CompatibilityLevel/text())[1]','int') END AS CompatibilityLevel,
    CASE WHEN d.EnvironmentXml.exist('/Environment/ScopedLegacyCE[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/ScopedLegacyCE/text())[1]','bit') END AS ScopedLegacyCE,
    CASE WHEN d.EnvironmentXml.exist('/Environment/LegacyTraceFlagVisible[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/LegacyTraceFlagVisible/text())[1]','bit') END AS LegacyTraceFlagVisible,
    CASE WHEN d.EnvironmentXml.exist('/Environment/ModernTraceFlagVisible[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/ModernTraceFlagVisible/text())[1]','bit') END AS ModernTraceFlagVisible,
    CASE WHEN d.EnvironmentXml.exist('/Environment/GlobalTraceFlag2371[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/GlobalTraceFlag2371/text())[1]','bit') END AS GlobalTraceFlag2371,
    CASE WHEN d.EnvironmentXml.exist('/Environment/AutoUpdateThresholdContext[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/AutoUpdateThresholdContext/text())[1]','varchar(80)') END AS AutoUpdateThresholdContext,
    CASE WHEN d.EnvironmentXml.exist('/Environment/DatabaseScopedMAXDOP[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/DatabaseScopedMAXDOP/text())[1]','int') END AS DatabaseScopedMAXDOP,
    CASE WHEN d.EnvironmentXml.exist('/Environment/ServerMAXDOP[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/ServerMAXDOP/text())[1]','int') END AS ServerMAXDOP,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/SupportsStatisticsMAXDOP[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/SupportsStatisticsMAXDOP/text())[1]','bit') END AS SupportsStatisticsMAXDOP,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/SupportsPersistSamplePercent[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/SupportsPersistSamplePercent/text())[1]','bit') END AS SupportsPersistSamplePercent,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/HasPersistedSamplePercentMetadata[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/HasPersistedSamplePercentMetadata/text())[1]','bit') END AS HasPersistedSamplePercentMetadata,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/PreservesPersistedSampleAfterRebuild[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/PreservesPersistedSampleAfterRebuild/text())[1]','bit') END AS PreservesPersistedSampleAfterRebuild,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/PersistedMetadataProbeStatus[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/PersistedMetadataProbeStatus/text())[1]','varchar(40)') END AS PersistedMetadataProbeStatus,
    CASE WHEN d.EnvironmentXml.exist('/Environment/QueryStoreState[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/QueryStoreState/text())[1]','nvarchar(60)') END AS QueryStoreState,
    CASE WHEN d.EnvironmentXml.exist('/Environment/QueryStoreWaitEvidenceStatus[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/QueryStoreWaitEvidenceStatus/text())[1]','varchar(80)') END AS QueryStoreWaitEvidenceStatus,
    CASE WHEN d.EnvironmentXml.exist('/Environment/CEFeedbackEvidenceStatus[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/CEFeedbackEvidenceStatus/text())[1]','varchar(80)') END AS CEFeedbackEvidenceStatus,
    CASE WHEN d.EnvironmentXml.exist('/Environment/ExpectedSamplingScanBehavior[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/ExpectedSamplingScanBehavior/text())[1]','varchar(100)') END AS ExpectedSamplingScanBehavior
FROM dbo.StatsGovernanceRunDatabases d JOIN dbo.StatsGovernanceRuns r ON r.RunID=d.RunID;
GO
-- dbo.v_DRE_StatsDatabaseSelection_v1.sql
IF OBJECT_ID(N'dbo.v_DRE_StatsDatabaseSelection_v1',N'V') IS NULL EXEC(N'CREATE VIEW dbo.v_DRE_StatsDatabaseSelection_v1 AS SELECT CONVERT(int,1) AS Placeholder;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER VIEW dbo.v_DRE_StatsDatabaseSelection_v1
AS
SELECT d.RunID,r.EngineVersion,r.Mode,r.RunStatus,d.DatabaseName,
    d.DatabaseIDAtSelection,d.DatabaseCreateDateAtSelection,d.SelectionStatus,d.SelectionReason,
    d.CollectionStatus,d.CandidateCount,d.LastScopeStatus,d.LastScopeCheckAtUTC,
    CASE WHEN d.ScopeAtSelectionXml.exist('/Scope/IsExcluded[1]')=1
        THEN d.ScopeAtSelectionXml.value('(/Scope/IsExcluded/text())[1]','bit') END AS InitiallyExcluded,
    CASE WHEN d.ScopeAtSelectionXml.exist('/Scope/ExclusionReason[1]')=1
        THEN d.ScopeAtSelectionXml.value('(/Scope/ExclusionReason/text())[1]','nvarchar(2000)') END AS InitialExclusionReason,
    CASE WHEN d.ScopeAtLastCheckXml.exist('/Scope/ExclusionReason[1]')=1
        THEN d.ScopeAtLastCheckXml.value('(/Scope/ExclusionReason/text())[1]','nvarchar(2000)') END AS LastExclusionReason,
    CASE WHEN d.ScopeAtLastCheckXml.exist('/Scope/ExcludedBy[1]')=1
        THEN d.ScopeAtLastCheckXml.value('(/Scope/ExcludedBy/text())[1]','nvarchar(128)') END AS ExcludedBy,
    CASE WHEN d.ScopeAtLastCheckXml.exist('/Scope/ExcludedAtUTC[1]')=1
        THEN d.ScopeAtLastCheckXml.value('(/Scope/ExcludedAtUTC/text())[1]','datetime2(7)') END AS ExcludedAtUTC,
    CASE WHEN d.ScopeAtLastCheckXml.exist('/Scope/EnabledForEnforcement[1]')=1
        THEN d.ScopeAtLastCheckXml.value('(/Scope/EnabledForEnforcement/text())[1]','bit') END AS LastEnforcementApproval,
    d.ErrorNumber,d.ErrorMessage,d.ScopeAtSelectionXml,d.ScopeAtLastCheckXml,d.EnvironmentXml
FROM dbo.StatsGovernanceRunDatabases d JOIN dbo.StatsGovernanceRuns r ON r.RunID=d.RunID;
GO
-- dbo.v_DRE_StatsGovernanceResults_v1.sql
IF OBJECT_ID(N'dbo.v_DRE_StatsGovernanceResults_v1',N'V') IS NULL EXEC(N'CREATE VIEW dbo.v_DRE_StatsGovernanceResults_v1 AS SELECT CONVERT(int,1) AS Placeholder;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER VIEW dbo.v_DRE_StatsGovernanceResults_v1
AS
SELECT t.TelemetryID,t.RunID,r.Mode,t.DatabaseName,t.SchemaName,t.TableName,t.StatName,
    t.InitialSnapshotXml.value('(/Statistic/StatisticType/text())[1]','varchar(20)') AS StatisticType,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/IndexName[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/IndexName/text())[1]','nvarchar(128)') END AS IndexName,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/IndexType[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/IndexType/text())[1]','tinyint') END AS IndexType,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/IndexTypeDescription[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/IndexTypeDescription/text())[1]','nvarchar(60)') END AS IndexTypeDescription,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/IndexFamily[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/IndexFamily/text())[1]','varchar(20)') END AS IndexFamily,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/StatisticsContext[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/StatisticsContext/text())[1]','varchar(50)') END AS StatisticsContext,
    t.InitialSnapshotXml.value('(/Statistic/BaseStorage/text())[1]','varchar(30)') AS BaseStorage,
    t.InitialSnapshotXml.value('(/Statistic/HasColumnstore/text())[1]','bit') AS HasColumnstore,
    t.InitialSnapshotXml.value('(/Statistic/IsIncremental/text())[1]','bit') AS IsIncremental,
    t.InitialSnapshotXml.value('(/Statistic/HasFilter/text())[1]','bit') AS HasFilter,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/CurrentTableRows[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/CurrentTableRows/text())[1]','bigint') END AS CurrentTableRows,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/StatsRows[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/StatsRows/text())[1]','bigint') END AS StatsRowsAtLastUpdate,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/UnfilteredRowsAtLastUpdate[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/UnfilteredRowsAtLastUpdate/text())[1]','bigint') END AS UnfilteredRowsAtLastUpdate,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/RowCountDeltaSinceStatsUpdate[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/RowCountDeltaSinceStatsUpdate/text())[1]','bigint') END AS RowCountDeltaSinceStatsUpdate,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/RowsSampled[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/RowsSampled/text())[1]','bigint') END AS RowsSampledBefore,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/ModificationCounter[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/ModificationCounter/text())[1]','bigint') END AS ModificationCounter,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/NoRecompute[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/NoRecompute/text())[1]','bit') END AS NoRecompute,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdBasisRows[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdBasisRows/text())[1]','bigint') END AS AutoUpdateThresholdBasisRows,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/EstimatedAutoUpdateThresholdModifications[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/EstimatedAutoUpdateThresholdModifications/text())[1]','bigint') END AS EstimatedAutoUpdateThresholdModifications,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/EstimatedNextAutoUpdateAtModificationCounter[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/EstimatedNextAutoUpdateAtModificationCounter/text())[1]','bigint') END AS EstimatedNextAutoUpdateAtModificationCounter,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdIsEstimate[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdIsEstimate/text())[1]','bit') END AS AutoUpdateThresholdIsEstimate,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/EstimatedModificationsRemainingToAutoUpdate[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/EstimatedModificationsRemainingToAutoUpdate/text())[1]','bigint') END AS EstimatedModificationsRemainingToAutoUpdate,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdProgressPercent[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdProgressPercent/text())[1]','decimal(19,6)') END AS AutoUpdateThresholdProgressPercent,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdReached[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdReached/text())[1]','bit') END AS AutoUpdateThresholdReached,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdPolicy[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdPolicy/text())[1]','varchar(48)') END AS AutoUpdateThresholdPolicy,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdFormula[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdFormula/text())[1]','varchar(100)') END AS AutoUpdateThresholdFormula,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdApplicable[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdApplicable/text())[1]','bit') END AS AutoUpdateThresholdApplicable,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateThresholdState[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateThresholdState/text())[1]','varchar(64)') END AS AutoUpdateThresholdState,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateStatisticsOn[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateStatisticsOn/text())[1]','bit') END AS AutoUpdateStatisticsOn,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/AutoUpdateStatisticsAsyncOn[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/AutoUpdateStatisticsAsyncOn/text())[1]','bit') END AS AutoUpdateStatisticsAsyncOn,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/ThresholdProductMajorVersion[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/ThresholdProductMajorVersion/text())[1]','int') END AS ThresholdProductMajorVersion,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/ThresholdCompatibilityLevel[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/ThresholdCompatibilityLevel/text())[1]','int') END AS ThresholdCompatibilityLevel,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/ThresholdTraceFlag2371[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/ThresholdTraceFlag2371/text())[1]','bit') END AS ThresholdTraceFlag2371,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/ThresholdCEContext[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/ThresholdCEContext/text())[1]','varchar(32)') END AS ThresholdCEContext,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceThresholdBasisRows[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceThresholdBasisRows/text())[1]','bigint') END AS GovernanceThresholdBasisRows,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceEffectiveModificationThreshold[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceEffectiveModificationThreshold/text())[1]','bigint') END AS GovernanceEffectiveModificationThreshold,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceModificationsRemaining[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceModificationsRemaining/text())[1]','bigint') END AS GovernanceModificationsRemaining,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceThresholdProgressPercent[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceThresholdProgressPercent/text())[1]','decimal(19,6)') END AS GovernanceThresholdProgressPercent,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceThresholdReached[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceThresholdReached/text())[1]','bit') END AS GovernanceThresholdReached,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceVsNativeThresholdDeltaModifications[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceVsNativeThresholdDeltaModifications/text())[1]','bigint') END AS GovernanceVsNativeThresholdDeltaModifications,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/GovernanceVsNativeThresholdComparison[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/GovernanceVsNativeThresholdComparison/text())[1]','varchar(32)') END AS GovernanceVsNativeThresholdComparison,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/LastUpdatedLocal[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/LastUpdatedLocal/text())[1]','datetime2(7)') END AS LastUpdatedLocalBefore,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/ModRatioPercent[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/ModRatioPercent/text())[1]','decimal(28,6)') END AS ModRatioPercent,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/ActualSamplePercent[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/ActualSamplePercent/text())[1]','decimal(19,6)') END AS ActualSamplePercentBefore,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/PersistedSamplePercent[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/PersistedSamplePercent/text())[1]','decimal(19,6)') END AS PersistedSamplePercentBefore,
    t.InitialDecisionXml.value('(/Decision/LowSampleWarning/text())[1]','bit') AS LowSampleWarning,
    t.InitialDecisionXml.value('(/Decision/EffectiveLowSampleThresholdPercent/text())[1]','decimal(19,6)') AS EffectiveLowSampleThresholdPercent,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/LegacyCEContext[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/LegacyCEContext/text())[1]','bit') END AS LegacyCEContext,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/HistogramAnalysisStatus[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/HistogramAnalysisStatus/text())[1]','varchar(40)') END AS HistogramAnalysisStatus,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/HistogramDominantEqualityPercent[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/HistogramDominantEqualityPercent/text())[1]','decimal(19,6)') END AS HistogramDominantEqualityPercent,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/HistogramTop3EqualityPercent[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/HistogramTop3EqualityPercent/text())[1]','decimal(19,6)') END AS HistogramTop3EqualityPercent,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/SkewClassification[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/SkewClassification/text())[1]','varchar(12)') END AS SkewClassification,
    t.InitialDecisionXml.value('(/Decision/IsEligible/text())[1]','bit') AS InitiallyEligible,
    t.InitialDecisionXml.value('(/Decision/Reason/text())[1]','varchar(80)') AS InitialReason,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/CollectionMethod[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/CollectionMethod/text())[1]','varchar(16)') END AS ProposedMethod,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/SamplingSource[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/SamplingSource/text())[1]','varchar(48)') END AS SamplingSource,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/RequestedSamplePercent[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/RequestedSamplePercent/text())[1]','decimal(19,6)') END AS RequestedSamplePercent,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/RequestedSampleRows[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/RequestedSampleRows/text())[1]','bigint') END AS RequestedSampleRows,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/PersistOption[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/PersistOption/text())[1]','bit') END AS ProposedPersistOption,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/FullscanEligible[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/FullscanEligible/text())[1]','bit') END AS FullscanEligible,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/FullscanReason[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/FullscanReason/text())[1]','varchar(80)') END AS FullscanReason,
    CASE WHEN r.ParametersXml.exist('/Policy/StatisticsScope[1]')=1
         THEN r.ParametersXml.value('(/Policy/StatisticsScope/text())[1]','varchar(20)') ELSE 'ALL' END AS StatisticsScope,
    CASE WHEN r.ParametersXml.exist('/Policy/TargetTablesXml/TableTargets/Table[1]')=1 THEN CONVERT(bit,1) ELSE CONVERT(bit,0) END AS IsTargetedTableRun,
    r.RequestedMAXDOP,t.OverrideID,t.RecommendedCommand,t.ExecutedCommand,t.CommandLogID,
    t.ExecutionStatus,t.ExecutionReason,t.CommandElapsedMilliseconds,
    CASE WHEN t.AfterSnapshotXml.exist('/Statistic/StatsRows[1]')=1
         THEN t.AfterSnapshotXml.value('(/Statistic/StatsRows/text())[1]','bigint') END AS StatsRowsAfter,
    CASE WHEN t.AfterSnapshotXml.exist('/Statistic/RowsSampled[1]')=1
         THEN t.AfterSnapshotXml.value('(/Statistic/RowsSampled/text())[1]','bigint') END AS RowsSampledAfter,
    CASE WHEN t.AfterSnapshotXml.exist('/Statistic/LastUpdatedLocal[1]')=1
         THEN t.AfterSnapshotXml.value('(/Statistic/LastUpdatedLocal/text())[1]','datetime2(7)') END AS LastUpdatedLocalAfter,
    CASE WHEN t.AfterSnapshotXml.exist('/Statistic/PersistedSamplePercent[1]')=1
         THEN t.AfterSnapshotXml.value('(/Statistic/PersistedSamplePercent/text())[1]','decimal(19,6)') END AS PersistedSamplePercentAfter,
    t.PostcheckStatus,t.ErrorNumber,t.ErrorMessage,t.PostcheckErrorNumber,t.PostcheckErrorMessage,
    r.EngineVersion,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/CanExecute[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/CanExecute/text())[1]','bit') END AS InitiallyExecutable,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/CapabilityReason[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/CapabilityReason/text())[1]','varchar(80)') END AS CapabilityReason,
    CASE WHEN t.InitialDecisionXml.exist('/Decision/PersistenceAdvisory[1]')=1
         THEN t.InitialDecisionXml.value('(/Decision/PersistenceAdvisory/text())[1]','varchar(80)') END AS PersistenceAdvisory,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/PersistedSampleMetadataStatus[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/PersistedSampleMetadataStatus/text())[1]','varchar(40)') END AS PersistedSampleMetadataStatus,
    CASE WHEN t.InitialSnapshotXml.exist('/Statistic/ExpectedSamplingScanBehavior[1]')=1
         THEN t.InitialSnapshotXml.value('(/Statistic/ExpectedSamplingScanBehavior/text())[1]','varchar(100)') END AS ExpectedSamplingScanBehavior
FROM dbo.StatsGovernanceTelemetry AS t
JOIN dbo.StatsGovernanceRuns AS r ON r.RunID=t.RunID;
GO
-- dbo.v_DRE_StatsScopeConfiguration_v1.sql
IF OBJECT_ID(N'dbo.v_DRE_StatsScopeConfiguration_v1',N'V') IS NULL EXEC(N'CREATE VIEW dbo.v_DRE_StatsScopeConfiguration_v1 AS SELECT CONVERT(int,1) AS Placeholder;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER VIEW dbo.v_DRE_StatsScopeConfiguration_v1
AS
SELECT s.DatabaseName AS ConfiguredDatabaseName,d.name AS CatalogDatabaseName,d.database_id AS DatabaseID,
    s.IsExcluded,s.EnabledForEnforcement,s.ExclusionReason,s.ExcludedBy,s.ExcludedAtUTC,
    s.ApprovedBy,s.ApprovedAtUTC,s.Notes,sys.fn_varbintohexstr(s.Revision) AS Revision,
    CASE WHEN d.database_id IS NULL THEN 'DATABASE_NOT_FOUND'
         WHEN d.database_id=2 OR d.name=N'SSISDB' OR d.is_distributor=1 THEN 'UNSUPPORTED_DATABASE'
         WHEN ISNULL(sys.fn_hadr_is_primary_replica(d.name),1)=0 THEN 'ALWAYS_ON_SECONDARY'
         WHEN (SELECT COUNT(*) FROM dbo.StatsGovernanceScope x WHERE DB_ID(x.DatabaseName)=d.database_id)>1
             THEN 'AMBIGUOUS_DATABASE_ALIASES'
         WHEN s.DatabaseName<>d.name COLLATE Latin1_General_100_BIN2 THEN 'NONCANONICAL_NAME_REVIEW'
         ELSE 'OK' END AS ConfigurationHealth
FROM dbo.StatsGovernanceScope s LEFT JOIN sys.databases d ON d.database_id=DB_ID(s.DatabaseName);
GO
-- dbo.tr_DRE_StatsScopeAudit_v1.sql
IF OBJECT_ID(N'dbo.tr_DRE_StatsScopeAudit_v1',N'TR') IS NULL EXEC(N'CREATE TRIGGER dbo.tr_DRE_StatsScopeAudit_v1 ON dbo.StatsGovernanceScope AFTER INSERT AS BEGIN RETURN; END;');
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER TRIGGER dbo.tr_DRE_StatsScopeAudit_v1
ON dbo.StatsGovernanceScope
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
    -- A key change is a different database configuration, not a scope edit.
    IF UPDATE(DatabaseName) AND EXISTS(SELECT 1 FROM deleted)
        THROW 51060, 'Do not rename a scope key. Review and create the new database configuration explicitly.',1;
    INSERT dbo.StatsGovernanceScopeAudit
        (DatabaseName,ChangeType,ChangedAtUTC,ChangedBy,SessionID,OldScopeXml,NewScopeXml)
    SELECT COALESCE(i.DatabaseName,d.DatabaseName),
        CASE WHEN d.DatabaseName IS NULL THEN 'INSERT'
             WHEN i.DatabaseName IS NULL THEN 'DELETE' ELSE 'UPDATE' END,
        SYSUTCDATETIME(),ORIGINAL_LOGIN(),@@SPID,
        CASE WHEN d.DatabaseName IS NOT NULL THEN
            (SELECT d.DatabaseName,d.IsExcluded,d.ExclusionReason,d.ExcludedBy,d.ExcludedAtUTC,
                d.EnabledForEnforcement,d.ApprovedBy,d.ApprovedAtUTC,d.Notes,
                sys.fn_varbintohexstr(d.Revision) AS Revision FOR XML PATH('Scope'),TYPE) END,
        CASE WHEN i.DatabaseName IS NOT NULL THEN
            (SELECT i.DatabaseName,i.IsExcluded,i.ExclusionReason,i.ExcludedBy,i.ExcludedAtUTC,
                i.EnabledForEnforcement,i.ApprovedBy,i.ApprovedAtUTC,i.Notes,
                sys.fn_varbintohexstr(i.Revision) AS Revision FOR XML PATH('Scope'),TYPE) END
    FROM inserted i FULL JOIN deleted d ON d.DatabaseName=i.DatabaseName;
END;
GO
COMMIT TRANSACTION;
GO
SELECT N'STATS_GOVERNANCE_V1_3_2_INSTALL_COMPLETE' AS Status;
GO
