SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @BeforeLogID int=ISNULL((SELECT MAX(ID) FROM dbo.CommandLog),0);
DECLARE @StartedUTC datetime2(7)=SYSUTCDATETIME(),@RunID uniqueidentifier;

EXEC dbo.usp_DRE_StatsGovernance_v1
    @Databases=N'SYSTEM_DATABASES',
    @Mode='OBSERVE',
    @MinRowCountFloor=0,
    @MaxExecutionTimeMinutes=30;

SELECT TOP(1) @RunID=RunID
FROM dbo.StatsGovernanceRuns
WHERE StartedAtUTC>=@StartedUTC AND Mode='OBSERVE'
ORDER BY StartedAtUTC DESC;

IF @RunID IS NULL
    THROW 51720,'SYSTEM_DATABASES OBSERVE run was not recorded.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.StatsGovernanceRuns WHERE RunID=@RunID AND RunStatus='COMPLETED')
    THROW 51721,'SYSTEM_DATABASES OBSERVE run did not complete.',1;
IF EXISTS
(
    SELECT 1 FROM dbo.StatsGovernanceRunDatabases
    WHERE RunID=@RunID
      AND (DatabaseName=N'tempdb' OR DatabaseName=N'SSISDB'
           OR SelectionReason=N'ALWAYS_ON_SECONDARY_REPLICA')
)
    THROW 51722,'SYSTEM_DATABASES processed an excluded database category.',1;
IF EXISTS
(
    SELECT 1 FROM dbo.StatsGovernanceRunDatabases
    WHERE RunID=@RunID AND CollectionStatus<>'COLLECTED'
)
    THROW 51723,'A supported system database was not collected.',1;
IF EXISTS(SELECT 1 FROM dbo.CommandLog WHERE ID>@BeforeLogID)
    THROW 51724,'System-database OBSERVE wrote CommandLog.',1;

SELECT N'SYSTEM_DATABASE_OBSERVE_PASS' AS Status,@RunID AS RunID;
