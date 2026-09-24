SET NOCOUNT ON;
SET XACT_ABORT ON;

IF (SELECT MinUpdateIntervalMinutes FROM dbo.StatsGovernanceSettings WHERE SettingsID=1)<>0
    THROW 51440,'Unexpected cooldown setting; inspect before cleanup.',1;
UPDATE dbo.StatsGovernanceSettings
SET MinUpdateIntervalMinutes=60 WHERE SettingsID=1;

EXEC dbo.usp_DRE_SetStatsDatabaseScope_v1
    @DatabaseName=N'AdventureWorks2019',
    @EnabledForEnforcement=0,
    @Notes=N'Controlled v1.3.2 qualification complete; remove temporary approval.';

DELETE FROM dbo.StatsGovernanceOverrides
WHERE DatabaseName=N'AdventureWorks2019'
  AND SchemaName=N'DREStatsLab'
  AND TableName=N'StatsGovV132Qualification'
  AND ((StatName=N'IX_StatsGovV132_GroupKey' AND OverrideAction='FORCE_SAMPLE_ROWS')
    OR (StatName=N'ST_StatsGovV132_Metric' AND OverrideAction='FORCE_FULLSCAN'))
  AND Notes LIKE N'Controlled v1.3.2%qualification.';
IF @@ROWCOUNT<>2 THROW 51441,'Expected to remove exactly two lab overrides.',1;

DELETE FROM dbo.StatsGovernanceScope
WHERE DatabaseName=N'AdventureWorks2019'
  AND EnabledForEnforcement=0
  AND Notes=N'Controlled v1.3.2 qualification complete; remove temporary approval.';
IF @@ROWCOUNT<>1 THROW 51442,'Expected to remove one temporary lab scope row.',1;

IF OBJECT_ID(N'AdventureWorks2019.DREStatsLab.StatsGovV132Qualification',N'U') IS NULL
    THROW 51443,'Lab table missing; inspect before cleanup.',1;
EXEC AdventureWorks2019.sys.sp_executesql N'
DROP TABLE DREStatsLab.StatsGovV132Qualification;
IF SCHEMA_ID(N''DREStatsLab'') IS NOT NULL EXEC(N''DROP SCHEMA DREStatsLab;'');';

IF (SELECT MinUpdateIntervalMinutes FROM dbo.StatsGovernanceSettings WHERE SettingsID=1)<>60
    THROW 51444,'Cooldown restoration failed.',1;
IF EXISTS(SELECT 1 FROM dbo.StatsGovernanceScope WHERE DatabaseName=N'AdventureWorks2019')
    THROW 51445,'Temporary scope row remains.',1;
SELECT N'LAB_CLEANUP_PASS' AS Status;
