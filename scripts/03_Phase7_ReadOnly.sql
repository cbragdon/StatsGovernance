USE [DBAdmin];
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

SELECT N'LAB_OBJECT' AS Section, s.name AS SchemaName, t.name AS TableName,
       t.create_date, t.modify_date
FROM AdventureWorks2019.sys.tables AS t
JOIN AdventureWorks2019.sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name = N'DREStatsLab' AND t.name = N'StatsEnforceQualification';

SELECT N'ENFORCE_RUN' AS Section, RunID, EngineVersion, Mode, StartedAtUTC,
       FinishedAtUTC, RunStatus, ErrorNumber, ErrorMessage
FROM dbo.StatsGovernanceRuns
WHERE Mode = 'ENFORCE'
ORDER BY StartedAtUTC DESC;

SELECT N'LAB_TELEMETRY' AS Section, t.TelemetryID, t.RunID, t.DatabaseName,
       t.SchemaName, t.TableName, t.StatName, t.ExecutionStatus,
       t.ExecutionReason, t.CommandLogID, t.CommandStartedAtUTC,
       t.CommandEndedAtUTC, t.PostcheckStatus, t.ErrorNumber,
       t.ErrorMessage, t.ExecutedCommand
FROM dbo.StatsGovernanceTelemetry AS t
WHERE t.DatabaseName = N'AdventureWorks2019'
  AND t.SchemaName = N'DREStatsLab'
  AND t.TableName = N'StatsEnforceQualification'
ORDER BY t.TelemetryID DESC;

SELECT N'LAB_COMMANDLOG' AS Section, ID, DatabaseName, SchemaName,
       ObjectName, ObjectType, IndexName, IndexType, StatisticsName,
       CommandType, StartTime, EndTime, ErrorNumber, ErrorMessage, Command
FROM dbo.CommandLog
WHERE DatabaseName = N'AdventureWorks2019'
  AND SchemaName = N'DREStatsLab'
  AND ObjectName = N'StatsEnforceQualification'
ORDER BY ID DESC;

SELECT N'LAB_OVERRIDES' AS Section, OverrideID, DatabaseName, SchemaName,
       TableName, StatName, OverrideAction, SamplePercent, SampleRows,
       PersistenceMode, ForceUpdate, IsEnabled, ExpiresAtUTC,
       sys.fn_varbintohexstr(Revision) AS RevisionHex
FROM dbo.StatsGovernanceOverrides
WHERE DatabaseName = N'AdventureWorks2019'
  AND SchemaName = N'DREStatsLab'
  AND TableName = N'StatsEnforceQualification'
ORDER BY OverrideID;

SELECT N'AW_SCOPE' AS Section, DatabaseName, EnabledForEnforcement,
       ApprovedAtUTC, Notes, IsExcluded, ExclusionReason,
       sys.fn_varbintohexstr(Revision) AS RevisionHex
FROM dbo.StatsGovernanceScope
WHERE DatabaseName = N'AdventureWorks2019';

SELECT N'PHASE7_READ_ONLY_COMPLETE' AS Status;
