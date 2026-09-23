CREATE VIEW dbo.v_DRE_StatsDatabaseContext_v1
AS
SELECT d.RunID,r.EngineVersion,d.DatabaseName,d.CollectionStatus,r.RequestedMAXDOP,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/ProductVersion[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/ProductVersion/text())[1]','nvarchar(128)') END AS DetectedProductVersion,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/ProductLevel[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/ProductLevel/text())[1]','nvarchar(128)') END AS ProductLevel,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/ProductUpdateLevel[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/ProductUpdateLevel/text())[1]','nvarchar(128)') END AS ProductUpdateLevel,
    CASE WHEN d.EnvironmentXml.exist('/Environment/CompatibilityLevel[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/CompatibilityLevel/text())[1]','int') END AS CompatibilityLevel,
    CASE WHEN d.EnvironmentXml.exist('/Environment/ScopedLegacyCE[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/ScopedLegacyCE/text())[1]','bit') END AS ScopedLegacyCE,
    CASE WHEN d.EnvironmentXml.exist('/Environment/LegacyTraceFlagVisible[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/LegacyTraceFlagVisible/text())[1]','bit') END AS LegacyTraceFlagVisible,
    CASE WHEN d.EnvironmentXml.exist('/Environment/ModernTraceFlagVisible[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/ModernTraceFlagVisible/text())[1]','bit') END AS ModernTraceFlagVisible,
    CASE WHEN d.EnvironmentXml.exist('/Environment/GlobalTraceFlag2371[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/GlobalTraceFlag2371/text())[1]','bit') END AS GlobalTraceFlag2371,
    CASE WHEN d.EnvironmentXml.exist('/Environment/AutoUpdateThresholdContext[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/AutoUpdateThresholdContext/text())[1]','varchar(80)') END AS AutoUpdateThresholdContext,
    CASE WHEN d.EnvironmentXml.exist('/Environment/DatabaseScopedMAXDOP[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/DatabaseScopedMAXDOP/text())[1]','int') END AS DatabaseScopedMAXDOP,
    CASE WHEN d.EnvironmentXml.exist('/Environment/ServerMAXDOP[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/ServerMAXDOP/text())[1]','int') END AS ServerMAXDOP,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/SupportsStatisticsMAXDOP[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/SupportsStatisticsMAXDOP/text())[1]','bit') END AS SupportsStatisticsMAXDOP,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/SupportsPersistSamplePercent[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/SupportsPersistSamplePercent/text())[1]','bit') END AS SupportsPersistSamplePercent,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/HasPersistedSamplePercentMetadata[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/HasPersistedSamplePercentMetadata/text())[1]','bit') END AS HasPersistedSamplePercentMetadata,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/PreservesPersistedSampleAfterRebuild[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/PreservesPersistedSampleAfterRebuild/text())[1]','bit') END AS PreservesPersistedSampleAfterRebuild,
    CASE WHEN d.EnvironmentXml.exist('/Environment/Capabilities/PersistedMetadataProbeStatus[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/Capabilities/PersistedMetadataProbeStatus/text())[1]','varchar(40)') END AS PersistedMetadataProbeStatus,
    CASE WHEN d.EnvironmentXml.exist('/Environment/QueryStoreState[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/QueryStoreState/text())[1]','nvarchar(60)') END AS QueryStoreState,
    CASE WHEN d.EnvironmentXml.exist('/Environment/QueryStoreWaitEvidenceStatus[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/QueryStoreWaitEvidenceStatus/text())[1]','varchar(80)') END AS QueryStoreWaitEvidenceStatus,
    CASE WHEN d.EnvironmentXml.exist('/Environment/CEFeedbackEvidenceStatus[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/CEFeedbackEvidenceStatus/text())[1]','varchar(80)') END AS CEFeedbackEvidenceStatus,
    CASE WHEN d.EnvironmentXml.exist('/Environment/ExpectedSamplingScanBehavior[1]')=1
         THEN d.EnvironmentXml.value('(/Environment/ExpectedSamplingScanBehavior/text())[1]','varchar(100)') END AS ExpectedSamplingScanBehavior
FROM dbo.StatsGovernanceRunDatabases d JOIN dbo.StatsGovernanceRuns r ON r.RunID=d.RunID;
