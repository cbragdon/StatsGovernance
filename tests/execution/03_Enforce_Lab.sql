SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @StartUTC datetime2(7)=SYSUTCDATETIME();
DECLARE @BeforeLogID int=ISNULL((SELECT MAX(ID) FROM dbo.CommandLog),0);

EXEC dbo.usp_DRE_StatsGovernanceTargeted_v1
    @Databases=N'AdventureWorks2019',
    @Tables=N'DREStatsLab.StatsGovV132Qualification',
    @StatisticsScope='ALL',
    @Mode='ENFORCE',
    @MinRowCountFloor=0,
    @MaxExecutionTimeMinutes=10;

DECLARE @RunID uniqueidentifier;
SELECT TOP (1) @RunID=RunID FROM dbo.StatsGovernanceRuns
WHERE Mode='ENFORCE' AND EngineVersion='1.3.2' AND StartedAtUTC>=@StartUTC
ORDER BY StartedAtUTC DESC;

SELECT N'LAB_ENFORCE' AS Section,StatName,InitiallyEligible,ProposedMethod,
       ExecutionStatus,ExecutionReason,ExecutedCommand,CommandLogID,
       PostcheckStatus,ErrorNumber,ErrorMessage
FROM dbo.v_DRE_StatsGovernanceResults_v1
WHERE RunID=@RunID AND SchemaName=N'DREStatsLab'
  AND TableName=N'StatsGovV132Qualification'
ORDER BY StatName;

SELECT N'LAB_COMMANDLOG' AS Section,ID,DatabaseName,SchemaName,ObjectName,
       Command,StartTime,EndTime,ErrorNumber,ErrorMessage
FROM dbo.CommandLog WHERE ID>@BeforeLogID ORDER BY ID;

IF @RunID IS NULL THROW 51430,'No v1.3.2 ENFORCE run was recorded.',1;
IF (SELECT COUNT(*) FROM dbo.CommandLog WHERE ID>@BeforeLogID)<>2
    THROW 51431,'Expected exactly two CommandLog rows for lab statistics.',1;
IF (SELECT COUNT(*) FROM dbo.StatsGovernanceTelemetry WHERE RunID=@RunID
      AND StatName IN (N'IX_StatsGovV132_GroupKey',N'ST_StatsGovV132_Metric')
      AND ExecutionStatus='SUCCEEDED')<>2
    THROW 51432,'Expected both lab statistics to execute.',1;
IF EXISTS(SELECT 1 FROM dbo.StatsGovernanceTelemetry WHERE RunID=@RunID
          AND (ErrorNumber>0 OR PostcheckErrorNumber>0))
    THROW 51433,'Lab enforcement telemetry contains an error.',1;
IF NOT EXISTS
(
    SELECT 1 FROM dbo.StatsGovernanceTelemetry AS t
    JOIN dbo.CommandLog AS c ON c.ID=t.CommandLogID
    WHERE t.RunID=@RunID AND t.StatName=N'IX_StatsGovV132_GroupKey'
      AND c.ObjectType='U' AND c.IndexName=N'IX_StatsGovV132_GroupKey'
      AND c.IndexType=2
      AND c.StatisticsName COLLATE Latin1_General_100_BIN2=t.StatName
      AND c.Command=t.ExecutedCommand AND c.ErrorNumber=0
)
    THROW 51434,'Index-associated CommandLog mapping mismatch.',1;
IF NOT EXISTS
(
    SELECT 1 FROM dbo.StatsGovernanceTelemetry AS t
    JOIN dbo.CommandLog AS c ON c.ID=t.CommandLogID
    WHERE t.RunID=@RunID AND t.StatName=N'ST_StatsGovV132_Metric'
      AND c.ObjectType='U' AND c.IndexName IS NULL AND c.IndexType IS NULL
      AND c.StatisticsName COLLATE Latin1_General_100_BIN2=t.StatName
      AND c.Command=t.ExecutedCommand AND c.ErrorNumber=0
)
    THROW 51435,'Standalone CommandLog mapping mismatch.',1;

SELECT N'LAB_ENFORCE_PASS' AS Status,@RunID AS RunID;
