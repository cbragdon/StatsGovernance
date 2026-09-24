CREATE VIEW dbo.v_DRE_StatsScopeConfiguration_v1
AS
SELECT s.DatabaseName AS ConfiguredDatabaseName,d.name AS CatalogDatabaseName,d.database_id AS DatabaseID,
    s.IsExcluded,s.EnabledForEnforcement,s.ExclusionReason,s.ExcludedBy,s.ExcludedAtUTC,
    s.ApprovedBy,s.ApprovedAtUTC,s.Notes,sys.fn_varbintohexstr(s.Revision) AS Revision,
    CASE WHEN d.database_id IS NULL THEN 'DATABASE_NOT_FOUND'
         WHEN d.database_id=2 OR d.name=N'SSISDB' OR d.is_distributor=1 THEN 'UNSUPPORTED_DATABASE'
         WHEN ISNULL(sys.fn_hadr_is_primary_replica(d.name),1)=0 THEN 'ALWAYS_ON_SECONDARY'
         WHEN (SELECT COUNT(*) FROM dbo.StatsGovernanceScope x WHERE DB_ID(x.DatabaseName)=d.database_id)>1
             THEN 'AMBIGUOUS_DATABASE_ALIASES'
         WHEN s.DatabaseName<>d.name COLLATE Latin1_General_100_BIN2 THEN 'NONCANONICAL_NAME_REVIEW'
         ELSE 'OK' END AS ConfigurationHealth
FROM dbo.StatsGovernanceScope s LEFT JOIN sys.databases d ON d.database_id=DB_ID(s.DatabaseName);
