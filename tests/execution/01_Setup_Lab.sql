SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;

IF (SELECT MinUpdateIntervalMinutes FROM dbo.StatsGovernanceSettings WHERE SettingsID=1)<>60
    THROW 51403,'Expected the default 60-minute cooldown; inspect before lab setup.',1;
IF EXISTS(SELECT 1 FROM dbo.StatsGovernanceScope WHERE DatabaseName=N'AdventureWorks2019')
    THROW 51401,'AdventureWorks2019 already has a scope row; do not overwrite it in this lab setup.',1;
IF EXISTS(SELECT 1 FROM dbo.StatsGovernanceOverrides
          WHERE DatabaseName=N'AdventureWorks2019'
            AND SchemaName=N'DREStatsLab'
            AND TableName=N'StatsGovV132Qualification')
    THROW 51402,'Lab override rows already exist; inspect them before setup.',1;

IF EXISTS(SELECT 1 FROM AdventureWorks2019.sys.schemas WHERE name=N'DREStatsLab')
    THROW 51404,'The DREStatsLab schema already exists; inspect it before setup.',1;
IF OBJECT_ID(N'AdventureWorks2019.DREStatsLab.StatsGovV132Qualification',N'U') IS NOT NULL
    THROW 51400,'The v1.3.2 qualification table already exists. Inspect it before setup.',1;

EXEC AdventureWorks2019.sys.sp_executesql N'CREATE SCHEMA DREStatsLab AUTHORIZATION dbo;';
EXEC AdventureWorks2019.sys.sp_executesql N'
CREATE TABLE DREStatsLab.StatsGovV132Qualification
(
    ID int NOT NULL CONSTRAINT PK_StatsGovV132Qualification PRIMARY KEY CLUSTERED,
    GroupKey int NOT NULL,
    Metric int NOT NULL,
    Padding char(100) NULL
);

;WITH n AS
(
    SELECT TOP (30000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS ID
    FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b
)
INSERT DREStatsLab.StatsGovV132Qualification(ID,GroupKey,Metric,Padding)
SELECT CONVERT(int,ID),CONVERT(int,ID%1000),CONVERT(int,ID%2000),NULL
FROM n;

CREATE NONCLUSTERED INDEX IX_StatsGovV132_GroupKey
ON DREStatsLab.StatsGovV132Qualification(GroupKey);
CREATE STATISTICS ST_StatsGovV132_Metric
ON DREStatsLab.StatsGovV132Qualification(Metric);

UPDATE DREStatsLab.StatsGovV132Qualification
SET GroupKey=GroupKey+1,Metric=Metric+1
WHERE ID<=5000;

SELECT N''LAB_STATS_BEFORE'' AS Section,s.name,sp.rows,sp.rows_sampled,
       sp.modification_counter,sp.persisted_sample_percent
FROM sys.stats AS s
OUTER APPLY sys.dm_db_stats_properties(s.object_id,s.stats_id) AS sp
WHERE s.object_id=OBJECT_ID(N''DREStatsLab.StatsGovV132Qualification'')
ORDER BY s.stats_id;';

UPDATE dbo.StatsGovernanceSettings
SET MinUpdateIntervalMinutes=0 WHERE SettingsID=1;

EXEC dbo.usp_DRE_SetStatsDatabaseScope_v1
    @DatabaseName=N'AdventureWorks2019',
    @IsExcluded=0,
    @EnabledForEnforcement=1,
    @Notes=N'Controlled v1.3.2 dedicated-lab qualification; temporary approval.';

INSERT dbo.StatsGovernanceOverrides
    (DatabaseName,SchemaName,TableName,StatName,OverrideAction,
     SampleRows,PersistenceMode,ForceUpdate,ApprovedBy,ExpiresAtUTC,Notes)
VALUES
    (N'AdventureWorks2019',N'DREStatsLab',N'StatsGovV132Qualification',
     N'IX_StatsGovV132_GroupKey','FORCE_SAMPLE_ROWS',2500,'OFF',1,
     ORIGINAL_LOGIN(),DATEADD(hour,2,SYSUTCDATETIME()),
     N'Controlled v1.3.2 SAMPLE ROWS execution qualification.'),
    (N'AdventureWorks2019',N'DREStatsLab',N'StatsGovV132Qualification',
     N'ST_StatsGovV132_Metric','FORCE_FULLSCAN',NULL,'OFF',1,
     ORIGINAL_LOGIN(),DATEADD(hour,2,SYSUTCDATETIME()),
     N'Controlled v1.3.2 FULLSCAN execution qualification.');

SELECT N'LAB_SETUP_COMPLETE' AS Status;
