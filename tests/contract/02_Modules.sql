USE [DBAdmin];
SET NOCOUNT ON;

IF (SELECT COUNT(*) FROM sys.objects
    WHERE name IN
    (
      N'usp_DRE_StatsScopeLookup_v1',N'usp_DRE_StatsOverride_v1',
      N'usp_DRE_StatsGovernance_v1',N'usp_DRE_StatsGovernanceWorker_v1',
      N'usp_DRE_StatsGovernanceTargeted_v1',N'usp_DRE_StatsDatabaseSelection_v1',
      N'usp_DRE_StatsCollect_v1',N'usp_DRE_StatsCheckDatabaseGate_v1',
      N'usp_DRE_StatsCapabilities_v1',N'usp_DRE_SetStatsDatabaseScope_v1',
      N'ufn_DRE_StatsDecision_v1',N'ufn_DRE_StatsCommand_v1',
      N'ufn_DRE_StatsCapabilities_v1',N'v_DRE_StatsScopeConfiguration_v1',
      N'v_DRE_StatsGovernanceResults_v1',N'v_DRE_StatsDatabaseSelection_v1',
      N'v_DRE_StatsDatabaseContext_v1',N'v_DRE_StatsColumnstoreHealth_v1',
      N'tr_DRE_StatsScopeAudit_v1'
    ) AND SCHEMA_NAME(schema_id)=N'dbo' AND type IN ('P','FN','IF','TF','V','TR'))<>19
    THROW 51600,'Required v1.3.2 module count or schema differs.',1;

IF EXISTS(SELECT 1 FROM sys.objects AS o LEFT JOIN sys.sql_modules AS m
          ON m.object_id=o.object_id
          WHERE o.name LIKE N'%DRE_%' AND SCHEMA_NAME(o.schema_id)=N'dbo'
            AND o.type IN ('P','FN','IF','TF','V','TR') AND m.definition IS NULL)
    THROW 51601,'A governance module definition is unavailable.',1;

DECLARE @Diff int;
;WITH Expected AS
(
    SELECT * FROM (VALUES
      (1,N'@Databases'),(2,N'@Mode'),(3,N'@MAXDOP'),
      (4,N'@MinRowCountFloor'),(5,N'@LowSampleThresholdBase'),
      (6,N'@LargeTableThresholdBase'),(7,N'@DefaultSamplePercentBase'),
      (8,N'@MaxExecutionTimeMinutes'),(9,N'@IOThroughputTier'),
      (10,N'@LegacyCEMultiplier')
    ) AS x(parameter_id,name)
), Actual AS
(
    SELECT parameter_id,name FROM sys.parameters
    WHERE object_id=OBJECT_ID(N'dbo.usp_DRE_StatsGovernance_v1',N'P')
)
SELECT @Diff=COUNT(*) FROM
(
    SELECT parameter_id,name FROM Expected EXCEPT SELECT parameter_id,name FROM Actual
    UNION ALL
    SELECT parameter_id,name FROM Actual EXCEPT SELECT parameter_id,name FROM Expected
) AS d;
IF @Diff<>0 THROW 51602,'Main public parameter contract differs.',1;
;WITH Expected AS
(
    SELECT * FROM (VALUES
      (1,231,-1,0,0),(2,167,10,0,0),(3,56,4,10,0),
      (4,127,8,19,0),(5,106,5,9,4),(6,127,8,19,0),
      (7,106,5,9,4),(8,56,4,10,0),(9,167,8,0,0),
      (10,106,5,9,4)
    ) AS x(parameter_id,system_type_id,max_length,precision,scale)
), Actual AS
(
    SELECT parameter_id,CONVERT(int,system_type_id) AS system_type_id,
           CONVERT(int,max_length) AS max_length,
           CONVERT(int,precision) AS precision,CONVERT(int,scale) AS scale
    FROM sys.parameters
    WHERE object_id=OBJECT_ID(N'dbo.usp_DRE_StatsGovernance_v1',N'P')
)
SELECT @Diff=COUNT(*) FROM
(
    SELECT * FROM Expected EXCEPT SELECT * FROM Actual
    UNION ALL
    SELECT * FROM Actual EXCEPT SELECT * FROM Expected
) AS d;
IF @Diff<>0 THROW 51606,'Main public parameter SQL types differ.',1;

;WITH Expected AS
(
    SELECT * FROM (VALUES
      (1,N'@Databases'),(2,N'@Tables'),(3,N'@StatisticsScope'),
      (4,N'@Mode'),(5,N'@MAXDOP'),(6,N'@MinRowCountFloor'),
      (7,N'@MaxExecutionTimeMinutes'),(8,N'@IOThroughputTier')
    ) AS x(parameter_id,name)
), Actual AS
(
    SELECT parameter_id,name FROM sys.parameters
    WHERE object_id=OBJECT_ID(N'dbo.usp_DRE_StatsGovernanceTargeted_v1',N'P')
)
SELECT @Diff=COUNT(*) FROM
(
    SELECT parameter_id,name FROM Expected EXCEPT SELECT parameter_id,name FROM Actual
    UNION ALL
    SELECT parameter_id,name FROM Actual EXCEPT SELECT parameter_id,name FROM Expected
) AS d;
IF @Diff<>0 THROW 51603,'Targeted public parameter contract differs.',1;
;WITH Expected AS
(
    SELECT * FROM (VALUES
      (1,231,-1,0,0),(2,231,-1,0,0),(3,167,20,0,0),
      (4,167,10,0,0),(5,56,4,10,0),(6,127,8,19,0),
      (7,56,4,10,0),(8,167,8,0,0)
    ) AS x(parameter_id,system_type_id,max_length,precision,scale)
), Actual AS
(
    SELECT parameter_id,CONVERT(int,system_type_id) AS system_type_id,
           CONVERT(int,max_length) AS max_length,
           CONVERT(int,precision) AS precision,CONVERT(int,scale) AS scale
    FROM sys.parameters
    WHERE object_id=OBJECT_ID(N'dbo.usp_DRE_StatsGovernanceTargeted_v1',N'P')
)
SELECT @Diff=COUNT(*) FROM
(
    SELECT * FROM Expected EXCEPT SELECT * FROM Actual
    UNION ALL
    SELECT * FROM Actual EXCEPT SELECT * FROM Expected
) AS d;
IF @Diff<>0 THROW 51607,'Targeted public parameter SQL types differ.',1;

IF COL_LENGTH(N'dbo.CommandLog',N'Command') IS NULL
 OR COL_LENGTH(N'dbo.CommandLog',N'CommandType') IS NULL
 OR COL_LENGTH(N'dbo.CommandLog',N'StatisticsName') IS NULL
 OR COL_LENGTH(N'dbo.CommandLog',N'IndexName') IS NULL
 OR COL_LENGTH(N'dbo.CommandLog',N'IndexType') IS NULL
 OR COL_LENGTH(N'dbo.CommandLog',N'ErrorNumber') IS NULL
    THROW 51604,'Required CommandLog columns differ.',1;

IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.CommandLog')
              AND name=N'IndexType' AND system_type_id=48 AND is_nullable=1)
    THROW 51605,'CommandLog IndexType contract differs.',1;

SELECT N'MODULE_AND_PUBLIC_CONTRACT_PASS' AS Status;
