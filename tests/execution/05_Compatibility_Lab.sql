USE [master];
SET NOCOUNT ON;
IF DB_ID(N'StatsGovCompatLabV132') IS NOT NULL
    THROW 51450,'Compatibility lab database already exists; inspect it before rerun.',1;
CREATE DATABASE [StatsGovCompatLabV132];
GO
USE [StatsGovCompatLabV132];
CREATE TABLE dbo.CompatProbe(ID int NOT NULL PRIMARY KEY, GroupKey int NOT NULL);
;WITH n AS
(
    SELECT TOP (1000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS ID
    FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b
)
INSERT dbo.CompatProbe(ID,GroupKey)
SELECT CONVERT(int,ID),CONVERT(int,ID%20) FROM n;
CREATE STATISTICS ST_CompatProbe_GroupKey ON dbo.CompatProbe(GroupKey);
GO
USE [DBAdmin];
SET NOCOUNT ON;
DECLARE @Levels TABLE(LevelValue int NOT NULL PRIMARY KEY);
INSERT @Levels(LevelValue) VALUES(110),(120),(130),(140),(150),(160),(170);
DECLARE @Level int,@RunID uniqueidentifier,@StartUTC datetime2(7),@sql nvarchar(max);
DECLARE levels CURSOR LOCAL FAST_FORWARD FOR SELECT LevelValue FROM @Levels ORDER BY LevelValue;
OPEN levels;
FETCH NEXT FROM levels INTO @Level;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @sql=N'ALTER DATABASE [StatsGovCompatLabV132] SET COMPATIBILITY_LEVEL = '+CONVERT(nvarchar(3),@Level)+N';';
    EXEC(@sql);
    SET @StartUTC=SYSUTCDATETIME();
    EXEC dbo.usp_DRE_StatsGovernanceTargeted_v1
        @Databases=N'StatsGovCompatLabV132',@Tables=N'dbo.CompatProbe',
        @StatisticsScope='USER_ONLY',@Mode='OBSERVE',@MinRowCountFloor=0,
        @MaxExecutionTimeMinutes=5;
    SELECT TOP(1) @RunID=RunID FROM dbo.StatsGovernanceRuns
    WHERE Mode='OBSERVE' AND StartedAtUTC>=@StartUTC ORDER BY StartedAtUTC DESC;
    IF @RunID IS NULL THROW 51451,'Compatibility OBSERVE run missing.',1;
    IF NOT EXISTS(SELECT 1 FROM dbo.v_DRE_StatsDatabaseContext_v1
                  WHERE RunID=@RunID AND DatabaseName=N'StatsGovCompatLabV132'
                    AND CompatibilityLevel=@Level AND CollectionStatus='COLLECTED')
        THROW 51452,'Compatibility context was not collected at requested level.',1;
    IF NOT EXISTS(SELECT 1 FROM dbo.v_DRE_StatsGovernanceResults_v1
                  WHERE RunID=@RunID AND DatabaseName=N'StatsGovCompatLabV132'
                    AND StatName=N'ST_CompatProbe_GroupKey'
                    AND ThresholdCompatibilityLevel=@Level)
        THROW 51453,'Compatibility statistic result missing or wrong level.',1;
    SELECT N'COMPAT_LEVEL_PASS' AS Status,@Level AS CompatibilityLevel,@RunID AS RunID;
    SET @RunID=NULL;
    FETCH NEXT FROM levels INTO @Level;
END;
CLOSE levels;
DEALLOCATE levels;
GO
USE [StatsGovCompatLabV132];
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;
GO
USE [DBAdmin];
SET NOCOUNT ON;
DECLARE @StartUTC datetime2(7)=SYSUTCDATETIME(),@RunID uniqueidentifier;
EXEC dbo.usp_DRE_StatsGovernanceTargeted_v1
    @Databases=N'StatsGovCompatLabV132',@Tables=N'dbo.CompatProbe',
    @StatisticsScope='USER_ONLY',@Mode='OBSERVE',@MinRowCountFloor=0,
    @MaxExecutionTimeMinutes=5;
SELECT TOP(1) @RunID=RunID FROM dbo.StatsGovernanceRuns
WHERE Mode='OBSERVE' AND StartedAtUTC>=@StartUTC ORDER BY StartedAtUTC DESC;
IF NOT EXISTS(SELECT 1 FROM dbo.v_DRE_StatsDatabaseContext_v1
              WHERE RunID=@RunID AND DatabaseName=N'StatsGovCompatLabV132'
                AND CompatibilityLevel=170 AND ScopedLegacyCE=1)
    THROW 51454,'CE70 context was not detected.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.v_DRE_StatsGovernanceResults_v1
              WHERE RunID=@RunID AND StatName=N'ST_CompatProbe_GroupKey'
                AND LegacyCEContext=1 AND ISNULL(ProposedMethod,'')<>'FULLSCAN')
    THROW 51455,'CE70 statistic policy missing or unexpected FULLSCAN.',1;
SELECT N'CE70_PASS' AS Status,@RunID AS RunID;
