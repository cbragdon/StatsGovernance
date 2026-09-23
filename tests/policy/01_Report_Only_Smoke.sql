USE [DBAdmin];
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @BeforeLogID int=ISNULL((SELECT MAX(ID) FROM dbo.CommandLog),0);
DECLARE @StartedUTC datetime2(7)=SYSUTCDATETIME();

EXEC dbo.usp_DRE_StatsGovernanceTargeted_v1
    @Databases=N'AdventureWorks2019',
    @Tables=N'Sales.SalesOrderHeader',
    @StatisticsScope='INDEX_ONLY',
    @Mode='OBSERVE',
    @MinRowCountFloor=0,
    @MaxExecutionTimeMinutes=10;

EXEC dbo.usp_DRE_StatsGovernanceTargeted_v1
    @Databases=N'AdventureWorks2019',
    @Tables=N'Sales.SalesOrderHeader',
    @StatisticsScope='USER_ONLY',
    @Mode='RECOMMEND',
    @MinRowCountFloor=0,
    @MaxExecutionTimeMinutes=10;

IF EXISTS (SELECT 1 FROM dbo.CommandLog WHERE ID>@BeforeLogID)
    THROW 51300,'Report-only mode wrote CommandLog.',1;

SELECT RunID,EngineVersion,Mode,RunStatus,StartedAtUTC,FinishedAtUTC
FROM dbo.StatsGovernanceRuns
WHERE StartedAtUTC>=@StartedUTC
ORDER BY StartedAtUTC;

IF (SELECT COUNT(*) FROM dbo.StatsGovernanceRuns
    WHERE StartedAtUTC>=@StartedUTC AND EngineVersion='1.3.2'
      AND RunStatus='COMPLETED' AND Mode IN ('OBSERVE','RECOMMEND'))<>2
    THROW 51301,'Expected two completed v1.3.2 report-only runs.',1;

SELECT N'REPORT_ONLY_SMOKE_PASS' AS Status;
