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
