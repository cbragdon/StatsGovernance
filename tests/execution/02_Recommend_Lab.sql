SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @StartUTC datetime2(7)=SYSUTCDATETIME();
DECLARE @BeforeLogID int=ISNULL((SELECT MAX(ID) FROM dbo.CommandLog),0);

EXEC dbo.usp_DRE_StatsGovernanceTargeted_v1
    @Databases=N'AdventureWorks2019',
    @Tables=N'DREStatsLab.StatsGovV132Qualification',
    @StatisticsScope='ALL',
    @Mode='RECOMMEND',
    @MinRowCountFloor=0,
    @MaxExecutionTimeMinutes=10;

DECLARE @RunID uniqueidentifier;
SELECT TOP (1) @RunID=RunID
FROM dbo.StatsGovernanceRuns
WHERE Mode='RECOMMEND' AND EngineVersion='1.3.2'
  AND StartedAtUTC>=@StartUTC
ORDER BY StartedAtUTC DESC;

SELECT N'LAB_RECOMMEND' AS Section,StatName,InitiallyEligible,
       ProposedMethod,RequestedSampleRows,RequestedSamplePercent,
       ProposedPersistOption,InitiallyExecutable,ExecutionStatus,RecommendedCommand
FROM dbo.v_DRE_StatsGovernanceResults_v1
WHERE RunID=@RunID AND SchemaName=N'DREStatsLab'
  AND TableName=N'StatsGovV132Qualification'
ORDER BY StatName;

IF @RunID IS NULL
    THROW 51410,'No v1.3.2 RECOMMEND run was recorded.',1;
IF EXISTS(SELECT 1 FROM dbo.CommandLog WHERE ID>@BeforeLogID)
    THROW 51411,'RECOMMEND wrote CommandLog.',1;
IF NOT EXISTS
(
    SELECT 1 FROM dbo.v_DRE_StatsGovernanceResults_v1
    WHERE RunID=@RunID AND StatName=N'IX_StatsGovV132_GroupKey'
      AND InitiallyEligible=1 AND InitiallyExecutable=1
      AND ProposedMethod='SAMPLE_ROWS' AND RequestedSampleRows=2500
      AND ProposedPersistOption=0
)
    THROW 51412,'Index-associated SAMPLE ROWS recommendation mismatch.',1;
IF NOT EXISTS
(
    SELECT 1 FROM dbo.v_DRE_StatsGovernanceResults_v1
    WHERE RunID=@RunID AND StatName=N'ST_StatsGovV132_Metric'
      AND InitiallyEligible=1 AND InitiallyExecutable=1
      AND ProposedMethod='FULLSCAN' AND ProposedPersistOption=0
)
    THROW 51413,'Standalone FULLSCAN recommendation mismatch.',1;

SELECT N'LAB_RECOMMEND_PASS' AS Status,@RunID AS RunID;
